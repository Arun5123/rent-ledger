import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../domain/models/tenant.dart';
import '../../../providers/property_providers.dart';
import '../../../providers/tenant_providers.dart';

/// Opens the edit tenant bottom sheet.
///
/// Returns `true` when updated, `false` or `null` when cancelled.
Future<bool?> showEditTenantSheet(
  BuildContext context, {
  required String propertyId,
  required String tenantId,
  Tenant? tenant,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _TenantEditSheetContent(
      propertyId: propertyId,
      tenantId: tenantId,
      tenant: tenant,
    ),
  );
}

/// Dedicated full screen for editing tenant details.
class TenantEditScreen extends ConsumerStatefulWidget {
  const TenantEditScreen({
    super.key,
    required this.propertyId,
    required this.tenantId,
    this.tenant,
  });

  final String propertyId;
  final String tenantId;
  final Tenant? tenant;

  @override
  ConsumerState<TenantEditScreen> createState() => _TenantEditScreenState();
}

class _TenantEditScreenState extends ConsumerState<TenantEditScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _rentOverrideController = TextEditingController();
  final _maintenanceOverrideController = TextEditingController();

  DateTime? _leaseStartDate;
  DateTime? _leaseEndDate;
  bool _hasOverrides = false;
  bool _populated = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.tenant != null) {
      _apply(widget.tenant!);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _rentOverrideController.dispose();
    _maintenanceOverrideController.dispose();
    super.dispose();
  }

  void _apply(Tenant tenant) {
    if (_populated) return;
    _populated = true;
    _nameController.text = tenant.name;
    _phoneController.text = tenant.phone;
    _emailController.text = tenant.email ?? '';
    _leaseStartDate = tenant.leaseStartDate;
    _leaseEndDate = tenant.leaseEndDate;
    _hasOverrides = tenant.hasOverrides;
    if (tenant.rentOverride != null) {
      _rentOverrideController.text = _formatNumber(tenant.rentOverride!);
    }
    if (tenant.maintenanceOverride != null) {
      _maintenanceOverrideController.text =
          _formatNumber(tenant.maintenanceOverride!);
    }
  }

  static String _formatNumber(double value) =>
      value == value.roundToDouble() ? value.round().toString() : value.toString();

  Future<void> _pickLeaseStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _leaseStartDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 10),
      helpText: 'Select lease start date',
    );
    if (picked == null || !mounted) return;
    setState(() => _leaseStartDate = picked);
  }

  Future<void> _pickLeaseEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _leaseEndDate ??
          (_leaseStartDate != null
              ? _leaseStartDate!.add(const Duration(days: 365))
              : DateTime.now().add(const Duration(days: 365))),
      firstDate: _leaseStartDate ?? DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 15),
      helpText: 'Select lease end date',
    );
    if (picked == null || !mounted) return;
    setState(() => _leaseEndDate = picked);
  }

  Future<void> _save(Tenant tenant) async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _saving = true);

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final emailText = _emailController.text.trim();
    final email = emailText.isEmpty ? null : emailText;

    double? rentOverride;
    double? maintenanceOverride;
    if (_hasOverrides) {
      final rentText = _rentOverrideController.text.trim();
      final maintText = _maintenanceOverrideController.text.trim();
      if (rentText.isNotEmpty) {
        rentOverride = double.tryParse(rentText);
      }
      if (maintText.isNotEmpty) {
        maintenanceOverride = double.tryParse(maintText);
      }
    }

    final updated = tenant.copyWith(
      name: name,
      phone: phone,
      email: email,
      clearEmail: email == null,
      leaseStartDate: _leaseStartDate ?? tenant.leaseStartDate,
      leaseEndDate: _leaseEndDate,
      clearLeaseEndDate: _leaseEndDate == null,
      rentOverride: rentOverride,
      clearRentOverride: rentOverride == null,
      maintenanceOverride: maintenanceOverride,
      clearMaintenanceOverride: maintenanceOverride == null,
      updatedAt: DateTime.now(),
    );

    final ok =
        await ref.read(tenantControllerProvider.notifier).saveTenant(updated);

    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated details for ${updated.name}.')),
      );
      if (context.canPop()) {
        context.pop(true);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update tenant details. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenant = widget.tenant ??
        ref.watch(tenantProvider((widget.propertyId, widget.tenantId)));
    final property = ref.watch(propertyProvider(widget.propertyId));

    if (tenant == null) {
      final loading =
          ref.watch(propertyTenantsProvider(widget.propertyId)).isLoading;
      return Scaffold(
        appBar: AppBar(title: const Text('Edit tenant details')),
        body: loading
            ? const LoadingView(message: 'Loading tenant details…')
            : const ErrorView(message: 'Tenant not found'),
      );
    }

    if (!_populated) {
      _apply(tenant);
    }

    final theme = Theme.of(context);
    final isExited = tenant.isExited;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit tenant details'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(tenant),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      child: const Icon(Icons.person),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tenant.name,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            property?.propertyName ?? 'Property',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isExited
                            ? theme.colorScheme.surfaceContainerHighest
                            : theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        tenant.status.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isExited
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isExited) ...[
              const SizedBox(height: 12),
              Card(
                color: theme.colorScheme.surfaceContainerLowest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Past tenant record. Updating name, phone, or email will update historical statements and audit records.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Tenant details',
                      subtitle: 'Primary contact information',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Tenant name *',
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
                        labelText: 'Phone number *',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: Validators.phone,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Email (optional)',
                        prefixIcon: Icon(Icons.mail_outline),
                        helperText: 'For notifications & receipts',
                      ),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        return trimmed.isEmpty ? null : Validators.email(trimmed);
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (!isExited) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(
                        title: 'Lease & overrides',
                        subtitle: 'Optional lease terms and rate overrides',
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_outlined),
                        title: const Text('Lease start date'),
                        subtitle: Text(
                          _leaseStartDate == null
                              ? 'Not set'
                              : Formatters.date(_leaseStartDate!),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _pickLeaseStart,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_busy_outlined),
                        title: const Text('Lease end date (optional)'),
                        subtitle: Text(
                          _leaseEndDate == null
                              ? 'Open-ended / monthly'
                              : Formatters.date(_leaseEndDate!),
                        ),
                        trailing: _leaseEndDate == null
                            ? const Icon(Icons.chevron_right)
                            : IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: 'Clear end date',
                                onPressed: () =>
                                    setState(() => _leaseEndDate = null),
                              ),
                        onTap: _pickLeaseEnd,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Custom rent / maintenance override'),
                        subtitle: Text(
                          property == null
                              ? 'Set tenant-specific rates'
                              : 'Default: ${Formatters.currency(property.baseRent)} rent, ${Formatters.currency(property.baseMaintenance)} maintenance',
                        ),
                        value: _hasOverrides,
                        onChanged: (val) => setState(() => _hasOverrides = val),
                      ),
                      if (_hasOverrides) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _rentOverrideController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Monthly rent override',
                            prefixIcon: Icon(Icons.payments_outlined),
                            prefixText: '${AppConstants.currencySymbol} ',
                          ),
                          validator: (value) => _hasOverrides
                              ? Validators.amount(value, field: 'Rent override')
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _maintenanceOverrideController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Monthly maintenance override',
                            prefixIcon: Icon(Icons.handyman_outlined),
                            prefixText: '${AppConstants.currencySymbol} ',
                          ),
                          validator: (value) => _hasOverrides
                              ? Validators.amount(
                                  value,
                                  field: 'Maintenance override',
                                )
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => context.pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(tenant),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save changes'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal bottom sheet content for editing tenant details.
class _TenantEditSheetContent extends ConsumerStatefulWidget {
  const _TenantEditSheetContent({
    required this.propertyId,
    required this.tenantId,
    this.tenant,
  });

