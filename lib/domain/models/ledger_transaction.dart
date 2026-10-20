import '../../core/utils/json_utils.dart';
import 'enums.dart';

/// Snapshot of the electricity sub-meter maths for a single EB bill.
class EbDetails {
  const EbDetails({
    required this.previousReading,
    required this.currentReading,
    required this.unitsConsumed,
    required this.unitRate,
    required this.amount,
    this.periodStart,
    this.periodEnd,
    this.meterPhotoUrl,
  });

  final double previousReading;
  final double currentReading;
  final double unitsConsumed;
  final double unitRate;
  final double amount;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final String? meterPhotoUrl;

  /// Core sub-meter calculation: `(current - previous) * rate`.
  factory EbDetails.calculate({
    required double previousReading,
    required double currentReading,
    required double unitRate,
    DateTime? periodStart,
    DateTime? periodEnd,
    String? meterPhotoUrl,
  }) {
    final units = (currentReading - previousReading).clamp(0.0, double.infinity);
    return EbDetails(
      previousReading: previousReading,
      currentReading: currentReading,
      unitsConsumed: units,
      unitRate: unitRate,
      amount: JsonUtils.money(units * unitRate),
      periodStart: periodStart,
      periodEnd: periodEnd,
      meterPhotoUrl: meterPhotoUrl,
    );
  }

  bool get isValid => currentReading >= previousReading;

  /// Alternative to [calculate] for landlords who copy the supplier's total
  /// straight off the electricity bill instead of doing the per-unit maths.
  ///
  /// The readings are still recorded so the units consumed stay on the ledger.
  /// [unitRate] is taken as given when supplied and otherwise derived from the
  /// total, which keeps the reported rate-per-unit meaningful either way.
  factory EbDetails.fromTotal({
    required double previousReading,
    required double currentReading,
    required double totalAmount,
    double? unitRate,
    DateTime? periodStart,
    DateTime? periodEnd,
    String? meterPhotoUrl,
  }) {
    final units = (currentReading - previousReading).clamp(0.0, double.infinity);
    return EbDetails(
      previousReading: previousReading,
      currentReading: currentReading,
      unitsConsumed: units,
      unitRate:
          unitRate ?? (units > 0 ? JsonUtils.money(totalAmount / units) : 0),
      amount: JsonUtils.money(totalAmount),
      periodStart: periodStart,
      periodEnd: periodEnd,
      meterPhotoUrl: meterPhotoUrl,
    );
  }

  factory EbDetails.fromJson(Map<String, dynamic> json) => EbDetails(
        previousReading: JsonUtils.toDouble(json['previousReading']),
        currentReading: JsonUtils.toDouble(json['currentReading']),
        unitsConsumed: JsonUtils.toDouble(json['unitsConsumed']),
        unitRate: JsonUtils.toDouble(json['unitRate']),
        amount: JsonUtils.toDouble(json['amount']),
        periodStart: JsonUtils.toDateTime(json['periodStart']),
        periodEnd: JsonUtils.toDateTime(json['periodEnd']),
        meterPhotoUrl: JsonUtils.toNullableStr(json['meterPhotoUrl']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'previousReading': previousReading,
        'currentReading': currentReading,
        'unitsConsumed': unitsConsumed,
        'unitRate': unitRate,
        'amount': JsonUtils.money(amount),
        'periodStart': JsonUtils.fromDateTime(periodStart),
        'periodEnd': JsonUtils.fromDateTime(periodEnd),
        'meterPhotoUrl': meterPhotoUrl,
      };
}

/// A ledger entry. Named `LedgerTransaction` (not `Transaction`) to avoid
/// colliding with `cloud_firestore`'s `Transaction` type.
class LedgerTransaction {
  const LedgerTransaction({
    required this.transactionId,
    required this.propertyId,
    required this.ownerId,
    this.tenantId,
    this.tenantName,
    required this.type,
    required this.category,
    required this.amount,
    this.paymentMethod = PaymentMethod.CASH,
    required this.billingPeriod,
    this.ebDetails,
    this.expenseCategory,
    this.meterPhotoUrl,
    this.notes,
    this.receiptUrl,
    required this.recordedAt,
    required this.createdBy,
    required this.createdAt,
  });

  final String transactionId;
  final String propertyId;

  /// Denormalised owner uid — enables `collectionGroup('transactions')`
  /// filtering and keeps security rules to a single field comparison.
  final String ownerId;

  final String? tenantId;
  final String? tenantName;
  final TransactionType type;
  final TransactionCategory category;
  final double amount;
  final PaymentMethod paymentMethod;

  /// `YYYY-MM` the payment belongs to (not necessarily when it was recorded).
  final String billingPeriod;

  final EbDetails? ebDetails;
  final ExpenseCategory? expenseCategory;
  final String? meterPhotoUrl;
  final String? notes;
  final String? receiptUrl;

