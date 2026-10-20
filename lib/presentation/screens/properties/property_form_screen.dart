import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/property.dart';
import '../../../providers/auth_providers.dart';
import '../../../providers/property_providers.dart';

/// Create / edit form for a [Property].
///
/// [propertyId] is null when creating a new property and non-null when editing
/// an existing one.
class PropertyFormScreen extends ConsumerStatefulWidget {
  const PropertyFormScreen({super.key, this.propertyId});

  final String? propertyId;

  @override
  ConsumerState<PropertyFormScreen> createState() => _PropertyFormScreenState();
}

class _PropertyFormScreenState extends ConsumerState<PropertyFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _baseRentController = TextEditingController();
  final _baseMaintenanceController = TextEditingController();
  final _ratePerUnitController = TextEditingController();
  final _meterReadingController = TextEditingController();
  final _fixedEbController = TextEditingController();
  final _notesController = TextEditingController();

  PropertyType _type = PropertyType.APARTMENT;
  PropertyStatus _status = PropertyStatus.VACANT;
  ElectricityBillingType _billingType = ElectricityBillingType.SUB_METER;

  bool _populated = false;
  bool _statusLocked = false;

  bool get _isEditing => widget.propertyId != null;

  @override
  void initState() {
    super.initState();
    final profileRate = ref.read(userProfileProvider).valueOrNull?.defaultRatePerUnit ??
        AppConstants.defaultRatePerUnit;
    _ratePerUnitController.text = _formatNumber(profileRate);

    if (!_isEditing) return;

    final existing = ref.read(propertyProvider(widget.propertyId!));
    if (existing != null) {
      _apply(existing);
      return;
    }
    // The property may still be streaming in — populate once it arrives.
    ref.listenManual<Property?>(
      propertyProvider(widget.propertyId!),
      (_, next) {
        if (next != null && mounted) setState(() => _apply(next));
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
    _baseRentController.dispose();
    _baseMaintenanceController.dispose();
    _ratePerUnitController.dispose();
    _meterReadingController.dispose();
    _fixedEbController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _apply(Property property) {
    if (_populated) return;
    _populated = true;
    _nameController.text = property.propertyName;
    _addressController.text = property.address;
    _cityController.text = property.city;
    _pincodeController.text = property.pincode ?? '';
    _baseRentController.text = _formatNumber(property.baseRent);
    _baseMaintenanceController.text = _formatNumber(property.baseMaintenance);
    _ratePerUnitController.text = _formatNumber(property.ratePerUnit);
    _meterReadingController.text = _formatNumber(property.currentEbMeterReading);
    _fixedEbController.text = _formatNumber(property.fixedEbAmount);
    _notesController.text = property.notes ?? '';
    _type = property.type;
    _status = property.currentStatus;
    _billingType = property.electricityBillingType;
    _statusLocked = property.currentStatus == PropertyStatus.OCCUPIED;
  }

  double _readAmount(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    FocusScope.of(context).unfocus();

    final controller = ref.read(propertyControllerProvider.notifier);
    final name = _nameController.text.trim();
    final address = _addressController.text.trim();
    final city = _cityController.text.trim();
    final pincodeText = _pincodeController.text.trim();
    final pincode = pincodeText.isEmpty ? null : pincodeText;
    final notesText = _notesController.text.trim();
    final notes = notesText.isEmpty ? null : notesText;

    final baseRent = _readAmount(_baseRentController);
    final baseMaintenance = _readAmount(_baseMaintenanceController);

    if (_isEditing) {
      final existing = ref.read(propertyProvider(widget.propertyId!));
      if (existing == null) return;
      final property = existing.copyWith(
        propertyName: name,
        address: address,
        city: city,
        pincode: pincode,
        type: _type,
        currentStatus: _status,
        baseRent: baseRent,
        baseMaintenance: baseMaintenance,
        electricityBillingType: _billingType,
        ratePerUnit:
            _billingType == ElectricityBillingType.SUB_METER
                ? _readAmount(_ratePerUnitController)
                : 0,
        currentEbMeterReading:
            _billingType == ElectricityBillingType.SUB_METER
                ? _readAmount(_meterReadingController)
                : 0,
        fixedEbAmount: _billingType == ElectricityBillingType.FIXED
            ? _readAmount(_fixedEbController)
            : 0,
        notes: notes,
        updatedAt: DateTime.now(),
      );
      final updated = await controller.saveProperty(property);
      if (!mounted) return;
      if (updated) {
        context.pop();
      } else {
        _showError();
      }
      return;
    }

    final now = DateTime.now();
    final property = Property(
      propertyId: '',
      propertyName: name,
      address: address,
      city: city,
      pincode: pincode,
      type: _type,
      currentStatus: _status,
      baseRent: baseRent,
      baseMaintenance: baseMaintenance,
      electricityBillingType: _billingType,
      ratePerUnit: _billingType == ElectricityBillingType.SUB_METER
          ? _readAmount(_ratePerUnitController)
          : 0,
      currentEbMeterReading:
          _billingType == ElectricityBillingType.SUB_METER
              ? _readAmount(_meterReadingController)
              : 0,
      fixedEbAmount: _billingType == ElectricityBillingType.FIXED
          ? _readAmount(_fixedEbController)
          : 0,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    final createdId = await controller.create(property);
    if (!mounted) return;
    if (createdId != null) {
      context.pop();
    } else {
      _showError();
    }
  }

  void _showError() {
    final error = ref.read(propertyControllerProvider).error;
    final message = error is AppException
        ? error.message
        : 'Could not save the property. Please try again.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(propertyControllerProvider).isLoading;
    final propertiesAsync = ref.watch(propertiesProvider);
    final existing =
        _isEditing ? ref.watch(propertyProvider(widget.propertyId!)) : null;

    if (_isEditing && existing == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit property')),
        body: propertiesAsync.isLoading
            ? const LoadingView()
            : const ErrorView(message: 'Property not found'),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit property' : 'Add property')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Property name'),
              validator: Validators.name,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressController,
              minLines: 1,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Address'),
              validator: (value) => Validators.required(value, field: 'Address'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cityController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'City'),
              validator: (value) => Validators.required(value, field: 'City'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pincodeController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Pincode (optional)'),
              validator: _validatePincode,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<PropertyType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Property type'),
              items: PropertyType.values
                  .map(
                    (type) =>
                        DropdownMenuItem(value: type, child: Text(type.label)),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<PropertyStatus>(
              initialValue: _status,
              decoration: InputDecoration(
                labelText: 'Status',
                helperText: _statusLocked
                    ? 'Occupied — the active tenant controls this status.'
                    : null,
              ),
              items: PropertyStatus.values
                  .map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(status.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _statusLocked
                  ? null
                  : (value) {
                      if (value != null) setState(() => _status = value);
                    },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _baseRentController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              decoration:
                  const InputDecoration(labelText: 'Base rent (per month)'),
              validator: (value) => Validators.amount(value, field: 'Base rent'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _baseMaintenanceController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Base maintenance (per month)',
              ),
              validator: (value) =>
                  Validators.amount(value, field: 'Base maintenance'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ElectricityBillingType>(
              initialValue: _billingType,
              decoration: const InputDecoration(labelText: 'Electricity billing'),
              items: ElectricityBillingType.values
                  .map(
                    (type) =>
                        DropdownMenuItem(value: type, child: Text(type.label)),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) setState(() => _billingType = value);
              },
            ),
            if (_billingType == ElectricityBillingType.SUB_METER) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _ratePerUnitController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Rate per unit',
                  suffixText: 'per unit',
                ),
                validator: (value) =>
                    Validators.amount(value, field: 'Rate per unit'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _meterReadingController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Current meter reading',
                  suffixText: 'units',
                ),
                validator: (value) =>
                    Validators.amount(value, field: 'Meter reading'),
              ),
            ],
            if (_billingType == ElectricityBillingType.FIXED) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _fixedEbController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                decoration:
                    const InputDecoration(labelText: 'Fixed monthly EB amount'),
                validator: (value) =>
                    Validators.amount(value, field: 'Fixed EB amount'),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton(
          onPressed: saving ? null : _submit,
          child: saving
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                )
              : const Text('Save property'),
        ),
      ),
    );
  }
}

String? _validatePincode(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  if (!RegExp(r'^\d{6}$').hasMatch(trimmed)) return 'Enter a 6-digit pincode';
  return null;
}

String _formatNumber(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';
