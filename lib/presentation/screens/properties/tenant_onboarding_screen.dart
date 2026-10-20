import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/ledger_transaction.dart';
import '../../../domain/models/property.dart';
import '../../../domain/models/tenant.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/auth_providers.dart';
import '../../../providers/property_providers.dart';
import '../../../providers/tenant_providers.dart';

/// Three step wizard that adds a tenant to a property, records the advance
/// deposit and marks the property occupied.
class TenantOnboardingScreen extends ConsumerStatefulWidget {
  const TenantOnboardingScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<TenantOnboardingScreen> createState() =>
      _TenantOnboardingScreenState();
}

class _TenantOnboardingScreenState
    extends ConsumerState<TenantOnboardingScreen> {
  final GlobalKey<FormState> _detailsFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _leaseFormKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _advanceController = TextEditingController();
  final TextEditingController _rentController = TextEditingController();
  final TextEditingController _maintenanceController = TextEditingController();

  int _step = 0;
  DateTime _leaseStart = DateTime.now();
  DateTime? _leaseEnd;
  bool _usePropertyDefaults = true;

  Uint8List? _idProofBytes;
  String? _idProofUrl;
  bool _uploadingProof = false;

  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _advanceController.dispose();
    _rentController.dispose();
    _maintenanceController.dispose();
    super.dispose();
  }

  String _numText(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final propertiesAsync = ref.watch(propertiesProvider);
    final property = ref.watch(propertyProvider(widget.propertyId));
    final activeTenant =
        ref.watch(activeTenantForPropertyProvider(widget.propertyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Add tenant')),
      body: _body(propertiesAsync, property, activeTenant),
    );
  }

  Widget _body(
    AsyncValue<List<Property>> propertiesAsync,
    Property? property,
    Tenant? activeTenant,
  ) {
    if (property == null) {
      if (propertiesAsync.isLoading) {
        return const LoadingView(message: 'Loading property…');
      }
      return ErrorView(
        message: propertiesAsync.hasError
            ? 'We could not load this property.'
            : 'This property could not be found.',
        onRetry: () => ref.invalidate(propertiesProvider),
      );
    }

    if (activeTenant != null || property.activeTenantId != null) {
      final name = activeTenant?.name ?? property.activeTenantName ?? 'A tenant';
      return EmptyState(
        icon: Icons.people_alt_outlined,
        title: 'Property already occupied',
        message:
            '$name is currently renting ${property.propertyName}. '
            'Exit the current tenant before adding a new one.',
        action: FilledButton.icon(
          onPressed: () => context.go(AppRoutes.property(property.propertyId)),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back to property'),
        ),
      );
    }

    return Stepper(
      currentStep: _step,
      type: StepperType.vertical,
      physics: const AlwaysScrollableScrollPhysics(),
      onStepTapped: (index) {
        if (index < _step) setState(() => _step = index);
      },
      onStepContinue: () => _onContinue(property),
      onStepCancel: () {
        if (_step > 0) setState(() => _step -= 1);
      },
      controlsBuilder: (context, details) => _controls(details),
      steps: <Step>[
        Step(
          title: const Text('Tenant details'),
          isActive: _step >= 0,
          state: _stateFor(0),
          content: _stepOne(),
        ),
        Step(
          title: const Text('Lease & deposit'),
          isActive: _step >= 1,
          state: _stateFor(1),
          content: _stepTwo(property),
        ),
        Step(
          title: const Text('Review'),
          isActive: _step >= 2,
          state: _stateFor(2),
          content: _stepThree(property),
        ),
      ],
    );
  }

  StepState _stateFor(int index) =>
      index < _step ? StepState.complete : StepState.indexed;

  Widget _controls(ControlsDetails details) {
    final isLast = details.stepIndex == 2;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton(
              onPressed: _submitting ? null : details.onStepContinue,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isLast ? 'Add tenant' : 'Continue'),
            ),
          ),
          if (details.stepIndex > 0) ...<Widget>[
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : details.onStepCancel,
                child: const Text('Back'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------- step one

  Widget _stepOne() {
    return Form(
      key: _detailsFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Tenant name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: Validators.name,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            validator: Validators.phone,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email (optional)',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              return trimmed.isEmpty ? null : Validators.email(trimmed);
            },
          ),
          const SizedBox(height: 24),
          const SectionHeader(
            title: 'ID proof',
            subtitle: 'Optional — kept with the tenant record',
          ),
          const SizedBox(height: 12),
          _idProofPreview(),
        ],
      ),
    );
  }

  Widget _idProofPreview() {
    if (_uploadingProof) {
      return const Row(
        children: <Widget>[
          SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Uploading ID proof…'),
        ],
      );
    }

    final bytes = _idProofBytes;
    if (bytes != null) {
      final theme = Theme.of(context);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 4),
                Text(
                  _idProofUrl == null ? 'Uploading…' : 'ID proof uploaded',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                TextButton.icon(
                  onPressed: _clearIdProof,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return OutlinedButton.icon(
      onPressed: _pickAndUploadProof,
      icon: const Icon(Icons.add_a_photo_outlined),
      label: const Text('Upload ID proof'),
    );
  }

  void _clearIdProof() => setState(() {
        _idProofBytes = null;
        _idProofUrl = null;
      });

  Future<void> _pickAndUploadProof() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      _showSnack('You are not signed in.');
      return;
    }

    final source = await pickImageSource(context);
    if (source == null || !mounted) return;

    final picked = await pickImageSafely(
      context,
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingProof = true);
    try {
      final bytes = await File(picked.path).readAsBytes();
      if (!mounted) return;
      setState(() => _idProofBytes = bytes);

      final url = await ref.read(storageRepositoryProvider).uploadBytes(
            path: 'users/$uid/properties/${widget.propertyId}/tenants/proofs/'
                '${DateTime.now().millisecondsSinceEpoch}.jpg',
            bytes: bytes,
            contentType: 'image/jpeg',
          );
      if (!mounted) return;
      setState(() {
        _idProofUrl = url;
        _uploadingProof = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploadingProof = false;
        _idProofBytes = null;
      });
      _showSnack('We could not upload the ID proof. Try again or skip it.');
    }
  }

  // -------------------------------------------------------------- step two

  Widget _stepTwo(Property property) {
    return Form(
      key: _leaseFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Lease start'),
              subtitle: Text(Formatters.date(_leaseStart)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickLeaseStart,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_busy_outlined),
              title: const Text('Lease end (optional)'),
              subtitle: Text(
                _leaseEnd == null
                    ? 'Open-ended / monthly'
                    : Formatters.date(_leaseEnd!),
              ),
              trailing: _leaseEnd == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear lease end',
                      onPressed: () => setState(() => _leaseEnd = null),
                    ),
              onTap: _pickLeaseEnd,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _advanceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Advance deposit',
              // Shown as a hint rather than seeded as text so the user can
              // type straight away; an empty field is read as 0.
              hintText: '0',
              prefixIcon: Icon(Icons.savings_outlined),
            ),
            validator: (value) =>
                Validators.optionalAmount(value, field: 'Advance'),
          ),
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile(
              title: const Text('Use property defaults'),
              subtitle: Text(
                '${Formatters.currency(property.baseRent)} rent · '
                '${Formatters.currency(property.baseMaintenance)} maintenance',
              ),
              value: _usePropertyDefaults,
              onChanged: (value) => _onDefaultsChanged(value, property),
            ),
          ),
          if (!_usePropertyDefaults) ...<Widget>[
            const SizedBox(height: 16),
            TextFormField(
              controller: _rentController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Monthly rent override',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (value) => Validators.amount(value, field: 'Rent'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _maintenanceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Monthly maintenance override',
                prefixIcon: Icon(Icons.handyman_outlined),
              ),
              validator: (value) =>
                  Validators.amount(value, field: 'Maintenance'),
            ),
          ],
        ],
      ),
    );
  }

  void _onDefaultsChanged(bool useDefaults, Property property) {
    setState(() {
      _usePropertyDefaults = useDefaults;
      if (!useDefaults) {
        if (_rentController.text.trim().isEmpty) {
          _rentController.text = _numText(property.baseRent);
        }
        if (_maintenanceController.text.trim().isEmpty) {
          _maintenanceController.text = _numText(property.baseMaintenance);
        }
      }
    });
  }

  Future<void> _pickLeaseStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _leaseStart,
      firstDate: DateTime(now.year - 30),
      lastDate: DateTime(now.year + 30),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _leaseStart = picked;
      if (_leaseEnd != null && _leaseEnd!.isBefore(_leaseStart)) {
        _leaseEnd = null;
      }
    });
  }

  Future<void> _pickLeaseEnd() async {
    final now = DateTime.now();
    final candidate = _leaseEnd ?? _leaseStart.add(const Duration(days: 330));
    final picked = await showDatePicker(
      context: context,
      initialDate: candidate.isBefore(_leaseStart) ? _leaseStart : candidate,
      firstDate: _leaseStart,
      lastDate: DateTime(now.year + 30),
    );
    if (!mounted || picked == null) return;
    setState(() => _leaseEnd = picked);
  }

  // ------------------------------------------------------------ step three

  Widget _stepThree(Property property) {
    final uid = ref.watch(currentUidProvider) ?? '';
    final tenant = _composeTenant(property: property, uid: uid);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(
          title: 'Review',
          subtitle: 'Confirm these details before adding the tenant',
        ),
        const SizedBox(height: 16),
        DetailRow(label: 'Property', value: property.propertyName),
        DetailRow(label: 'Tenant', value: tenant.name),
        DetailRow(label: 'Phone', value: tenant.phone),
        if (tenant.email != null)
          DetailRow(label: 'Email', value: tenant.email!),
        DetailRow(label: 'Lease', value: _leaseWindowLabel()),
        DetailRow(
          label: 'Advance deposit',
          value: Formatters.currency(tenant.advanceDepositAmount),
        ),
        DetailRow(
          label: 'Monthly rent',
          value: Formatters.currency(tenant.rentFor(property.baseRent)),
        ),
        DetailRow(
          label: 'Monthly maintenance',
          value: Formatters.currency(
            tenant.maintenanceFor(property.baseMaintenance),
          ),
        ),
        if (tenant.hasOverrides)
          const DetailRow(label: 'Rates', value: 'Custom override for this tenant'),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tenant.advanceDepositAmount > 0
                      ? 'The advance of '
                          '${Formatters.currency(tenant.advanceDepositAmount)} '
                          'will be recorded as an “Advance received” income '
                          'entry, and the property will be marked as occupied.'
                      : 'No advance amount was entered, so no advance entry '
                          'will be recorded. The property will be marked as '
                          'occupied.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _leaseWindowLabel() {
    final start = Formatters.date(_leaseStart);
    final end = _leaseEnd;
    return end == null ? 'From $start' : '$start – ${Formatters.date(end)}';
  }

  // ------------------------------------------------------------- submission

  Tenant _composeTenant({required Property property, required String uid}) {
    final now = DateTime.now();
    final email = _emailController.text.trim();
    return Tenant(
      tenantId: '',
      propertyId: property.propertyId,
      ownerId: uid,
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      email: email.isEmpty ? null : email,
      idProofUrl: _idProofUrl,
      advanceDepositAmount:
          double.tryParse(_advanceController.text.trim()) ?? 0,
      rentOverride: _usePropertyDefaults
          ? null
          : double.tryParse(_rentController.text.trim()),
      maintenanceOverride: _usePropertyDefaults
          ? null
          : double.tryParse(_maintenanceController.text.trim()),
      leaseStartDate: _leaseStart,
      leaseEndDate: _leaseEnd,
      status: TenantStatus.ACTIVE,
      createdAt: now,
      updatedAt: now,
    );
  }

  void _onContinue(Property property) {
    FocusScope.of(context).unfocus();
    if (_step == 0) {
      if (_detailsFormKey.currentState?.validate() ?? false) {
        setState(() => _step = 1);
      }
      return;
    }
    if (_step == 1) {
      final rangeError = Validators.dateRange(_leaseStart, _leaseEnd);
      final valid = _leaseFormKey.currentState?.validate() ?? false;
      if (rangeError != null) {
        _showSnack(rangeError);
        return;
      }
      if (valid) setState(() => _step = 2);
      return;
    }
    _submit(property);
  }

  Future<void> _submit(Property property) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      _showSnack('You are not signed in.');
      return;
    }

    final tenant = _composeTenant(property: property, uid: uid);
    final now = DateTime.now();
    final advance = tenant.advanceDepositAmount;
    final advanceTransaction = advance > 0
        ? LedgerTransaction(
            transactionId: '',
            propertyId: property.propertyId,
            ownerId: uid,
            tenantName: tenant.name,
            type: TransactionType.ADVANCE_RECEIVED,
            category: TransactionCategory.INCOME,
            amount: advance,
            paymentMethod: PaymentMethod.CASH,
            billingPeriod: Formatters.periodKey(now),
            notes: 'Advance deposit',
            recordedAt: now,
            createdBy: uid,
            createdAt: now,
          )
        : null;

    setState(() => _submitting = true);
    final id = await ref.read(tenantControllerProvider.notifier).onboard(
          tenant: tenant,
          advanceTransaction: advanceTransaction,
        );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (id == null) {
      _showSnack('We could not add the tenant. Please try again.');
      return;
    }

    _showSnack('${tenant.name} was added to ${property.propertyName}.');
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.property(property.propertyId));
    }
  }
}