  /// Business date of the entry — used for all reporting.
  final DateTime recordedAt;
  final String createdBy;
  final DateTime createdAt;

  bool get isIncome => category == TransactionCategory.INCOME;
  bool get isExpense => category == TransactionCategory.EXPENSE;
  double get signedAmount => isIncome ? amount : -amount;

  factory LedgerTransaction.fromJson(
    String transactionId,
    Map<String, dynamic> json,
  ) {
    final recorded =
        JsonUtils.toDateTimeOr(json['recordedAt'], DateTime.now());
    final type = enumFromName(
      TransactionType.values,
      json['type'],
      TransactionType.OTHER,
    );
    final ebJson = JsonUtils.toNullableMap(json['ebDetails']);
    return LedgerTransaction(
      transactionId: JsonUtils.toStr(json['transactionId'], transactionId),
      propertyId: JsonUtils.toStr(json['propertyId']),
      ownerId: JsonUtils.toStr(json['ownerId'], JsonUtils.toStr(json['createdBy'])),
      tenantId: JsonUtils.toNullableStr(json['tenantId']),
      tenantName: JsonUtils.toNullableStr(json['tenantName']),
      type: type,
      category: enumFromName(
        TransactionCategory.values,
        json['category'],
        type.defaultCategory,
      ),
      amount: JsonUtils.toDouble(json['amount']),
      paymentMethod: enumFromName(
        PaymentMethod.values,
        json['paymentMethod'],
        PaymentMethod.CASH,
      ),
      billingPeriod: JsonUtils.toStr(
        json['billingPeriod'],
        '${recorded.year.toString().padLeft(4, '0')}-'
            '${recorded.month.toString().padLeft(2, '0')}',
      ),
      ebDetails: ebJson == null ? null : EbDetails.fromJson(ebJson),
      expenseCategory: json['expenseCategory'] == null
          ? null
          : enumFromName(
              ExpenseCategory.values,
              json['expenseCategory'],
              ExpenseCategory.OTHER,
            ),
      meterPhotoUrl: JsonUtils.toNullableStr(json['meterPhotoUrl']) ??
          (ebJson == null ? null : JsonUtils.toNullableStr(ebJson['meterPhotoUrl'])),
      notes: JsonUtils.toNullableStr(json['notes']),
      receiptUrl: JsonUtils.toNullableStr(json['receiptUrl']),
      recordedAt: recorded,
      createdBy: JsonUtils.toStr(json['createdBy']),
      createdAt: JsonUtils.toDateTimeOr(json['createdAt'], recorded),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'transactionId': transactionId,
        'propertyId': propertyId,
        'ownerId': ownerId,
        'tenantId': tenantId,
        'tenantName': tenantName,
        'type': type.name,
        'category': category.name,
        'amount': JsonUtils.money(amount),
        'paymentMethod': paymentMethod.name,
        'billingPeriod': billingPeriod,
        'ebDetails': ebDetails?.toJson(),
        'expenseCategory': expenseCategory?.name,
        'meterPhotoUrl': meterPhotoUrl ?? ebDetails?.meterPhotoUrl,
        'notes': notes,
        'receiptUrl': receiptUrl,
        'recordedAt': JsonUtils.fromDateTime(recordedAt),
        'createdBy': createdBy,
        'createdAt': JsonUtils.fromDateTime(createdAt),
      };

  LedgerTransaction copyWith({
    String? tenantId,
    String? tenantName,
    TransactionType? type,
    TransactionCategory? category,
    double? amount,
    PaymentMethod? paymentMethod,
    String? billingPeriod,
    EbDetails? ebDetails,
    ExpenseCategory? expenseCategory,
    bool clearExpenseCategory = false,
    String? meterPhotoUrl,
    bool clearMeterPhotoUrl = false,
    String? notes,
    String? receiptUrl,
    DateTime? recordedAt,
  }) =>
      LedgerTransaction(
        transactionId: transactionId,
        propertyId: propertyId,
        ownerId: ownerId,
        tenantId: tenantId ?? this.tenantId,
        tenantName: tenantName ?? this.tenantName,
        type: type ?? this.type,
        category: category ?? this.category,
        amount: amount ?? this.amount,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        billingPeriod: billingPeriod ?? this.billingPeriod,
        ebDetails: ebDetails ?? this.ebDetails,
        expenseCategory: clearExpenseCategory
            ? null
            : (expenseCategory ?? this.expenseCategory),
        meterPhotoUrl: clearMeterPhotoUrl
            ? null
            : (meterPhotoUrl ?? this.meterPhotoUrl),
        notes: notes ?? this.notes,
        receiptUrl: receiptUrl ?? this.receiptUrl,
        recordedAt: recordedAt ?? this.recordedAt,
        createdBy: createdBy,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      other is LedgerTransaction && other.transactionId == transactionId;

  @override
  int get hashCode => transactionId.hashCode;

  @override
  String toString() =>
      'LedgerTransaction($transactionId, ${type.name}, $amount)';
}
