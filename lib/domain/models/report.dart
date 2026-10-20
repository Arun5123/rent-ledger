import 'enums.dart';
import 'ledger_transaction.dart';
import 'property.dart';
import 'tenant.dart';

/// Criteria used by the Reports screen and every export.
class LedgerFilter {
  const LedgerFilter({
    required this.from,
    required this.to,
    this.propertyId,
    this.tenantId,
    this.types = const <TransactionType>{},
    this.category,
    this.paymentMethod,
    this.search = '',
  });

  final DateTime from;
  final DateTime to;

  /// null means "all properties".
  final String? propertyId;
  final String? tenantId;
  final Set<TransactionType> types;
  final TransactionCategory? category;
  final PaymentMethod? paymentMethod;
  final String search;

  factory LedgerFilter.thisMonth() {
    final now = DateTime.now();
    return LedgerFilter(
      from: DateTime(now.year, now.month),
      to: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
    );
  }

  factory LedgerFilter.financialYear(int startYear) {
    // Indian financial year runs April → March.
    return LedgerFilter(
      from: DateTime(startYear, 4),
      to: DateTime(startYear + 1, 3, 31, 23, 59, 59),
    );
  }

  LedgerFilter copyWith({
    DateTime? from,
    DateTime? to,
    String? propertyId,
    String? tenantId,
    Set<TransactionType>? types,
    TransactionCategory? category,
    PaymentMethod? paymentMethod,
    String? search,
  }) =>
      LedgerFilter(
        from: from ?? this.from,
        to: to ?? this.to,
        propertyId: propertyId ?? this.propertyId,
        tenantId: tenantId ?? this.tenantId,
        types: types ?? this.types,
        category: category ?? this.category,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        search: search ?? this.search,
      );

  LedgerFilter clearProperty() => LedgerFilter(
        from: from,
        to: to,
        tenantId: tenantId,
        types: types,
        category: category,
        paymentMethod: paymentMethod,
        search: search,
      );

  LedgerFilter clearCategory() => LedgerFilter(
        from: from,
        to: to,
        propertyId: propertyId,
        tenantId: tenantId,
        types: types,
        paymentMethod: paymentMethod,
        search: search,
      );

