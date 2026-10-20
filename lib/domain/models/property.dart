import '../../core/utils/json_utils.dart';
import 'enums.dart';

/// A rental unit owned by the user.
class Property {
  const Property({
    required this.propertyId,
    required this.propertyName,
    required this.address,
    required this.city,
    this.pincode,
    this.type = PropertyType.APARTMENT,
    this.currentStatus = PropertyStatus.VACANT,
    this.activeTenantId,
    this.activeTenantName,
    this.baseRent = 0,
    this.baseMaintenance = 0,
    this.electricityBillingType = ElectricityBillingType.SUB_METER,
    this.currentEbMeterReading = 0,
    this.ratePerUnit = 0,
    this.fixedEbAmount = 0,
    this.notes,
    this.photos = const <String>[],
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String propertyId;
  final String propertyName;
  final String address;
  final String city;
  final String? pincode;
  final PropertyType type;
  final PropertyStatus currentStatus;

  /// Denormalised pointer to the active tenant so list screens need one read.
  final String? activeTenantId;
  final String? activeTenantName;

  final double baseRent;
  final double baseMaintenance;

  final ElectricityBillingType electricityBillingType;

  /// Last recorded sub-meter reading (units). Seed for the next EB bill.
  final double currentEbMeterReading;
  final double ratePerUnit;

  /// Used when [electricityBillingType] is [ElectricityBillingType.FIXED].
  final double fixedEbAmount;

  final String? notes;
  final List<String> photos;

  /// Soft-delete flag — archived properties are hidden but fully retained.
  final bool isArchived;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOccupied => currentStatus == PropertyStatus.OCCUPIED;
  bool get isVacant => currentStatus == PropertyStatus.VACANT;

  /// Rent + maintenance that this unit can generate per month.
  double get monthlyPotentialRent => baseRent + baseMaintenance;

  double get effectiveFixedEb => fixedEbAmount;

  factory Property.fromJson(String propertyId, Map<String, dynamic> json) {
    final created = JsonUtils.toDateTimeOr(json['createdAt'], DateTime.now());
    return Property(
      propertyId: JsonUtils.toStr(json['propertyId'], propertyId),
      propertyName: JsonUtils.toStr(json['propertyName']),
      address: JsonUtils.toStr(json['address']),
      city: JsonUtils.toStr(json['city']),
      pincode: JsonUtils.toNullableStr(json['pincode']),
      type: enumFromName(PropertyType.values, json['type'], PropertyType.OTHER),
      currentStatus: enumFromName(
        PropertyStatus.values,
        json['currentStatus'],
        PropertyStatus.VACANT,
      ),
      activeTenantId: JsonUtils.toNullableStr(json['activeTenantId']),
      activeTenantName: JsonUtils.toNullableStr(json['activeTenantName']),
      baseRent: JsonUtils.toDouble(json['baseRent']),
      baseMaintenance: JsonUtils.toDouble(json['baseMaintenance']),
      electricityBillingType: enumFromName(
        ElectricityBillingType.values,
        json['electricityBillingType'],
        ElectricityBillingType.SUB_METER,
      ),
      currentEbMeterReading: JsonUtils.toDouble(json['currentEbMeterReading']),
      ratePerUnit: JsonUtils.toDouble(json['ratePerUnit']),
      fixedEbAmount: JsonUtils.toDouble(json['fixedEbAmount']),
      notes: JsonUtils.toNullableStr(json['notes']),
      photos: JsonUtils.toStringList(json['photos']),
      isArchived: JsonUtils.toBool(json['isArchived']),
      createdAt: created,
      updatedAt: JsonUtils.toDateTimeOr(json['updatedAt'], created),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'propertyId': propertyId,
        'propertyName': propertyName,
        'address': address,
        'city': city,
        'pincode': pincode,
        'type': type.name,
        'currentStatus': currentStatus.name,
        'activeTenantId': activeTenantId,
        'activeTenantName': activeTenantName,
        'baseRent': JsonUtils.money(baseRent),
        'baseMaintenance': JsonUtils.money(baseMaintenance),
        'electricityBillingType': electricityBillingType.name,
        'currentEbMeterReading': currentEbMeterReading,
        'ratePerUnit': ratePerUnit,
        'fixedEbAmount': JsonUtils.money(fixedEbAmount),
        'notes': notes,
        'photos': photos,
        'isArchived': isArchived,
        'createdAt': JsonUtils.fromDateTime(createdAt),
        'updatedAt': JsonUtils.fromDateTime(updatedAt),
      };

  Property copyWith({
    String? propertyName,
    String? address,
    String? city,
    String? pincode,
    PropertyType? type,
    PropertyStatus? currentStatus,
    String? activeTenantId,
    String? activeTenantName,
    double? baseRent,
    double? baseMaintenance,
    ElectricityBillingType? electricityBillingType,
    double? currentEbMeterReading,
    double? ratePerUnit,
    double? fixedEbAmount,
    String? notes,
    List<String>? photos,
    bool? isArchived,
    DateTime? updatedAt,
  }) =>
      Property(
        propertyId: propertyId,
        propertyName: propertyName ?? this.propertyName,
        address: address ?? this.address,
        city: city ?? this.city,
        pincode: pincode ?? this.pincode,
        type: type ?? this.type,
        currentStatus: currentStatus ?? this.currentStatus,
        activeTenantId: activeTenantId ?? this.activeTenantId,
        activeTenantName: activeTenantName ?? this.activeTenantName,
        baseRent: baseRent ?? this.baseRent,
        baseMaintenance: baseMaintenance ?? this.baseMaintenance,
        electricityBillingType: electricityBillingType ?? this.electricityBillingType,
        currentEbMeterReading:
            currentEbMeterReading ?? this.currentEbMeterReading,
        ratePerUnit: ratePerUnit ?? this.ratePerUnit,
        fixedEbAmount: fixedEbAmount ?? this.fixedEbAmount,
        notes: notes ?? this.notes,
        photos: photos ?? this.photos,
        isArchived: isArchived ?? this.isArchived,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  /// Clears the tenant pointer when a tenant exits.
  Property withoutActiveTenant({PropertyStatus? status}) => Property(
        propertyId: propertyId,
        propertyName: propertyName,
        address: address,
        city: city,
        pincode: pincode,
        type: type,
        currentStatus: status ?? PropertyStatus.VACANT,
        activeTenantId: null,
        activeTenantName: null,
        baseRent: baseRent,
        baseMaintenance: baseMaintenance,
        electricityBillingType: electricityBillingType,
        currentEbMeterReading: currentEbMeterReading,
        ratePerUnit: ratePerUnit,
        fixedEbAmount: fixedEbAmount,
        notes: notes,
        photos: photos,
        isArchived: isArchived,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  @override
  bool operator ==(Object other) =>
      other is Property &&
      other.propertyId == propertyId &&
      other.updatedAt == updatedAt &&
      other.currentStatus == currentStatus &&
      other.activeTenantId == activeTenantId;

  @override
  int get hashCode => Object.hash(
        propertyId,
        updatedAt,
        currentStatus,
        activeTenantId,
      );

  @override
  String toString() => 'Property($propertyId, $propertyName)';
}
