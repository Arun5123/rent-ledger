import '../../core/utils/json_utils.dart';
import 'enums.dart';

/// A single line-item deduction applied during tenant exit settlement.
class Deduction {
  const Deduction({required this.label, required this.amount});

  final String label;
  final double amount;

  factory Deduction.fromJson(Map<String, dynamic> json) => Deduction(
        label: JsonUtils.toStr(json['label']),
        amount: JsonUtils.toDouble(json['amount']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'label': label,
        'amount': JsonUtils.money(amount),
      };
}

/// Immutable snapshot captured when a tenant vacates.
///
/// The settlement is fully denormalised so the statement can be re-printed
/// years later without re-deriving rates that may have changed.
class TenantExitDetails {
  const TenantExitDetails({
    required this.exitedAt,
    required this.advanceDeposit,
    this.finalMeterReading = 0,
    this.pendingRent = 0,
    this.pendingMaintenance = 0,
    this.pendingEb = 0,
    this.pendingOther = 0,
    this.deductions = const <Deduction>[],
    this.depositRefunded = 0,
    this.amountDueFromTenant = 0,
    this.amountPaidByTenant = 0,
    this.paymentMethod,
    this.meterPhotoUrl,
    this.deductionReason,
    this.exitStatementUrl,
    this.notes,
  });

  final DateTime exitedAt;
  final double advanceDeposit;
  final double finalMeterReading;
  final double pendingRent;
  final double pendingMaintenance;
  final double pendingEb;
  final double pendingOther;
  final List<Deduction> deductions;

  /// Positive amount paid back to the tenant (0 when nothing is refundable).
  final double depositRefunded;

  /// Positive amount still owed *by* the tenant (0 when fully settled).
  final double amountDueFromTenant;

  /// Positive amount settled/paid *by* the tenant at exit.
  final double amountPaidByTenant;

  /// Payment method used for the exit settlement transaction (if any).
  final PaymentMethod? paymentMethod;

  /// Optional photo of the final electricity sub-meter reading.
  final String? meterPhotoUrl;

  final String? deductionReason;
  final String? exitStatementUrl;
  final String? notes;

  double get totalPending =>
      pendingRent + pendingMaintenance + pendingEb + pendingOther;

  double get totalDeductions =>
      deductions.fold<double>(0, (sum, d) => sum + d.amount);

  /// Net settlement: advance minus what the tenant owes.
  double get netSettlement => advanceDeposit - totalPending - totalDeductions;

  bool get isRefundDue => netSettlement > 0;

