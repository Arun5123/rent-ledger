import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/ledger_transaction.dart';
import '../../../domain/models/property.dart';
import '../../../domain/models/tenant.dart';
import '../../../domain/services/settlement_calculator.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/auth_providers.dart';
import '../../../providers/property_providers.dart';
import '../../../providers/tenant_providers.dart';
import '../../../providers/transaction_providers.dart';

/// Four step wizard that computes and confirms a tenant's exit settlement.
class TenantExitWizardScreen extends ConsumerStatefulWidget {
  const TenantExitWizardScreen({
    super.key,
    required this.propertyId,
    required this.tenantId,
  });

  final String propertyId;
  final String tenantId;

  @override
  ConsumerState<TenantExitWizardScreen> createState() =>
      _TenantExitWizardScreenState();
}

class _TenantExitWizardScreenState
    extends ConsumerState<TenantExitWizardScreen> {
  final GlobalKey<FormState> _meterFormKey = GlobalKey<FormState>();
  final TextEditingController _meterController = TextEditingController();
  final TextEditingController _deductionReasonController =
      TextEditingController();

  int _step = 0;
  DateTime _exitDate = DateTime.now();
  bool _isProRataExitMonth = true;

  bool _checkNoticePeriod = false;
  DateTime? _noticeDate;
  int _requiredNoticeDays = 30;

  Set<String> _completedChecklist = <String>{};

  double? _overridePendingRent;
  double? _overridePendingMaintenance;
  double? _overridePendingEb;
  double? _overridePendingOther;

  final List<Deduction> _deductions = <Deduction>[];

  bool _depositRefunded = true;
  final TextEditingController _refundAmountController =
      TextEditingController();
  final TextEditingController _refundRefController =
      TextEditingController();
  PaymentMethod _refundPaymentMethod = PaymentMethod.UPI;

  bool _paymentReceivedFromTenant = true;
  final TextEditingController _amountPaidByTenantController =
      TextEditingController();
  PaymentMethod _tenantPaymentMethod = PaymentMethod.UPI;
  String? _meterPhotoUrl;
  bool _uploadingMeterPhoto = false;
  bool _busy = false;
  String? _statementPath;

  @override
  void initState() {
    super.initState();
    _completedChecklist = HandoverChecklistItems.defaults.toSet();
  }

  @override
  void dispose() {
    _meterController.dispose();
    _deductionReasonController.dispose();
    _refundAmountController.dispose();
    _refundRefController.dispose();
    _amountPaidByTenantController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final property = ref.watch(propertyProvider(widget.propertyId));
    final propertiesAsync = ref.watch(propertiesProvider);
    final tenantsAsync = ref.watch(propertyTenantsProvider(widget.propertyId));
    final allTenantsAsync = ref.watch(allTenantsProvider);
    final tenant = ref
        .watch(tenantProvider((widget.propertyId, widget.tenantId)));

    return Scaffold(
      appBar: AppBar(title: const Text('Tenant exit')),
      body: _resolveBody(
        property: property,
        propertiesAsync: propertiesAsync,
        tenantsAsync: tenantsAsync,
        allTenantsAsync: allTenantsAsync,
        tenant: tenant,
      ),
    );
  }

  Widget _resolveBody({
    required Property? property,
    required AsyncValue<List<Property>> propertiesAsync,
    required AsyncValue<List<Tenant>> tenantsAsync,
    required AsyncValue<List<Tenant>> allTenantsAsync,
    required Tenant? tenant,
  }) {
    if (property == null) {
      if (propertiesAsync.isLoading) {
        return const LoadingView(message: 'Loading property…');
      }
      return ErrorView(
        message: 'We could not load this property.',
        onRetry: () => ref.invalidate(propertiesProvider),
      );
    }

    if (tenant == null) {
      if (tenantsAsync.isLoading || allTenantsAsync.isLoading) {
        return const LoadingView(message: 'Loading tenant…');
      }
      return ErrorView(
        message: 'This tenant record could not be loaded.',
        onRetry: () =>
            ref.invalidate(propertyTenantsProvider(widget.propertyId)),
      );
    }

    if (tenant.isExited) {
      return EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Tenant already exited',
        message:
            '${tenant.name} has already been settled for ${property.propertyName}.',
        action: FilledButton.icon(
          onPressed: () => context.go(AppRoutes.property(property.propertyId)),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back to property'),
        ),
      );
    }

    final transactions = ref.watch(tenantTransactionsProvider(tenant.tenantId));
    final breakdown = _settle(property, tenant, transactions);

    return Stepper(
      currentStep: _step,
      type: StepperType.vertical,
      physics: const AlwaysScrollableScrollPhysics(),
      onStepTapped: (index) {
        if (index < _step) setState(() => _step = index);
      },
      onStepContinue: () => _onContinue(property, tenant, breakdown),
      onStepCancel: () {
        if (_step > 0) setState(() => _step -= 1);
      },
      controlsBuilder: (context, details) => _controls(property, details),
      steps: <Step>[
        Step(
          title: const Text('Readings'),
          isActive: _step >= 0,
          state: _stateFor(0),
          content: _stepReadings(property, tenant, breakdown),
        ),
        Step(
          title: const Text('Dues & deductions'),
          isActive: _step >= 1,
          state: _stateFor(1),
          content: _stepDues(breakdown),
        ),
        Step(
          title: const Text('Summary'),
          isActive: _step >= 2,
          state: _stateFor(2),
          content: _stepSummary(property, tenant, breakdown),
        ),
        Step(
          title: const Text('Confirm'),
          isActive: _step >= 3,
          state: _stateFor(3),
          content: _stepConfirm(property, tenant, breakdown),
        ),
      ],
    );
  }

  StepState _stateFor(int index) =>
      index < _step ? StepState.complete : StepState.indexed;

  Widget _controls(Property property, ControlsDetails details) {
    final isLast = details.stepIndex == 3;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : details.onStepContinue,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isLast ? 'Confirm exit & settle' : 'Continue'),
            ),
          ),
          if (details.stepIndex > 0) ...<Widget>[
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : details.onStepCancel,
                child: const Text('Back'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------------- step one

  Widget _stepReadings(
    Property property,
    Tenant tenant,
    SettlementBreakdown breakdown,
  ) {
    final isSubMeter =
        property.electricityBillingType == ElectricityBillingType.SUB_METER;
    final previous = property.currentEbMeterReading;
    final entered = double.tryParse(_meterController.text.trim());
    final consumed =
        entered == null ? 0.0 : (entered - previous).clamp(0, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(
          title: 'Meter & dates',
          subtitle: 'Final readings and the handover date',
        ),
        const SizedBox(height: 12),
        DetailRow(
          label: 'Electricity billing',
          value: property.electricityBillingType.label,
        ),
        const SizedBox(height: 8),
        if (isSubMeter) ...<Widget>[
          Form(
            key: _meterFormKey,
            child: TextFormField(
              controller: _meterController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Final meter reading',
                prefixIcon: Icon(Icons.speed_outlined),
                suffixText: 'units',
              ),
              validator: (value) =>
                  Validators.meterReading(value, previous: previous),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),
          DetailRow(
            label: 'Previous reading',
            value: '${Formatters.units(previous)} units',
          ),
          DetailRow(
            label: 'Units consumed',
            value: '${Formatters.units(consumed)} units',
          ),
          if (property.ratePerUnit > 0)
            DetailRow(
              label: 'Rate per unit',
              value: Formatters.currency(property.ratePerUnit),
            ),
          const SizedBox(height: 12),
          if (_meterPhotoUrl == null)
            OutlinedButton.icon(
              onPressed:
                  _uploadingMeterPhoto || _busy ? null : _attachMeterPhoto,
              icon: _uploadingMeterPhoto
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Attach meter photo (optional)'),
            )
          else
            Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _meterPhotoUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.speed_outlined, size: 40),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Final meter photo attached (optional)'),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove photo',
                  onPressed: () => setState(() => _meterPhotoUrl = null),
                ),
              ],
            ),
        ] else
          _infoCard(
            icon: Icons.bolt_outlined,
            message: property.electricityBillingType ==
                    ElectricityBillingType.DIRECT_EB
                ? 'The tenant pays the electricity board directly, so no '
                    'meter reading is required for this settlement.'
                : 'Electricity is charged at a fixed monthly amount, so no '
                    'meter reading is required for this settlement.',
          ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.event_outlined),
            title: const Text('Exit date'),
            subtitle: Text(Formatters.date(_exitDate)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickExitDate(tenant),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: SwitchListTile(
            title: const Text('Pro-rata final month rent'),
            subtitle: Text(
              _isProRataExitMonth
                  ? 'Bill ${_exitDate.day} of ${DateTime(_exitDate.year, _exitDate.month + 1, 0).day} days in ${Formatters.monthYear(_exitDate)}'
                  : 'Bill the entire month of ${Formatters.monthYear(_exitDate)} in full',
            ),
            value: _isProRataExitMonth,
            onChanged: (val) => setState(() => _isProRataExitMonth = val),
          ),
        ),
        const SizedBox(height: 12),
        DetailRow(label: 'Lease start', value: Formatters.date(tenant.leaseStartDate)),
        DetailRow(
          label: 'Billing duration',
          value: breakdown.isProRata
              ? '${breakdown.monthsBilled} months (${breakdown.exitMonthDays}d pro-rata in exit month)'
              : '${breakdown.monthsBilled} full months',
        ),
        const SizedBox(height: 16),
        _noticePeriodCard(breakdown.rentPerMonth),
        const SizedBox(height: 12),
        _handoverChecklistCard(),
      ],
    );
  }

  Widget _noticePeriodCard(double rentPerMonth) {
    final notice = _noticeDate ?? _exitDate.subtract(const Duration(days: 30));
    final shortfall = SettlementCalculator.calculateNoticeShortfall(
      noticeDate: notice,
      exitDate: _exitDate,
      requiredNoticeDays: _requiredNoticeDays,
      rentPerMonth: rentPerMonth,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Check notice period shortfall'),
              subtitle: const Text(
                'Deduct rent if tenant vacated without serving agreed notice',
              ),
              value: _checkNoticePeriod,
              onChanged: (val) => setState(() => _checkNoticePeriod = val),
            ),
            if (_checkNoticePeriod) ...[
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Date notice was given'),
                subtitle: Text(Formatters.date(notice)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: notice,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _noticeDate = picked);
                },
              ),
              Row(
                children: [
                  const Text('Required notice: '),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _requiredNoticeDays,
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('15 days')),
                      DropdownMenuItem(value: 30, child: Text('30 days (1 mo)')),
                      DropdownMenuItem(value: 60, child: Text('60 days (2 mo)')),
                      DropdownMenuItem(value: 90, child: Text('90 days (3 mo)')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _requiredNoticeDays = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (shortfall.shortfallDays > 0) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade700),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.amber.shade900),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Notice shortfall: ${shortfall.shortfallDays} days unserved.\n'
                          'Rent deduction: ${Formatters.currency(shortfall.shortfallRent)}',
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: () {
                          final label =
                              'Notice period shortfall (${shortfall.shortfallDays} days)';
                          if (!_deductions.any((d) => d.label == label)) {
                            setState(() {
                              _deductions.add(Deduction(
                                label: label,
                                amount: shortfall.shortfallRent,
                              ));
                            });
                            _showSnack('Added notice shortfall deduction.');
                          } else {
                            _showSnack('Notice shortfall already added.');
                          }
                        },
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Full notice served (${_exitDate.difference(notice).inDays} days). No shortfall deduction.',
                    style: TextStyle(
                      color: context.ledgerColors.income,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _handoverChecklistCard() {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: Icon(
          _completedChecklist.length == HandoverChecklistItems.defaults.length
              ? Icons.check_circle
              : Icons.checklist_outlined,
          color: _completedChecklist.length ==
                  HandoverChecklistItems.defaults.length
              ? context.ledgerColors.income
              : null,
        ),
        title: const Text('Move-out handover checklist'),
        subtitle: Text(
          '${_completedChecklist.length} of ${HandoverChecklistItems.defaults.length} items verified',
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    if (_completedChecklist.length ==
                        HandoverChecklistItems.defaults.length) {
                      _completedChecklist.clear();
                    } else {
                      _completedChecklist =
                          HandoverChecklistItems.defaults.toSet();
                    }
                  }),
                  child: Text(
                    _completedChecklist.length ==
                            HandoverChecklistItems.defaults.length
                        ? 'Uncheck all'
                        : 'Check all',
                  ),
                ),
              ],
            ),
          ),
          for (final item in HandoverChecklistItems.defaults)
            CheckboxListTile(
              dense: true,
              value: _completedChecklist.contains(item),
              title: Text(item),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _completedChecklist.add(item);
                  } else {
                    _completedChecklist.remove(item);
                  }
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _infoCard({required IconData icon, required String message}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Future<void> _pickExitDate(Tenant tenant) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _exitDate,
      firstDate: tenant.leaseStartDate,
      lastDate: DateTime(now.year + 5),
    );
    if (!mounted || picked == null) return;
    if (picked.isBefore(tenant.leaseStartDate)) {
      _showSnack(
        'Exit date cannot be before lease start date (${Formatters.date(tenant.leaseStartDate)}).',
      );
      return;
    }
    setState(() => _exitDate = picked);
  }

  // --------------------------------------------------------------- step two

  Widget _stepDues(SettlementBreakdown breakdown) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(
          title: 'Dues & deductions',
          subtitle: 'Tap any pending amount to adjust it',
        ),
        const SizedBox(height: 8),
        _editableRow(
          label: 'Pending rent',
          value: _pendingRent(breakdown),
          onChanged: (value) => setState(() => _overridePendingRent = value),
        ),
        _editableRow(
          label: 'Pending maintenance',
          value: _pendingMaintenance(breakdown),
          onChanged: (value) =>
              setState(() => _overridePendingMaintenance = value),
        ),
        _editableRow(
          label: 'Pending electricity',
          value: _pendingEb(breakdown),
          onChanged: (value) => setState(() => _overridePendingEb = value),
        ),
        _editableRow(
          label: 'Other dues',
          value: _pendingOther(breakdown),
          onChanged: (value) => setState(() => _overridePendingOther = value),
        ),
        const SizedBox(height: 4),
        const Divider(),
        DetailRow(
          label: 'Total pending',
          value: Formatters.currency(_totalPending(breakdown)),
          valueColor: context.ledgerColors.pending,
          emphasize: true,
        ),
        const SizedBox(height: 20),
        SectionHeader(
          title: 'Deductions',
          subtitle: 'Anything withheld from the deposit',
          trailing: TextButton.icon(
            onPressed: () => _addDeduction(breakdown),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
          ),
        ),
        const SizedBox(height: 4),
        if (_deductions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No deductions added.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (int i = 0; i < _deductions.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _deductions[i].label.isEmpty
                    ? 'Deduction'
                    : _deductions[i].label,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    Formatters.currency(_deductions[i].amount),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove deduction',
                    onPressed: () => setState(() => _deductions.removeAt(i)),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 12),
        TextField(
          controller: _deductionReasonController,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Deduction reason (optional)',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  Widget _editableRow({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _promptAmount(
        label: label,
        initial: value,
        onChanged: onChanged,
      ),
      child: DetailRow(
        label: label,
        value: Formatters.currency(value),
        icon: Icons.edit_outlined,
      ),
    );
  }

  Future<void> _promptAmount({
    required String label,
    required double initial,
    required ValueChanged<double> onChanged,
  }) async {
    final result = await showDialog<double>(
      context: context,
      builder: (context) => _PromptAmountDialog(
        label: label,
        initial: initial,
      ),
    );
    if (!mounted || result == null) return;
    onChanged(result);
  }

  Future<void> _addDeduction(SettlementBreakdown breakdown) async {
    final result = await showDialog<Deduction>(
      context: context,
      builder: (context) => _AddDeductionDialog(
        rentPerMonth: breakdown.rentPerMonth,
      ),
    );

    if (!mounted || result == null) return;
    setState(() => _deductions.add(result));
  }

  // ------------------------------------------------------------- step three

  Widget _stepSummary(
    Property property,
    Tenant tenant,
    SettlementBreakdown breakdown,
  ) {
    final theme = Theme.of(context);
    final pendingRent = _pendingRent(breakdown);
    final pendingMaintenance = _pendingMaintenance(breakdown);
    final pendingEb = _pendingEb(breakdown);
    final pendingOther = _pendingOther(breakdown);
    final totalPending = _totalPending(breakdown);
    final totalDeductions = _totalDeductions();
    final net = _net(breakdown);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(
          title: 'Settlement summary',
          subtitle: 'Statement of the final settlement',
        ),
        const SizedBox(height: 12),
        DetailRow(
          label: 'Advance deposit held',
          value: Formatters.currency(breakdown.advanceDeposit),
        ),
        if (breakdown.isProRata)
          DetailRow(
            label: 'Exit month billing',
            value:
                '${breakdown.exitMonthDays} of ${breakdown.daysInExitMonth} days pro-rata',
          ),
        if (_completedChecklist.isNotEmpty)
          DetailRow(
            label: 'Handover checklist',
            value:
                '${_completedChecklist.length} of ${HandoverChecklistItems.defaults.length} items verified',
          ),
        if (property.electricityBillingType ==
            ElectricityBillingType.SUB_METER) ...<Widget>[
          const SizedBox(height: 8),
          DetailRow(
            label: 'Final meter reading',
            value: '${Formatters.units(breakdown.finalMeterReading)} units',
          ),
          DetailRow(
            label: 'Units since last reading',
            value: '${Formatters.units(breakdown.unitsConsumedAtExit)} units',
          ),
        ],
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Dues outstanding',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        DetailRow(
          label: 'Pending rent',
          value: Formatters.currency(pendingRent),
        ),
        DetailRow(
          label: 'Pending maintenance',
          value: Formatters.currency(pendingMaintenance),
        ),
        DetailRow(
          label: 'Pending electricity',
          value: Formatters.currency(pendingEb),
        ),
        if (pendingOther > 0)
          DetailRow(
            label: 'Other dues',
            value: Formatters.currency(pendingOther),
          ),
        DetailRow(
          label: 'Total pending',
          value: Formatters.currency(totalPending),
          valueColor: context.ledgerColors.pending,
          emphasize: true,
        ),
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Deductions',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (_deductions.isEmpty)
          DetailRow(label: 'None', value: Formatters.currency(0))
        else
          for (final deduction in _deductions)
            DetailRow(
              label: deduction.label.isEmpty ? 'Deduction' : deduction.label,
              value: Formatters.currency(deduction.amount),
            ),
        DetailRow(
          label: 'Total deductions',
          value: Formatters.currency(totalDeductions),
          emphasize: true,
        ),
        const SizedBox(height: 20),
        _resultCard(net),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _generateStatement(property, tenant, breakdown),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(
            _statementPath == null
                ? 'Generate statement PDF'
                : 'Regenerate statement PDF',
          ),
        ),
        if (_statementPath != null) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Icon(
                Icons.check_circle,
                size: 18,
                color: context.ledgerColors.income,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Statement generated — you will be offered to share it '
                  'after the exit.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _shareStatement(tenant),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share statement'),
          ),
        ],
      ],
    );
  }

  Widget _resultCard(double net) {
    final theme = Theme.of(context);
    final Color color;
    final String label;
    final String caption;
    if (net > 0) {
      color = context.ledgerColors.income;
      label = 'Refund due to tenant';
      caption = 'Net settlement in the tenant’s favour.';
    } else if (net < 0) {
      color = context.ledgerColors.expense;
      label = 'Amount due from tenant';
      caption = 'Net settlement still payable by the tenant.';
    } else {
      color = theme.colorScheme.primary;
      label = 'Fully settled';
      caption = 'Nothing is payable either way.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          AmountText(
            text: Formatters.currency(net.abs()),
            color: color,
            size: 26,
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- step four

  Widget _stepConfirm(
    Property property,
    Tenant tenant,
    SettlementBreakdown breakdown,
  ) {
    final theme = Theme.of(context);
    final color = context.ledgerColors.pending;
    final net = _net(breakdown);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(
          title: 'Confirm exit',
          subtitle: 'This action updates the ledger and the property',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.warning_amber_rounded, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Before you confirm',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const _BulletLine(
                'The tenant is marked as exited and moved to Past tenants.',
              ),
              const _BulletLine(
                'All rent, maintenance and electricity history is retained.',
              ),
              const _BulletLine(
                'The property is marked as vacant and freed for a new tenant.',
              ),
              if (net > 0)
                const _BulletLine(
                  'Any advance refund is recorded as an expense in the ledger.',
                )
              else if (net < 0)
                const _BulletLine(
                  'Any payment received from the tenant is recorded as an income transaction in the ledger.',
                ),
              const _BulletLine(
                'The final meter reading becomes the baseline for the next tenant.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (net > 0) ...<Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Deposit refunded to tenant'),
                    subtitle: Text(
                      _depositRefunded
                          ? 'A refund transaction will be recorded as an expense in the ledger.'
                          : 'Refund not issued yet (withheld pending final utility bills).',
                    ),
                    value: _depositRefunded,
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(() {
                              _depositRefunded = value;
                              if (value &&
                                  _refundAmountController.text.isEmpty) {
                                _refundAmountController.text =
                                    net.toStringAsFixed(0);
                              }
                            });
                          },
                  ),
                  if (_depositRefunded) ...<Widget>[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _refundAmountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Refund amount paid',
                        helperText: 'Actual amount refunded to tenant now',
                        prefixText: '₹ ',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<PaymentMethod>(
                      value: _refundPaymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'Refund payment mode',
                      ),
                      items: PaymentMethod.values.map((method) {
                        return DropdownMenuItem<PaymentMethod>(
                          value: method,
                          child: Text(method.label),
                        );
                      }).toList(),
                      onChanged: _busy
                          ? null
                          : (val) {
                              if (val != null) {
                                setState(() => _refundPaymentMethod = val);
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _refundRefController,
                      decoration: const InputDecoration(
                        labelText:
                            'Payment reference / UTR / Cheque # (optional)',
                        hintText: 'e.g. UPI Ref / Bank UTR #',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ] else if (net < 0) ...<Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Payment received from tenant'),
                    subtitle: Text(
                      _paymentReceivedFromTenant
                          ? 'Record payment received now as an income transaction in the ledger.'
                          : 'Tenant will settle remaining dues later.',
                    ),
                    value: _paymentReceivedFromTenant,
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(() {
                              _paymentReceivedFromTenant = value;
                              if (value &&
                                  _amountPaidByTenantController.text.isEmpty) {
                                _amountPaidByTenantController.text =
                                    net.abs().toStringAsFixed(0);
                              }
                            });
                          },
                  ),
                  if (_paymentReceivedFromTenant) ...<Widget>[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _amountPaidByTenantController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Amount received from tenant',
                        helperText: 'Enter amount paid by tenant at exit',
                        prefixText: '₹ ',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<PaymentMethod>(
                      value: _tenantPaymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'Payment method',
                      ),
                      items: PaymentMethod.values.map((method) {
                        return DropdownMenuItem<PaymentMethod>(
                          value: method,
                          child: Text(method.label),
                        );
                      }).toList(),
                      onChanged: _busy
                          ? null
                          : (val) {
                              if (val != null) {
                                setState(() => _tenantPaymentMethod = val);
                              }
                            },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        DetailRow(label: 'Tenant', value: tenant.name),
        DetailRow(label: 'Property', value: property.propertyName),
        DetailRow(label: 'Exit date', value: Formatters.date(_exitDate)),
        DetailRow(
          label: net >= 0 ? 'Refund payable' : 'Total due from tenant',
          value: Formatters.currency(net.abs()),
          valueColor:
              net >= 0 ? context.ledgerColors.income : context.ledgerColors.expense,
          emphasize: true,
        ),
        if (net < 0 && _paymentReceivedFromTenant) ...<Widget>[
          DetailRow(
            label: 'Payment received now',
            value: Formatters.currency(
              double.tryParse(_amountPaidByTenantController.text.trim()) ?? 0,
            ),
            valueColor: context.ledgerColors.income,
          ),
          DetailRow(
            label: 'Remaining balance due',
            value: Formatters.currency(
              (net.abs() -
                      (double.tryParse(
                              _amountPaidByTenantController.text.trim()) ??
                          0))
                  .clamp(0, double.infinity),
            ),
            valueColor: context.ledgerColors.expense,
            emphasize: true,
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------- settlement

  SettlementBreakdown _settle(
    Property property,
    Tenant tenant,
    List<LedgerTransaction> transactions,
  ) {
    final finalMeterReading =
        property.electricityBillingType == ElectricityBillingType.SUB_METER
            ? double.tryParse(_meterController.text.trim())
            : null;
    return SettlementCalculator.calculate(
      SettlementInput(
        property: property,
        tenant: tenant,
        transactions: transactions,
        exitDate: _exitDate,
        finalMeterReading: finalMeterReading,
        deductions: _deductions,
        pendingOther: _overridePendingOther ?? 0,
        isProRataExitMonth: _isProRataExitMonth,
        noticeDate: _checkNoticePeriod ? _noticeDate : null,
        requiredNoticeDays: _requiredNoticeDays,
      ),
    );
  }

  double _pendingRent(SettlementBreakdown b) =>
      _overridePendingRent ?? b.pendingRent;
  double _pendingMaintenance(SettlementBreakdown b) =>
      _overridePendingMaintenance ?? b.pendingMaintenance;
  double _pendingEb(SettlementBreakdown b) =>
      _overridePendingEb ?? b.pendingEb;
  double _pendingOther(SettlementBreakdown b) =>
      _overridePendingOther ?? b.pendingOther;

  double _totalPending(SettlementBreakdown b) =>
      _pendingRent(b) +
      _pendingMaintenance(b) +
      _pendingEb(b) +
      _pendingOther(b);

  double _totalDeductions() =>
      _deductions.fold<double>(0, (sum, d) => sum + d.amount);

  double _net(SettlementBreakdown b) =>
      b.advanceDeposit - _totalPending(b) - _totalDeductions();

  TenantExitDetails _buildDetails(SettlementBreakdown breakdown) {
    final reason = _deductionReasonController.text.trim();
    final net = _net(breakdown);
    final amountPaid = (_paymentReceivedFromTenant && net < 0)
        ? (double.tryParse(_amountPaidByTenantController.text.trim()) ?? 0.0)
        : 0.0;
    final refundAmount = (_depositRefunded && net > 0)
        ? (double.tryParse(_refundAmountController.text.trim()) ?? net)
        : 0.0;
    return breakdown.toExitDetails(
      deductionReason: reason.isEmpty ? null : reason,
      depositRefunded: _depositRefunded,
      refundAmount: refundAmount,
      refundPaymentMethod:
          (_depositRefunded && net > 0) ? _refundPaymentMethod : null,
      refundTransactionRef: (_depositRefunded && net > 0)
          ? _refundRefController.text.trim()
          : null,
      amountPaidByTenant: amountPaid,
      paymentMethod: (_paymentReceivedFromTenant && net < 0 && amountPaid > 0)
          ? _tenantPaymentMethod
          : null,
      meterPhotoUrl: _meterPhotoUrl,
      overridePendingRent: _overridePendingRent,
      overridePendingMaintenance: _overridePendingMaintenance,
      overridePendingEb: _overridePendingEb,
      overridePendingOther: _overridePendingOther,
      overrideDeductions: _deductions,
      isProRataRent: _isProRataExitMonth,
      handoverChecklist: _completedChecklist.toList(),
    );
  }

  Future<void> _attachMeterPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo of meter'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose meter photo from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picked = await pickImageSafely(
      context,
      source: source,
      imageQuality: 80,
      maxWidth: 2048,
    );
    if (picked == null || !mounted) return;

    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      _showSnack('You are not signed in.');
      return;
    }

    setState(() => _uploadingMeterPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await ref.read(storageRepositoryProvider).uploadBytes(
            path: 'users/$uid/properties/${widget.propertyId}/meter-photos/'
                'exit_${DateTime.now().millisecondsSinceEpoch}.jpg',
            bytes: bytes,
            contentType: 'image/jpeg',
          );
      if (!mounted) return;
      setState(() => _meterPhotoUrl = url);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not upload the meter photo.');
    } finally {
      if (mounted) setState(() => _uploadingMeterPhoto = false);
    }
  }

  void _onContinue(
    Property property,
    Tenant tenant,
    SettlementBreakdown breakdown,
  ) {
    FocusScope.of(context).unfocus();
    if (_step == 0) {
      if (_meterFormKey.currentState?.validate() ?? true) {
        setState(() => _step = 1);
      }
      return;
    }
    if (_step < 3) {
      final nextStep = _step + 1;
      if (nextStep == 3) {
        final net = _net(breakdown);
        if (net < 0 && _amountPaidByTenantController.text.isEmpty) {
          _amountPaidByTenantController.text = net.abs().toStringAsFixed(0);
        } else if (net > 0 && _refundAmountController.text.isEmpty) {
          _refundAmountController.text = net.toStringAsFixed(0);
        }
      }
      setState(() => _step = nextStep);
      return;
    }
    _confirmExit(property, tenant, breakdown);
  }

  String _fileName(Tenant tenant) {
    final safe = tenant.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return 'exit_statement_${safe.isEmpty ? 'tenant' : safe}_'
        '${DateTime.now().millisecondsSinceEpoch}.pdf';
  }

  Future<void> _generateStatement(
    Property property,
    Tenant tenant,
    SettlementBreakdown breakdown,
  ) async {
    setState(() => _busy = true);
    String? path;
    try {
      final currency = ref.read(userProfileProvider).valueOrNull?.currency ??
          AppConstants.defaultCurrency;
      final bytes = await ref
          .read(settlementStatementBuilderProvider)
          .buildStatement(
            property: property,
            tenant: tenant,
            details: _buildDetails(breakdown),
            currency: currency,
          );
      path = await ref
          .read(exportFileSaverProvider)
          .save(fileName: _fileName(tenant), bytes: bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack('We could not generate the statement PDF.');
      return;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _statementPath = path;
    });
    await _shareStatement(tenant);
  }

  Future<void> _shareStatement(Tenant tenant) async {
    final path = _statementPath;
    if (path == null) return;
    try {
      await ref.read(exportFileSaverProvider).share(
            filePath: path,
            subject: 'Tenant exit settlement — ${tenant.name}',
            text: 'Exit & deposit settlement statement for ${tenant.name}.',
          );
    } catch (_) {
      if (!mounted) return;
      _showSnack('Sharing is not available on this device right now.');
    }
  }

  Future<void> _confirmExit(
    Property property,
    Tenant tenant,
    SettlementBreakdown breakdown,
  ) async {
    FocusScope.of(context).unfocus();
    final net = _net(breakdown);
    if (net < 0 && _paymentReceivedFromTenant) {
      final text = _amountPaidByTenantController.text.trim();
      final parsed = double.tryParse(text);
      if (parsed == null || parsed <= 0) {
        _showSnack(
          'Please enter a valid amount received or turn off payment received.',
        );
        return;
      }
    } else if (net > 0 && _depositRefunded) {
      final text = _refundAmountController.text.trim();
      final parsed = double.tryParse(text);
      if (parsed == null || parsed <= 0) {
        _showSnack(
          'Please enter a valid refund amount or turn off deposit refunded.',
        );
        return;
      }
    }
    setState(() => _busy = true);

    final ok = await ref.read(tenantControllerProvider.notifier).settleExit(
          property: property,
          tenant: tenant,
          details: _buildDetails(breakdown),
        );
    if (!mounted) return;
    setState(() => _busy = false);

    if (!ok) {
      final error = ref.read(tenantControllerProvider).error;
      _showSnack(
        AppException.userMessageOf(
          error,
          fallback: 'We could not complete the exit. Please try again.',
        ),
      );
      return;
    }

    _showSnack(
      '${tenant.name} has been settled and ${property.propertyName} is now vacant.',
    );

    if (_statementPath != null) {
      final shouldShare = await _askToShare();
      if (!mounted) return;
      if (shouldShare) {
        await _shareStatement(tenant);
        if (!mounted) return;
      }
    }

    if (!mounted) return;
    context.go(AppRoutes.property(property.propertyId));
  }

  Future<bool> _askToShare() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit recorded'),
        content: const Text(
          'The settlement statement was generated. Share it with the tenant now?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Share'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Small bullet used by the confirmation warning card.
class _BulletLine extends StatelessWidget {
  const _BulletLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _PromptAmountDialog extends StatefulWidget {
  const _PromptAmountDialog({
    required this.label,
    required this.initial,
  });

  final String label;
  final double initial;

  @override
  State<_PromptAmountDialog> createState() => _PromptAmountDialogState();
}

class _PromptAmountDialogState extends State<_PromptAmountDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial == widget.initial.roundToDouble()
          ? widget.initial.round().toString()
          : widget.initial.toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || parsed < 0) return;
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.label),
      content: SingleChildScrollView(
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount'),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _AddDeductionDialog extends StatefulWidget {
  const _AddDeductionDialog({
    this.rentPerMonth = 0,
  });

  final double rentPerMonth;

  @override
  State<_AddDeductionDialog> createState() => _AddDeductionDialogState();
}

class _AddDeductionDialogState extends State<_AddDeductionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController();
    _amountController = TextEditingController();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final label = _labelController.text.trim();
    Navigator.of(context).pop(
      Deduction(
        label: label.isEmpty ? 'Deduction' : label,
        amount: double.parse(_amountController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Add deduction'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Quick presets',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (widget.rentPerMonth > 0)
                    ActionChip(
                      avatar: const Icon(Icons.format_paint, size: 14),
                      label: const Text('Painting (1 mo)'),
                      onPressed: () {
                        _labelController.text =
                            MoveOutDeductionPresets.paintingOneMonth;
                        _amountController.text =
                            widget.rentPerMonth.toStringAsFixed(0);
                      },
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.cleaning_services, size: 14),
                    label: const Text('Deep cleaning'),
                    onPressed: () {
                      _labelController.text =
                          MoveOutDeductionPresets.deepCleaning;
                      if (_amountController.text.isEmpty) {
                        _amountController.text = '2500';
                      }
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.plumbing, size: 14),
                    label: const Text('Plumbing'),
                    onPressed: () {
                      _labelController.text =
                          MoveOutDeductionPresets.plumbingRepair;
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.carpenter, size: 14),
                    label: const Text('Carpentry'),
                    onPressed: () {
                      _labelController.text =
                          MoveOutDeductionPresets.carpentryRepair;
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.electrical_services, size: 14),
                    label: const Text('Electrical'),
                    onPressed: () {
                      _labelController.text =
                          MoveOutDeductionPresets.electricalRepair;
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.key, size: 14),
                    label: const Text('Keys / locks'),
                    onPressed: () {
                      _labelController.text =
                          MoveOutDeductionPresets.keyReplacement;
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.apartment, size: 14),
                    label: const Text('Society dues'),
                    onPressed: () {
                      _labelController.text =
                          MoveOutDeductionPresets.societyMaintenance;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _labelController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reason / label',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount'),
                validator: (value) =>
                    Validators.positiveAmount(value, field: 'Deduction'),
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