  final String propertyId;
  final String tenantId;
  final Tenant? tenant;

  @override
  ConsumerState<_TenantEditSheetContent> createState() =>
      _TenantEditSheetContentState();
}

class _TenantEditSheetContentState
    extends ConsumerState<_TenantEditSheetContent> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  bool _populated = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.tenant != null) {
      _apply(widget.tenant!);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _apply(Tenant tenant) {
    if (_populated) return;
    _populated = true;
    _nameController.text = tenant.name;
    _phoneController.text = tenant.phone;
    _emailController.text = tenant.email ?? '';
  }

  Future<void> _save(Tenant tenant) async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _saving = true);

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final emailText = _emailController.text.trim();
    final email = emailText.isEmpty ? null : emailText;

    final updated = tenant.copyWith(
      name: name,
      phone: phone,
      email: email,
      clearEmail: email == null,
      updatedAt: DateTime.now(),
    );

    final ok =
        await ref.read(tenantControllerProvider.notifier).saveTenant(updated);

    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated details for ${updated.name}.')),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update tenant details. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenant = widget.tenant ??
        ref.watch(tenantProvider((widget.propertyId, widget.tenantId)));
    final theme = Theme.of(context);

    if (tenant == null) {
      final loading =
          ref.watch(propertyTenantsProvider(widget.propertyId)).isLoading;
      return Padding(
        padding: const EdgeInsets.all(24),
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : const Center(child: Text('Tenant not found')),
      );
    }

    if (!_populated) {
      _apply(tenant);
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit tenant details',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Update name, phone and email',
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
                    onPressed: _saving ? null : () => Navigator.pop(context, false),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Tenant name *',
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
                  labelText: 'Phone number *',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: Validators.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                  prefixIcon: Icon(Icons.mail_outline),
                  helperText: 'For notifications & receipts',
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  return trimmed.isEmpty ? null : Validators.email(trimmed);
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: [
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
                      onPressed: _saving ? null : () => _save(tenant),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
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
