import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/communication_utils.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/ledger_transaction.dart';
import '../../../domain/models/property.dart';
import '../../../domain/models/tenant.dart';
import '../../../domain/services/ledger_calculator.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/auth_providers.dart';
import '../../../providers/property_providers.dart';
import '../../../providers/tenant_providers.dart';
import '../../../providers/transaction_providers.dart';

/// Opens the ledger-entry bottom sheet.
Future<bool?> showTransactionEntrySheet(
  BuildContext context, {
  required String propertyId,
  LedgerTransaction? existing,
  String? presetTenantId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _TransactionEntrySheet(
      propertyId: propertyId,
      existing: existing,
      presetTenantId: presetTenantId,
    ),
  );
}

/// Renders `12` for `12.0` and `12.5` for `12.5` — keeps seeded fields tidy.
String _numberText(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toString();

enum _EbEntryMode {
  perUnit,
  totalBill,
}

class _TransactionEntrySheet extends ConsumerStatefulWidget {
  const _TransactionEntrySheet({
    required this.propertyId,
    this.existing,
    this.presetTenantId,
  });

  final String propertyId;
  final LedgerTransaction? existing;
  final String? presetTenantId;

  @override
  ConsumerState<_TransactionEntrySheet> createState() =>
      _TransactionEntrySheetState();
}

class _TransactionEntrySheetState
    extends ConsumerState<_TransactionEntrySheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late TransactionType _type;
  late TransactionCategory _category;
  late PaymentMethod _paymentMethod;
  String? _tenantId;
  late DateTime _recordedAt;
  late String _billingPeriod;
  late _EbEntryMode _ebMode;
  ExpenseCategory? _expenseCategory;
  String? _meterPhotoUrl;
  bool _uploadingMeterPhoto = false;
  String? _receiptUrl;
  String? _ebError;
  bool _saving = false;
  bool _uploadingReceipt = false;
  bool _ebPrefilled = false;

  late final TextEditingController _amount;
  late final TextEditingController _previousReading;
  late final TextEditingController _currentReading;
  late final TextEditingController _ratePerUnit;
  late final TextEditingController _notes;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final eb = existing?.ebDetails;

    _type = existing?.type ?? TransactionType.RENT_PAYMENT;
    _category = existing?.category ?? _type.defaultCategory;
    _paymentMethod = existing?.paymentMethod ?? PaymentMethod.CASH;
    _tenantId = existing?.tenantId ?? widget.presetTenantId;
    _recordedAt = existing?.recordedAt ?? DateTime.now();
    _billingPeriod =
        existing?.billingPeriod ?? Formatters.periodKey(DateTime.now());
    _expenseCategory =
        existing?.expenseCategory ?? ExpenseCategory.MAINTENANCE;
    _meterPhotoUrl = existing?.meterPhotoUrl ?? eb?.meterPhotoUrl;
    _receiptUrl = existing?.receiptUrl;

    _amount = TextEditingController(
      text: existing == null ? '' : _numberText(eb?.amount ?? existing.amount),
    );
    _previousReading = TextEditingController(
      text: eb == null ? '' : _numberText(eb.previousReading),
    );
    _currentReading = TextEditingController(
      text: eb == null ? '' : _numberText(eb.currentReading),
    );
    _ratePerUnit = TextEditingController(
      text: eb == null ? '' : _numberText(eb.unitRate),
    );
    _notes = TextEditingController(text: existing?.notes ?? '');

    _ebMode = eb != null &&
            eb.unitsConsumed > 0 &&
            (eb.amount - eb.unitsConsumed * eb.unitRate).abs() > 0.5
        ? _EbEntryMode.totalBill
        : _EbEntryMode.perUnit;

    _ebPrefilled = eb != null;
    if (!_ebPrefilled) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _prefillEbFromProperty(),
      );
      ref.listenManual(
        propertyProvider(widget.propertyId),
        (_, _) => _prefillEbFromProperty(),
      );
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _previousReading.dispose();
    _currentReading.dispose();
    _ratePerUnit.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _prefillEbFromProperty() {
    if (!mounted || _ebPrefilled) return;
    final Property? property = ref.read(propertyProvider(widget.propertyId));
    if (property == null) return;
    final profile = ref.read(userProfileProvider).valueOrNull;
    final rate = property.ratePerUnit > 0
        ? property.ratePerUnit
        : (profile?.defaultRatePerUnit ?? AppConstants.defaultRatePerUnit);

    _previousReading.text = _numberText(property.currentEbMeterReading);
    _ratePerUnit.text = _numberText(rate);
    _ebPrefilled = true;
    _syncEbAmount();
    setState(() {});
  }

  bool get _ebUsesMeterMath =>
      _type.usesMeterReading && _ebMode == _EbEntryMode.perUnit;

  EbDetails? _computeEb() {
    final previous = double.tryParse(_previousReading.text.trim());
    final current = double.tryParse(_currentReading.text.trim());
    final month = Formatters.parsePeriodKey(_billingPeriod);
    final periodStart = month == null ? null : Formatters.monthStart(month);
    final periodEnd = month == null ? null : Formatters.monthEnd(month);

    if (_ebMode == _EbEntryMode.totalBill) {
      final total = double.tryParse(_amount.text.trim());
      if (previous == null || current == null || total == null) return null;
      return EbDetails.fromTotal(
        previousReading: previous,
        currentReading: current,
        totalAmount: total,
        unitRate: double.tryParse(_ratePerUnit.text.trim()),
        periodStart: periodStart,
        periodEnd: periodEnd,
        meterPhotoUrl: _meterPhotoUrl,
      );
    }

    final rate = double.tryParse(_ratePerUnit.text.trim());
    if (previous == null || current == null || rate == null) return null;
    return EbDetails.calculate(
      previousReading: previous,
      currentReading: current,
      unitRate: rate,
      periodStart: periodStart,
      periodEnd: periodEnd,
      meterPhotoUrl: _meterPhotoUrl,
    );
  }

  void _syncEbAmount() {
    if (!_ebUsesMeterMath) return;
    final details = _computeEb();
    _amount.text = details == null ? '' : _numberText(details.amount);
  }

  void _onEbModeChanged(_EbEntryMode mode) {
    if (mode == _ebMode) return;
    setState(() {
      _ebMode = mode;
      _ebError = null;
      _syncEbAmount();
    });
  }

  String get _ebIncompleteMessage => _ebMode == _EbEntryMode.totalBill
      ? 'Enter both meter readings and the bill total.'
      : 'Enter the meter readings and rate.';

  void _onTypeChanged(TransactionType type) {
    if (type == _type) return;
    _type = type;
    _category = type.defaultCategory;
    _ebError = null;
    if (!type.requiresTenant) _tenantId = null;
    if (type.usesMeterReading) _syncEbAmount();
    setState(() {});
  }

  void _onEbFieldChanged(String _) {
    _ebError = null;
    _syncEbAmount();
    setState(() {});
  }

  Future<void> _pickBillingPeriod() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: Formatters.parsePeriodKey(_billingPeriod) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
      helpText: 'Billing month',
    );
    if (picked == null || !mounted) return;
    setState(() => _billingPeriod = Formatters.periodKey(picked));
  }

  Future<void> _pickRecordedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recordedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
      helpText: 'Entry date',
    );
    if (picked == null || !mounted) return;
    setState(() => _recordedAt = picked);
  }

  Future<void> _attachReceipt() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
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
      _showMessage('You are not signed in.');
      return;
    }

    setState(() => _uploadingReceipt = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await ref
          .read(storageRepositoryProvider)
          .uploadBytes(
            path:
                'users/$uid/properties/${widget.propertyId}/receipts/'
                '${DateTime.now().millisecondsSinceEpoch}.jpg',
            bytes: bytes,
            contentType: 'image/jpeg',
          );
      if (!mounted) return;
      setState(() => _receiptUrl = url);
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        error is AppException ? error.message : 'Could not upload the receipt.',
      );
    } finally {
      if (mounted) setState(() => _uploadingReceipt = false);
    }
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
      _showMessage('You are not signed in.');
      return;
    }

    setState(() => _uploadingMeterPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await ref.read(storageRepositoryProvider).uploadBytes(
            path: 'users/$uid/properties/${widget.propertyId}/meter-photos/'
                '${DateTime.now().millisecondsSinceEpoch}.jpg',
            bytes: bytes,
            contentType: 'image/jpeg',
          );
      if (!mounted) return;
      setState(() => _meterPhotoUrl = url);
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        error is AppException
            ? error.message
            : 'Could not upload the meter photo.',
      );
    } finally {
      if (mounted) setState(() => _uploadingMeterPhoto = false);
    }
  }

  Tenant? _selectedTenant() {
    final tenants =
        ref.read(propertyTenantsProvider(widget.propertyId)).valueOrNull ??
        const <Tenant>[];
    final id = _tenantId;
    if (id == null) return null;
    for (final tenant in tenants) {
      if (tenant.tenantId == id) return tenant;
    }
    return null;
  }

  LedgerTransaction _buildTransaction(String uid, Tenant? tenant) {
    final existing = widget.existing;
    final eb = _type.usesMeterReading ? _computeEb() : null;
    final amount = eb != null
        ? eb.amount
        : (double.tryParse(_amount.text.trim()) ?? 0);
    final notes = _notes.text.trim();
    final ownerId = existing != null && existing.ownerId.isNotEmpty
        ? existing.ownerId
        : uid;
    final createdBy = existing != null && existing.createdBy.isNotEmpty
        ? existing.createdBy
        : uid;

    return LedgerTransaction(
      transactionId: existing?.transactionId ?? '',
      propertyId: widget.propertyId,
      ownerId: ownerId,
      tenantId: tenant?.tenantId,
      tenantName: tenant?.name,
      type: _type,
      category: _category,
      amount: amount,
      paymentMethod: _paymentMethod,
      billingPeriod: _billingPeriod,
      ebDetails: eb,
      expenseCategory: _type == TransactionType.PROPERTY_EXPENSE
          ? (_expenseCategory ?? ExpenseCategory.MAINTENANCE)
          : null,
      meterPhotoUrl: _meterPhotoUrl,
      notes: notes.isEmpty ? null : notes,
      receiptUrl: _receiptUrl,
      recordedAt: _recordedAt,
      createdBy: createdBy,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );
  }

  Future<void> _save() async {
    if (_saving) return;

    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      _showMessage('You are not signed in.');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      if (_type.usesMeterReading && _computeEb() == null) {
        setState(() => _ebError = _ebIncompleteMessage);
      }
      return;
    }

    if (_type.usesMeterReading) {
      final details = _computeEb();
      if (details == null) {
        setState(() => _ebError = _ebIncompleteMessage);
        return;
      }
      if (!details.isValid) {
        setState(
          () => _ebError =
              'Current reading cannot be lower than the previous reading.',
        );
        return;
      }
    }

    final tenant = _type.requiresTenant ? _selectedTenant() : null;
    if (_type.requiresTenant && tenant == null) {
      _showMessage('Select a tenant for this entry.');
      return;
    }

    final transaction = _buildTransaction(uid, tenant);
    setState(() {
      _saving = true;
      _ebError = null;
    });

    try {
      final controller = ref.read(transactionControllerProvider.notifier);
      final bool success;
      if (_isEditing) {
        success = await controller.saveTransaction(transaction);
      } else {
        success = await controller.add(transaction) != null;
      }
      if (!mounted) return;
      if (success) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context, true);
        if (transaction.isIncome && tenant != null) {
          final prop = ref.read(propertyProvider(widget.propertyId));
          final propName = prop?.propertyName ?? 'Property';
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Recorded ${Formatters.currency(transaction.amount)} from ${tenant.name}.',
              ),
              action: SnackBarAction(
                label: 'Share receipt',
                onPressed: () {
                  final msg = CommunicationUtils.buildReceiptMessage(
                    tenantName: tenant.name,
                    propertyName: propName,
                    amount: transaction.amount,
                    typeLabel: transaction.type.label,
                    date: transaction.recordedAt,
                    paymentMethodLabel: transaction.paymentMethod.label,
                    billingPeriod: transaction.billingPeriod,
                  );
                  CommunicationUtils.shareText(
                    text: msg,
                    subject: 'Receipt: $propName - ${transaction.type.label}',
                  );
                },
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        setState(() => _saving = false);
        _showMessage('Could not save the entry. Please try again.');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(
        error is AppException ? error.message : 'Could not save the entry.',
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ledgerColors = context.ledgerColors;
    final property = ref.watch(propertyProvider(widget.propertyId));
    final propertyTransactions =
        ref.watch(propertyTransactionsProvider(widget.propertyId)).valueOrNull ??
            const <LedgerTransaction>[];

    final tenants =
        (ref.watch(propertyTenantsProvider(widget.propertyId)).valueOrNull ??
                const <Tenant>[])
            .where((t) => t.isActive)
            .toList(growable: false);
    final tenantOptions = <String, String>{
      for (final tenant in tenants) tenant.tenantId: tenant.name,
    };
    final currentTenantId = _tenantId;
    if (currentTenantId != null &&
        !tenantOptions.containsKey(currentTenantId) &&
        widget.existing?.tenantName != null) {
      tenantOptions[currentTenantId] = widget.existing!.tenantName!;
    }
    final tenantValue =
        (currentTenantId != null && tenantOptions.containsKey(currentTenantId))
            ? currentTenantId
            : null;

    final ebDetails = _type.usesMeterReading ? _computeEb() : null;

    final selectedTenant = _isEditing ? null : _selectedTenant();
    final tenantDue = (selectedTenant != null &&
            property != null &&
            _type.isRecurringIncome &&
            !_type.usesMeterReading)
        ? LedgerCalculator.dueForTenant(
            tenant: selectedTenant,
            property: property,
            transactions: propertyTransactions,
            month: Formatters.parsePeriodKey(_billingPeriod) ?? DateTime.now(),
          )
        : null;
    final outstanding =
        tenantDue != null && tenantDue.dueAmount > 0.5 ? tenantDue.dueAmount : null;
    final enteredAmount = double.tryParse(_amount.text.trim()) ?? 0;
    final remainingDue =
        outstanding != null && enteredAmount > 0 ? outstanding - enteredAmount : null;

    final String amountHelper;
    if (_ebUsesMeterMath) {
      amountHelper = 'Calculated from the meter readings below';
    } else if (_type.usesMeterReading) {
      amountHelper = 'Enter the total printed on the electricity bill';
    } else if (outstanding == null) {
      amountHelper = 'Part payments are allowed';
    } else {
      amountHelper =
          'Outstanding for ${Formatters.monthLabel(_billingPeriod)}: '
          '${Formatters.currency(outstanding)} — part payments are allowed';
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _isEditing ? 'Edit entry' : 'New entry',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Add ledger entry',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Type',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TransactionType.values
                    .map(
                      (type) => ChoiceChip(
                        label: Text(type.label),
                        selected: _type == type,
                        onSelected: (selected) {
                          if (selected) _onTypeChanged(type);
                        },
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Category: ${_category.label}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SegmentedButton<TransactionCategory>(
                    showSelectedIcon: false,
                    segments: TransactionCategory.values
                        .map(
                          (category) => ButtonSegment<TransactionCategory>(
                            value: category,
                            label: Text(category.label),
                          ),
                        )
                        .toList(growable: false),
                    selected: <TransactionCategory>{_category},
                    onSelectionChanged: (selection) =>
                        setState(() => _category = selection.first),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Property'),
                child: Text(
                  property?.propertyName ?? 'Property',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              if (_type.requiresTenant) ...<Widget>[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey<TransactionType>(_type),
                  isExpanded: true,
                  initialValue: tenantValue,
                  decoration: const InputDecoration(labelText: 'Tenant'),
                  items: tenantOptions.entries
                      .map(
                        (entry) => DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(
                            entry.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => setState(() => _tenantId = value),
                  validator: (value) =>
                      value == null ? 'Select a tenant' : null,
                ),
              ],
              if (_type == TransactionType.PROPERTY_EXPENSE) ...<Widget>[
                const SizedBox(height: 16),
                DropdownButtonFormField<ExpenseCategory>(
                  initialValue:
                      _expenseCategory ?? ExpenseCategory.MAINTENANCE,
                  decoration: const InputDecoration(
                    labelText: 'Expense category',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: ExpenseCategory.values
                      .map(
                        (cat) => DropdownMenuItem(
                          value: cat,
                          child: Text(cat.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (val) {
                    if (val != null) setState(() => _expenseCategory = val);
                  },
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                readOnly: _ebUsesMeterMath,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: _ebUsesMeterMath ? 'Amount (calculated)' : 'Amount',
                  prefixText: '₹ ',
                  helperText: amountHelper,
                  helperMaxLines: 2,
                ),
                validator: (value) =>
                    _ebUsesMeterMath ? null : Validators.positiveAmount(value),
              ),
              if (remainingDue != null && remainingDue > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Balance remaining after this payment: '
                    '${Formatters.currency(remainingDue)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ledgerColors.pending,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (_type.usesMeterReading) ...<Widget>[
                const SizedBox(height: 16),
                SegmentedButton<_EbEntryMode>(
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<_EbEntryMode>>[
                    ButtonSegment<_EbEntryMode>(
                      value: _EbEntryMode.perUnit,
                      label: Text('Sub-meter units'),
                      icon: Icon(Icons.speed_outlined),
                    ),
                    ButtonSegment<_EbEntryMode>(
                      value: _EbEntryMode.totalBill,
                      label: Text('Total bill'),
                      icon: Icon(Icons.receipt_outlined),
                    ),
                  ],
                  selected: <_EbEntryMode>{_ebMode},
                  onSelectionChanged: (selection) =>
                      _onEbModeChanged(selection.first),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextFormField(
                        controller: _previousReading,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Previous reading',
                          suffixText: 'units',
                        ),
                        onChanged: _onEbFieldChanged,
                        validator: (value) => Validators.amount(
                          value,
                          field: 'Previous reading',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _currentReading,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Current reading',
                          suffixText: 'units',
                        ),
                        onChanged: _onEbFieldChanged,
                        validator: (value) => Validators.amount(
                          value,
                          field: 'Current reading',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ratePerUnit,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Rate per unit',
                    prefixText: '₹ ',
                    suffixText: '/ unit',
                  ),
                  onChanged: _onEbFieldChanged,
                  validator: (value) => _ebMode == _EbEntryMode.totalBill
                      ? null
                      : Validators.positiveAmount(
                          value,
                          field: 'Rate per unit',
                        ),
                ),
                const SizedBox(height: 8),
                DetailRow(
                  label: 'Units consumed',
                  value: ebDetails == null
                      ? '—'
                      : Formatters.units(ebDetails.unitsConsumed),
                ),
                DetailRow(
                  label: _ebMode == _EbEntryMode.totalBill
                      ? 'Bill total'
                      : 'Bill amount',
                  value: ebDetails == null
                      ? '—'
                      : Formatters.currency(ebDetails.amount),
                  valueColor: ledgerColors.income,
                  emphasize: true,
                ),
                if (_ebMode == _EbEntryMode.totalBill &&
                    ebDetails != null &&
                    ebDetails.unitsConsumed > 0)
                  DetailRow(
                    label: 'Effective rate per unit',
                    value: Formatters.currency(ebDetails.unitRate),
                  ),
                if (ebDetails != null && !ebDetails.isValid)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Current reading cannot be lower than the previous reading.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ledgerColors.expense,
                      ),
                    ),
                  ),
                if (_meterPhotoUrl == null) ...<Widget>[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _uploadingMeterPhoto || _saving
                        ? null
                        : _attachMeterPhoto,
                    icon: _uploadingMeterPhoto
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt_outlined),
                    label: Text(
                      _uploadingMeterPhoto
                          ? 'Uploading…'
                          : 'Attach meter photo (optional)',
                    ),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 10),
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
                      Expanded(
                        child: Text(
                          'Meter photo attached (optional)',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Remove meter photo',
                        onPressed: _saving
                            ? null
                            : () => setState(() => _meterPhotoUrl = null),
                      ),
                    ],
                  ),
                ],
              ],
              if (_ebError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _ebError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ledgerColors.expense,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Payment method',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: PaymentMethod.values
                    .map(
                      (method) => ChoiceChip(
                        label: Text(method.label),
                        selected: _paymentMethod == method,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _paymentMethod = method);
                          }
                        },
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_note_outlined),
                title: const Text('Billing period'),
                subtitle: Text(Formatters.monthLabel(_billingPeriod)),
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_month_outlined),
                  tooltip: 'Pick month',
                  onPressed: _saving ? null : _pickBillingPeriod,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.today_outlined),
                title: const Text('Entry date'),
                subtitle: Text(Formatters.date(_recordedAt)),
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_today_outlined),
                  tooltip: 'Pick date',
                  onPressed: _saving ? null : _pickRecordedDate,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              if (_receiptUrl == null)
                OutlinedButton.icon(
                  onPressed: _uploadingReceipt || _saving
                      ? null
                      : _attachReceipt,
                  icon: _uploadingReceipt
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.receipt_long_outlined),
                  label: Text(
                    _uploadingReceipt ? 'Uploading…' : 'Attach receipt',
                  ),
                )
              else
                Row(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _receiptUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.receipt_long_outlined, size: 40),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Receipt attached',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Remove receipt',
                      onPressed: _saving
                          ? null
                          : () => setState(() => _receiptUrl = null),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save entry'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
