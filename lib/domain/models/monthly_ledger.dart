import '../../core/utils/json_utils.dart';

/// Per-property slice of a month's ledger (denormalised for fast dashboards).
class PropertyLedgerSummary {
  const PropertyLedgerSummary({
    required this.propertyId,
    required this.propertyName,
    this.rentCollected = 0,
    this.maintenanceCollected = 0,
    this.ebCollected = 0,
    this.otherIncome = 0,
    this.expenses = 0,
    this.transactionCount = 0,
  });

  final String propertyId;
  final String propertyName;
  final double rentCollected;
  final double maintenanceCollected;
  final double ebCollected;
  final double otherIncome;
  final double expenses;
  final int transactionCount;

  double get totalIncome =>
      rentCollected + maintenanceCollected + ebCollected + otherIncome;
  double get netIncome => totalIncome - expenses;

  factory PropertyLedgerSummary.fromJson(Map<String, dynamic> json) =>
      PropertyLedgerSummary(
        propertyId: JsonUtils.toStr(json['propertyId']),
        propertyName: JsonUtils.toStr(json['propertyName']),
        rentCollected: JsonUtils.toDouble(json['rentCollected']),
        maintenanceCollected: JsonUtils.toDouble(json['maintenanceCollected']),
        ebCollected: JsonUtils.toDouble(json['ebCollected']),
        otherIncome: JsonUtils.toDouble(json['otherIncome']),
        expenses: JsonUtils.toDouble(json['expenses']),
        transactionCount: JsonUtils.toInt(json['transactionCount']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'propertyId': propertyId,
        'propertyName': propertyName,
        'rentCollected': JsonUtils.money(rentCollected),
        'maintenanceCollected': JsonUtils.money(maintenanceCollected),
        'ebCollected': JsonUtils.money(ebCollected),
        'otherIncome': JsonUtils.money(otherIncome),
        'expenses': JsonUtils.money(expenses),
        'transactionCount': transactionCount,
      };
}

/// Aggregated roll-up for one calendar month, written by the
/// `rebuildMonthlyLedger` Cloud Function and optimistically by the client.
class MonthlyLedger {
  const MonthlyLedger({
    required this.period,
    required this.year,
    required this.month,
    this.totalRentCollected = 0,
    this.totalMaintenanceCollected = 0,
    this.totalEbCollected = 0,
    this.totalOtherIncome = 0,
    this.totalExpensesIncurred = 0,
    this.pendingDues = 0,
    this.pendingTenantCount = 0,
    this.propertyBreakdown = const <String, PropertyLedgerSummary>{},
    this.transactionCount = 0,
    required this.updatedAt,
  });

  /// `YYYY-MM`
  final String period;
  final int year;
  final int month;

  final double totalRentCollected;
  final double totalMaintenanceCollected;
  final double totalEbCollected;
  final double totalOtherIncome;
  final double totalExpensesIncurred;

  /// Rent + maintenance expected but not yet collected for the month.
  final double pendingDues;
  final int pendingTenantCount;

  final Map<String, PropertyLedgerSummary> propertyBreakdown;
  final int transactionCount;
  final DateTime updatedAt;

  double get totalIncome =>
      totalRentCollected +
      totalMaintenanceCollected +
      totalEbCollected +
      totalOtherIncome;

  double get netOperatingIncome => totalIncome - totalExpensesIncurred;

  /// Percentage of billed income actually collected (0–100).
  double get collectionRate {
    final billed = totalIncome + pendingDues;
    if (billed <= 0) return 0;
    return (totalIncome / billed) * 100;
  }

  factory MonthlyLedger.empty(String period, DateTime updatedAt) {
    final parts = period.split('-');
    return MonthlyLedger(
      period: period,
      year: int.tryParse(parts.first) ?? updatedAt.year,
      month: parts.length > 1 ? int.tryParse(parts[1]) ?? updatedAt.month : 1,
      updatedAt: updatedAt,
    );
  }

  factory MonthlyLedger.fromJson(String period, Map<String, dynamic> json) {
    final breakdown = JsonUtils.toMap(json['propertyBreakdown']);
    return MonthlyLedger(
      period: JsonUtils.toStr(json['period'], period),
      year: JsonUtils.toInt(json['year']),
      month: JsonUtils.toInt(json['month']),
      totalRentCollected: JsonUtils.toDouble(json['totalRentCollected']),
      totalMaintenanceCollected:
          JsonUtils.toDouble(json['totalMaintenanceCollected']),
      totalEbCollected: JsonUtils.toDouble(json['totalEbCollected']),
      totalOtherIncome: JsonUtils.toDouble(json['totalOtherIncome']),
      totalExpensesIncurred: JsonUtils.toDouble(json['totalExpensesIncurred']),
      pendingDues: JsonUtils.toDouble(json['pendingDues']),
      pendingTenantCount: JsonUtils.toInt(json['pendingTenantCount']),
      propertyBreakdown: breakdown.map(
        (key, value) => MapEntry(
          key,
          PropertyLedgerSummary.fromJson(JsonUtils.toMap(value)),
        ),
      ),
      transactionCount: JsonUtils.toInt(json['transactionCount']),
      updatedAt: JsonUtils.toDateTimeOr(json['updatedAt'], DateTime.now()),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'period': period,
        'year': year,
        'month': month,
        'totalRentCollected': JsonUtils.money(totalRentCollected),
        'totalMaintenanceCollected':
            JsonUtils.money(totalMaintenanceCollected),
        'totalEbCollected': JsonUtils.money(totalEbCollected),
        'totalOtherIncome': JsonUtils.money(totalOtherIncome),
        'totalExpensesIncurred': JsonUtils.money(totalExpensesIncurred),
        'pendingDues': JsonUtils.money(pendingDues),
        'pendingTenantCount': pendingTenantCount,
        'propertyBreakdown': propertyBreakdown.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'transactionCount': transactionCount,
        'updatedAt': JsonUtils.fromDateTime(updatedAt),
      };
}