  bool matches(LedgerTransaction txn) {
    if (propertyId != null && txn.propertyId != propertyId) return false;
    if (tenantId != null && txn.tenantId != tenantId) return false;
    if (types.isNotEmpty && !types.contains(txn.type)) return false;
    if (category != null && txn.category != category) return false;
    if (paymentMethod != null && txn.paymentMethod != paymentMethod) return false;
    final date = txn.recordedAt;
    if (date.isBefore(from) || date.isAfter(to)) return false;
    if (search.trim().isNotEmpty) {
      final needle = search.trim().toLowerCase();
      final haystack = [
        txn.tenantName ?? '',
        txn.notes ?? '',
        txn.type.label,
        txn.transactionId,
      ].join(' ').toLowerCase();
      if (!haystack.contains(needle)) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is LedgerFilter &&
      other.from == from &&
      other.to == to &&
      other.propertyId == propertyId &&
      other.tenantId == tenantId &&
      other.category == category &&
      other.paymentMethod == paymentMethod &&
      other.search == search &&
      _sameSet(other.types, types);

  @override
  int get hashCode => Object.hash(
        from,
        to,
        propertyId,
        tenantId,
        category,
        paymentMethod,
        search,
        Object.hashAllUnordered(types),
      );

  static bool _sameSet(Set<TransactionType> a, Set<TransactionType> b) =>
      a.length == b.length && a.containsAll(b);
}

/// Everything the Reports screen needs for one filter, in one immutable object.
class ReportBundle {
  const ReportBundle({
    required this.filter,
    required this.transactions,
    required this.generatedAt,
    this.propertyNames = const <String, String>{},
  });

  final LedgerFilter filter;
  final List<LedgerTransaction> transactions;
  final Map<String, String> propertyNames;
  final DateTime generatedAt;

  double get totalIncome => transactions
      .where((t) => t.isIncome)
      .fold<double>(0, (sum, t) => sum + t.amount);

  double get totalExpenses => transactions
      .where((t) => t.isExpense)
      .fold<double>(0, (sum, t) => sum + t.amount);

  double get netIncome => totalIncome - totalExpenses;

  double get totalRent => _sumOf(TransactionType.RENT_PAYMENT);
  double get totalMaintenance => _sumOf(TransactionType.MAINTENANCE_FEE);
  double get totalEb => _sumOf(TransactionType.EB_BILL);
  double get totalWater => _sumOf(TransactionType.WATER_BILL);
  double get totalAdvanceReceived => _sumOf(TransactionType.ADVANCE_RECEIVED);
  double get totalAdvanceRefund => _sumOf(TransactionType.ADVANCE_REFUND);
  double get totalPropertyExpense => _sumOf(TransactionType.PROPERTY_EXPENSE);

  double get totalUnitsBilled => transactions
      .where((t) => t.ebDetails != null)
      .fold<double>(0, (sum, t) => sum + (t.ebDetails?.unitsConsumed ?? 0));

  bool get isEmpty => transactions.isEmpty;

  double _sumOf(TransactionType type) => transactions
      .where((t) => t.type == type)
      .fold<double>(0, (sum, t) => sum + t.amount);

  String propertyNameFor(String propertyId) =>
      propertyNames[propertyId] ?? 'Property';
}

/// Aggregated numbers powering the dashboard.
class DashboardMetrics {
  const DashboardMetrics({
    required this.totalProperties,
    required this.occupiedCount,
    required this.vacantCount,
    required this.maintenanceCount,
    required this.activeTenantCount,
    required this.incomeThisMonth,
    required this.expensesThisMonth,
    required this.rentCollectedThisMonth,
    required this.pendingDues,
    required this.pendingTenantCount,
    required this.lastMonthIncome,
    required this.trend,
    required this.duesByTenant,
  });

  final int totalProperties;
  final int occupiedCount;
  final int vacantCount;
  final int maintenanceCount;
  final int activeTenantCount;
  final double incomeThisMonth;
  final double expensesThisMonth;
  final double rentCollectedThisMonth;
  final double pendingDues;
  final int pendingTenantCount;
  final double lastMonthIncome;

  /// Last six months of income, oldest first.
  final List<TrendPoint> trend;
  final List<TenantDue> duesByTenant;

  double get netThisMonth => incomeThisMonth - expensesThisMonth;

  double get occupancyRate =>
      totalProperties == 0 ? 0 : (occupiedCount / totalProperties) * 100;

  /// Month-over-month income change in percent (0 when there is no baseline).
  double get incomeDeltaPercent {
    if (lastMonthIncome <= 0) return incomeThisMonth > 0 ? 100 : 0;
    return ((incomeThisMonth - lastMonthIncome) / lastMonthIncome) * 100;
  }

  static const DashboardMetrics empty = DashboardMetrics(
    totalProperties: 0,
    occupiedCount: 0,
    vacantCount: 0,
    maintenanceCount: 0,
    activeTenantCount: 0,
    incomeThisMonth: 0,
    expensesThisMonth: 0,
    rentCollectedThisMonth: 0,
    pendingDues: 0,
    pendingTenantCount: 0,
    lastMonthIncome: 0,
    trend: <TrendPoint>[],
    duesByTenant: <TenantDue>[],
  );
}

class TrendPoint {
  const TrendPoint({
    required this.period,
    required this.income,
    required this.expenses,
  });

  final String period;
  final double income;
  final double expenses;

  double get net => income - expenses;
}

/// One tenant that still owes money for the current month.
class TenantDue {
  const TenantDue({
    required this.propertyId,
    required this.propertyName,
    required this.tenantId,
    required this.tenantName,
    required this.dueAmount,
    required this.expectedAmount,
    required this.paidAmount,
    this.phone,
  });

  final String propertyId;
  final String propertyName;
  final String tenantId;
  final String tenantName;
  final double dueAmount;
  final double expectedAmount;
  final double paidAmount;
  final String? phone;

  double get progress => expectedAmount <= 0 ? 0 : paidAmount / expectedAmount;
}

/// Read-only snapshot used by the exit wizard and the past-tenants screen.
class TenantHistoryEntry {
  const TenantHistoryEntry({
    required this.tenant,
    required this.property,
    this.lifetimePaid = 0,
    this.transactionCount = 0,
  });

  final Tenant tenant;
  final Property property;
  final double lifetimePaid;
  final int transactionCount;
}