  factory TenantExitDetails.fromJson(Map<String, dynamic> json) {
    final rawDeductions = json['deductions'];
    return TenantExitDetails(
      exitedAt: JsonUtils.toDateTimeOr(json['exitedAt'], DateTime.now()),
      advanceDeposit: JsonUtils.toDouble(json['advanceDeposit']),
      finalMeterReading: JsonUtils.toDouble(json['finalMeterReading']),
      pendingRent: JsonUtils.toDouble(json['pendingRent']),
      pendingMaintenance: JsonUtils.toDouble(json['pendingMaintenance']),
      pendingEb: JsonUtils.toDouble(json['pendingEb']),
      pendingOther: JsonUtils.toDouble(json['pendingOther']),
      deductions: rawDeductions is List
          ? rawDeductions
              .whereType<Map>()
              .map((e) => Deduction.fromJson(
                    e.map((k, v) => MapEntry(k.toString(), v)),
                  ))
              .toList(growable: false)
          : const <Deduction>[],
      depositRefunded: JsonUtils.toDouble(json['depositRefunded']),
      amountDueFromTenant: JsonUtils.toDouble(json['amountDueFromTenant']),
      amountPaidByTenant: JsonUtils.toDouble(json['amountPaidByTenant']),
      paymentMethod: json['paymentMethod'] == null
          ? null
          : enumFromName(
              PaymentMethod.values,
              json['paymentMethod'],
              PaymentMethod.UPI,
            ),
      meterPhotoUrl: JsonUtils.toNullableStr(json['meterPhotoUrl']),
      deductionReason: JsonUtils.toNullableStr(json['deductionReason']),
      exitStatementUrl: JsonUtils.toNullableStr(json['exitStatementUrl']),
      notes: JsonUtils.toNullableStr(json['notes']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'exitedAt': JsonUtils.fromDateTime(exitedAt),
        'advanceDeposit': JsonUtils.money(advanceDeposit),
        'finalMeterReading': finalMeterReading,
        'pendingRent': JsonUtils.money(pendingRent),
        'pendingMaintenance': JsonUtils.money(pendingMaintenance),
        'pendingEb': JsonUtils.money(pendingEb),
        'pendingOther': JsonUtils.money(pendingOther),
        'deductions': deductions.map((d) => d.toJson()).toList(),
        'depositRefunded': JsonUtils.money(depositRefunded),
        'amountDueFromTenant': JsonUtils.money(amountDueFromTenant),
        'amountPaidByTenant': JsonUtils.money(amountPaidByTenant),
        'paymentMethod': paymentMethod?.name,
        'meterPhotoUrl': meterPhotoUrl,
        'deductionReason': deductionReason,
        'exitStatementUrl': exitStatementUrl,
        'notes': notes,
      };

  TenantExitDetails copyWith({
    DateTime? exitedAt,
    double? advanceDeposit,
    double? finalMeterReading,
    double? pendingRent,
    double? pendingMaintenance,
    double? pendingEb,
    double? pendingOther,
    List<Deduction>? deductions,
    double? depositRefunded,
    double? amountDueFromTenant,
    double? amountPaidByTenant,
    PaymentMethod? paymentMethod,
    String? meterPhotoUrl,
    String? deductionReason,
    String? exitStatementUrl,
    String? notes,
  }) =>
      TenantExitDetails(
        exitedAt: exitedAt ?? this.exitedAt,
        advanceDeposit: advanceDeposit ?? this.advanceDeposit,
        finalMeterReading: finalMeterReading ?? this.finalMeterReading,
        pendingRent: pendingRent ?? this.pendingRent,
        pendingMaintenance: pendingMaintenance ?? this.pendingMaintenance,
        pendingEb: pendingEb ?? this.pendingEb,
        pendingOther: pendingOther ?? this.pendingOther,
        deductions: deductions ?? this.deductions,
        depositRefunded: depositRefunded ?? this.depositRefunded,
        amountDueFromTenant: amountDueFromTenant ?? this.amountDueFromTenant,
        amountPaidByTenant: amountPaidByTenant ?? this.amountPaidByTenant,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        meterPhotoUrl: meterPhotoUrl ?? this.meterPhotoUrl,
        deductionReason: deductionReason ?? this.deductionReason,
        exitStatementUrl: exitStatementUrl ?? this.exitStatementUrl,
        notes: notes ?? this.notes,
      );
}

/// A stored document associated with a tenancy (Rental Agreement, Aadhaar, Police Verification, etc.).
class TenantDocument {
  const TenantDocument({
    required this.id,
    required this.name,
    required this.url,
    required this.uploadedAt,
  });

  final String id;
  final String name;
  final String url;
  final DateTime uploadedAt;

  factory TenantDocument.fromJson(Map<String, dynamic> json) => TenantDocument(
        id: JsonUtils.toStr(json['id']),
        name: JsonUtils.toStr(json['name'], 'Document'),
        url: JsonUtils.toStr(json['url']),
        uploadedAt: JsonUtils.toDateTimeOr(json['uploadedAt'], DateTime.now()),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'url': url,
        'uploadedAt': JsonUtils.fromDateTime(uploadedAt),
      };
}

/// A tenant occupying (or having occupied) a property.
///
/// Exited tenants are never deleted — they are retained with
/// [exitDetails] populated so history and audit trails stay intact.
class Tenant {
  const Tenant({
    required this.tenantId,
    required this.propertyId,
    required this.ownerId,
    required this.name,
    required this.phone,
    this.email,
    this.idProofUrl,
    this.documents = const <TenantDocument>[],
    this.advanceDepositAmount = 0,
    this.rentOverride,
    this.maintenanceOverride,
    required this.leaseStartDate,
    this.leaseEndDate,
    this.status = TenantStatus.ACTIVE,
    this.exitDetails,
    required this.createdAt,
    required this.updatedAt,
  });

  final String tenantId;
  final String propertyId;

  /// Denormalised owner uid so `collectionGroup('tenants')` queries can be
  /// filtered (and secured) without reading every parent property.
  final String ownerId;

  final String name;
  final String phone;
  final String? email;
  final String? idProofUrl;
  final List<TenantDocument> documents;
  final double advanceDepositAmount;

  /// Optional per-tenant overrides; null means "use the property default".
  final double? rentOverride;
  final double? maintenanceOverride;

  final DateTime leaseStartDate;
  final DateTime? leaseEndDate;
  final TenantStatus status;
  final TenantExitDetails? exitDetails;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status == TenantStatus.ACTIVE;
  bool get isExited => status == TenantStatus.EXITED;
  bool get hasOverrides => rentOverride != null || maintenanceOverride != null;

  /// Effective rent for this tenant.
  double rentFor(double propertyBaseRent) => rentOverride ?? propertyBaseRent;

  double maintenanceFor(double propertyBaseMaintenance) =>
      maintenanceOverride ?? propertyBaseMaintenance;

  factory Tenant.fromJson(String tenantId, Map<String, dynamic> json) {
    final created = JsonUtils.toDateTimeOr(json['createdAt'], DateTime.now());
    final exitJson = JsonUtils.toNullableMap(json['exitDetails']);
    final idProof = JsonUtils.toNullableStr(json['idProofUrl']);
    final rawDocs = json['documents'];
    final docs = rawDocs is List
        ? rawDocs
            .whereType<Map>()
            .map((e) => TenantDocument.fromJson(
                  e.map((k, v) => MapEntry(k.toString(), v)),
                ))
            .toList()
        : <TenantDocument>[];
    if (idProof != null && !docs.any((d) => d.url == idProof)) {
      docs.insert(
        0,
        TenantDocument(
          id: 'id_proof',
          name: 'ID Proof',
          url: idProof,
          uploadedAt: created,
        ),
      );
    }
    return Tenant(
      tenantId: JsonUtils.toStr(json['tenantId'], tenantId),
      propertyId: JsonUtils.toStr(json['propertyId']),
      ownerId: JsonUtils.toStr(json['ownerId']),
      name: JsonUtils.toStr(json['name']),
      phone: JsonUtils.toStr(json['phone']),
      email: JsonUtils.toNullableStr(json['email']),
      idProofUrl: idProof,
      documents: docs,
      advanceDepositAmount: JsonUtils.toDouble(json['advanceDepositAmount']),
      rentOverride: json['rentOverride'] == null
          ? null
          : JsonUtils.toDouble(json['rentOverride']),
      maintenanceOverride: json['maintenanceOverride'] == null
          ? null
          : JsonUtils.toDouble(json['maintenanceOverride']),
      leaseStartDate:
          JsonUtils.toDateTimeOr(json['leaseStartDate'], created),
      leaseEndDate: JsonUtils.toDateTime(json['leaseEndDate']),
      status:
          enumFromName(TenantStatus.values, json['status'], TenantStatus.ACTIVE),
      exitDetails:
          exitJson == null ? null : TenantExitDetails.fromJson(exitJson),
      createdAt: created,
      updatedAt: JsonUtils.toDateTimeOr(json['updatedAt'], created),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tenantId': tenantId,
        'propertyId': propertyId,
        'ownerId': ownerId,
        'name': name,
        'phone': phone,
        'email': email,
        'idProofUrl': idProofUrl,
        'documents': documents.map((d) => d.toJson()).toList(),
        'advanceDepositAmount': JsonUtils.money(advanceDepositAmount),
        'rentOverride': rentOverride == null ? null : JsonUtils.money(rentOverride!),
        'maintenanceOverride': maintenanceOverride == null
            ? null
            : JsonUtils.money(maintenanceOverride!),
        'leaseStartDate': JsonUtils.fromDateTime(leaseStartDate),
        'leaseEndDate': JsonUtils.fromDateTime(leaseEndDate),
        'status': status.name,
        'exitDetails': exitDetails?.toJson(),
        'createdAt': JsonUtils.fromDateTime(createdAt),
        'updatedAt': JsonUtils.fromDateTime(updatedAt),
      };

  Tenant copyWith({
    String? name,
    String? phone,
    String? email,
    bool clearEmail = false,
    String? idProofUrl,
    bool clearIdProof = false,
    List<TenantDocument>? documents,
    double? advanceDepositAmount,
    double? rentOverride,
    bool clearRentOverride = false,
    double? maintenanceOverride,
    bool clearMaintenanceOverride = false,
    DateTime? leaseStartDate,
    DateTime? leaseEndDate,
    bool clearLeaseEndDate = false,
    TenantStatus? status,
    TenantExitDetails? exitDetails,
    DateTime? updatedAt,
  }) =>
      Tenant(
        tenantId: tenantId,
        propertyId: propertyId,
        ownerId: ownerId,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        email: clearEmail ? null : (email ?? this.email),
        idProofUrl: clearIdProof
            ? null
            : (idProofUrl ?? this.idProofUrl),
        documents: documents ?? this.documents,
        advanceDepositAmount: advanceDepositAmount ?? this.advanceDepositAmount,
        rentOverride: clearRentOverride
            ? null
            : (rentOverride ?? this.rentOverride),
        maintenanceOverride: clearMaintenanceOverride
            ? null
            : (maintenanceOverride ?? this.maintenanceOverride),
        leaseStartDate: leaseStartDate ?? this.leaseStartDate,
        leaseEndDate: clearLeaseEndDate
            ? null
            : (leaseEndDate ?? this.leaseEndDate),
        status: status ?? this.status,
        exitDetails: exitDetails ?? this.exitDetails,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  @override
  bool operator ==(Object other) =>
      other is Tenant && other.tenantId == tenantId && other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(tenantId, updatedAt);

  @override
  String toString() => 'Tenant($tenantId, $name, ${status.name})';
}
