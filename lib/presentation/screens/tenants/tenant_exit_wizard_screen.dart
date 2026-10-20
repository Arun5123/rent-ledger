import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  double? _overridePendingRent;
  double? _overridePendingMaintenance;
  double? _overridePendingEb;
  double? _overridePendingOther;

  final List<Deduction> _deductions = <Deduction>[];

  bool _depositRefunded = true;
  bool _paymentReceivedFromTenant = true;
  final TextEditingController _amountPaidByTenantController =
      TextEditingController();
  PaymentMethod _tenantPaymentMethod = PaymentMethod.UPI;
  String? _meterPhotoUrl;
  bool _uploadingMeterPhoto = false;
  bool _busy = false;
  String? _statementPath;

  @override
  void dispose() {
    _meterController.dispose();
    _deductionReasonController.dispose();
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
            onTap: _pickExitDate,
          ),
        ),
        const SizedBox(height: 12),
        DetailRow(label: 'Lease start', value: Formatters.date(tenant.leaseStartDate)),
        DetailRow(
          label: 'Billed months',
          value: '${breakdown.monthsBilled}',
        ),
      ],
    );
  }

  Widget _infoCard({required IconData icon, required String message}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
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

  Future<void> _pickExitDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _exitDate,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 5),
    );
    if (!mounted || picked == null) return;
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
            onPressed: _addDeduction,
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

  Future<void> _addDeduction() async {
    final result = await showDialog<Deduction>(
      context: context,
      builder: (context) => const _AddDeductionDialog(),
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
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
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
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.35)),
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
            child: SwitchListTile(
              title: const Text('Deposit refunded to tenant'),
              subtitle: Text(
                'A refund of ${Formatters.currency(net)} will be recorded as an expense in the ledger.',
              ),
              value: _depositRefunded,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _depositRefunded = value),
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
                      initialValue: _tenantPaymentMethod,
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
    return breakdown.toExitDetails(
      deductionReason: reason.isEmpty ? null : reason,
      depositRefunded: _depositRefunded,
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
      _showSnack('We could not complete the exit. Please try again.');
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
  const _AddDeductionDialog();

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
    return AlertDialog(
      title: const Text('Add deduction'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
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
