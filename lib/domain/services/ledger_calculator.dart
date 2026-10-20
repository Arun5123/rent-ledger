import 'dart:math' as math;

import '../../core/utils/formatters.dart';
import '../../core/utils/json_utils.dart';
import '../models/enums.dart';
import '../models/ledger_transaction.dart';
import '../models/monthly_ledger.dart';
import '../models/property.dart';
import '../models/report.dart';
import '../models/tenant.dart';

/// Pure aggregation logic behind the dashboard and the reports screen.
///
/// Kept free of I/O so it can be unit tested with plain Dart objects.
abstract final class LedgerCalculator {
  /// Single pass that produces every KPI the dashboard renders.
  static DashboardMetrics buildDashboard({
    required List<Property> properties,
    required List<Tenant> tenants,
    required List<LedgerTransaction> transactions,
    required DateTime now,
    List<MonthlyLedger> ledgers = const <MonthlyLedger>[],
  }) {
    final visible = properties.where((p) => !p.isArchived).toList();
    final monthStart = Formatters.monthStart(now);
    final monthEnd = Formatters.monthEnd(now);
    final lastMonthStart = DateTime(now.year, now.month - 1);
    final lastMonthEnd = DateTime(now.year, now.month, 0, 23, 59, 59);

    var income = 0.0;
    var expenses = 0.0;
    var rentCollected = 0.0;

    for (final txn in transactions) {
      final at = txn.recordedAt;
      if (at.isBefore(monthStart) || at.isAfter(monthEnd)) continue;
      if (txn.isIncome) {
        income += txn.amount;
        if (txn.type == TransactionType.RENT_PAYMENT) rentCollected += txn.amount;
      } else {
        expenses += txn.amount;
      }
    }

    var lastMonthIncome = 0.0;
    for (final txn in transactions) {
      if (!txn.isIncome) continue;
      final at = txn.recordedAt;
      if (at.isBefore(lastMonthStart) || at.isAfter(lastMonthEnd)) continue;
      lastMonthIncome += txn.amount;
    }

    final activeTenants =
        tenants.where((t) => t.isActive).toList(growable: false);
    final dues = <TenantDue>[];
    for (final tenant in activeTenants) {
      final property = visible.firstWhere(
        (p) => p.propertyId == tenant.propertyId,
        orElse: () => Property(
          propertyId: tenant.propertyId,
          propertyName: 'Property',
          address: '',
          city: '',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final due = dueForTenant(
        tenant: tenant,
        property: property,
        transactions: transactions,
        month: now,
      );
      if (due != null && due.dueAmount > 0.5) dues.add(due);
    }
    dues.sort((a, b) => b.dueAmount.compareTo(a.dueAmount));

    final occupied = visible
        .where((p) => p.currentStatus == PropertyStatus.OCCUPIED)
        .length;
    final vacant =
        visible.where((p) => p.currentStatus == PropertyStatus.VACANT).length;
    final maintenance = visible
        .where((p) => p.currentStatus == PropertyStatus.UNDER_MAINTENANCE)
        .length;

    return DashboardMetrics(
      totalProperties: visible.length,
      occupiedCount: occupied,
      vacantCount: vacant,
      maintenanceCount: maintenance,
      activeTenantCount: activeTenants.length,
      incomeThisMonth: JsonUtils.money(income),
      expensesThisMonth: JsonUtils.money(expenses),
      rentCollectedThisMonth: JsonUtils.money(rentCollected),
      pendingDues: JsonUtils.money(
        dues.fold<double>(0, (sum, d) => sum + d.dueAmount),
      ),
      pendingTenantCount: dues.length,
      lastMonthIncome: JsonUtils.money(lastMonthIncome),
      trend: ledgers.isNotEmpty
          ? trendFromLedgers(ledgers)
          : trendFromTransactions(transactions, now),
      duesByTenant: dues,
    );
  }

  /// Expected-vs-paid position for one tenant in one month.
  static TenantDue? dueForTenant({
    required Tenant tenant,
    required Property property,
    required List<LedgerTransaction> transactions,
    required DateTime month,
    int? monthsElapsed,
  }) {
    final start = Formatters.monthStart(month);
    final end = Formatters.monthEnd(month);
    final periodKey = Formatters.periodKey(month);

    if (!tenant.isActive) return null;
    if (tenant.leaseStartDate.isAfter(end)) return null;

    final cycles = monthsElapsed ?? 1;

    final rent = tenant.rentFor(property.baseRent);
    final maintenance = tenant.maintenanceFor(property.baseMaintenance);
    final fixedEb = property.electricityBillingType == ElectricityBillingType.FIXED
        ? property.fixedEbAmount
        : 0.0;

    var ebRaised = 0.0;
    var paid = 0.0;
    for (final txn in transactions) {
      if (txn.tenantId != tenant.tenantId) continue;
      final at = txn.recordedAt;
      final matchesPeriod = (txn.billingPeriod.isNotEmpty && txn.billingPeriod == periodKey) ||
          (!at.isBefore(start) && !at.isAfter(end));
      if (!matchesPeriod) continue;
      if (txn.type == TransactionType.EB_BILL && txn.isIncome) {
        ebRaised += txn.amount;
      }
      if (txn.type.isRecurringIncome && txn.isIncome) paid += txn.amount;
    }

    final expectedTotal = _monthsRent(rent, maintenance, cycles) +
        math.max(ebRaised, fixedEb) * (ebRaised > 0 ? 1 : cycles);
    final due = math.max(0.0, expectedTotal - paid);

    return TenantDue(
      propertyId: property.propertyId,
      propertyName: property.propertyName,
      tenantId: tenant.tenantId,
      tenantName: tenant.name,
      dueAmount: JsonUtils.money(due),
      expectedAmount: JsonUtils.money(expectedTotal),
      paidAmount: JsonUtils.money(paid),
      phone: tenant.phone.isEmpty ? null : tenant.phone,
    );
  }

  static double _monthsRent(double rent, double maintenance, int cycles) =>
      (rent + maintenance) * cycles;

  static List<TrendPoint> trendFromLedgers(List<MonthlyLedger> ledgers) {
    final sorted = [...ledgers]..sort((a, b) => a.period.compareTo(b.period));
    return sorted
        .map(
          (l) => TrendPoint(
            period: l.period,
            income: l.totalIncome,
            expenses: l.totalExpensesIncurred,
          ),
        )
        .toList(growable: false);
  }

  /// Fallback trend built from raw transactions (used before the monthly
  /// ledger documents exist).
  static List<TrendPoint> trendFromTransactions(
    List<LedgerTransaction> transactions,
    DateTime now, {
    int months = 6,
  }) {
    final points = <TrendPoint>[];
    for (var i = months - 1; i >= 0; i--) {
      final ref = DateTime(now.year, now.month - i);
      final start = Formatters.monthStart(ref);
      final end = Formatters.monthEnd(ref);
      var income = 0.0;
      var expense = 0.0;
      for (final txn in transactions) {
        final at = txn.recordedAt;
        if (at.isBefore(start) || at.isAfter(end)) continue;
        if (txn.isIncome) {
          income += txn.amount;
        } else {
          expense += txn.amount;
        }
      }
      points.add(
        TrendPoint(
          period: Formatters.periodKey(start),
          income: JsonUtils.money(income),
          expenses: JsonUtils.money(expense),
        ),
      );
    }
    return points;
  }

  /// Builds the immutable bundle consumed by the reports screen + exporters.
  static ReportBundle buildReport({
    required List<LedgerTransaction> transactions,
    required LedgerFilter filter,
    List<Property> properties = const <Property>[],
  }) {
    final matched = transactions.where(filter.matches).toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final names = <String, String>{
      for (final property in properties)
        property.propertyId: property.propertyName,
    };
    return ReportBundle(
      filter: filter,
      transactions: matched,
      propertyNames: names,
      generatedAt: DateTime.now(),
    );
  }

  /// Rolls the current month into a [MonthlyLedger] shape (client-side
  /// optimistic aggregation; the Cloud Function is the source of truth).
  static MonthlyLedger rollUp({
    required List<Property> properties,
    required List<Tenant> tenants,
    required List<LedgerTransaction> transactions,
    required DateTime month,
  }) {
    final start = Formatters.monthStart(month);
    final end = Formatters.monthEnd(month);
    final period = Formatters.periodKey(start);

    var rent = 0.0;
    var maintenance = 0.0;
    var eb = 0.0;
    var other = 0.0;
    var expenses = 0.0;
    var count = 0;
    final breakdown = <String, PropertyLedgerSummary>{};
    final names = {
      for (final p in properties) p.propertyId: p.propertyName,
    };

    for (final txn in transactions) {
      final at = txn.recordedAt;
      if (at.isBefore(start) || at.isAfter(end)) continue;
      count++;
      final summary = breakdown.putIfAbsent(
        txn.propertyId,
        () => PropertyLedgerSummary(
          propertyId: txn.propertyId,
          propertyName: names[txn.propertyId] ?? 'Property',
        ),
      );

      var r = summary.rentCollected;
      var m = summary.maintenanceCollected;
      var e = summary.ebCollected;
      var o = summary.otherIncome;
      var x = summary.expenses;

      switch (txn.type) {
        case TransactionType.RENT_PAYMENT:
          r += txn.amount;
        case TransactionType.MAINTENANCE_FEE:
          m += txn.amount;
        case TransactionType.EB_BILL:
          e += txn.amount;
        case TransactionType.ADVANCE_REFUND:
        case TransactionType.PROPERTY_EXPENSE:
          x += txn.amount;
        default:
          o += txn.amount;
      }

      breakdown[txn.propertyId] = PropertyLedgerSummary(
        propertyId: summary.propertyId,
        propertyName: summary.propertyName,
        rentCollected: r,
        maintenanceCollected: m,
        ebCollected: e,
        otherIncome: o,
        expenses: x,
        transactionCount: summary.transactionCount + 1,
      );

      if (txn.isIncome) {
        switch (txn.type) {
          case TransactionType.RENT_PAYMENT:
            rent += txn.amount;
          case TransactionType.MAINTENANCE_FEE:
            maintenance += txn.amount;
          case TransactionType.EB_BILL:
            eb += txn.amount;
          default:
            other += txn.amount;
        }
      } else {
        expenses += txn.amount;
      }
    }

    final dashboard = buildDashboard(
      properties: properties,
      tenants: tenants,
      transactions: transactions,
      now: month,
    );

    return MonthlyLedger(
      period: period,
      year: start.year,
      month: start.month,
      totalRentCollected: JsonUtils.money(rent),
      totalMaintenanceCollected: JsonUtils.money(maintenance),
      totalEbCollected: JsonUtils.money(eb),
      totalOtherIncome: JsonUtils.money(other),
      totalExpensesIncurred: JsonUtils.money(expenses),
      pendingDues: dashboard.pendingDues,
      pendingTenantCount: dashboard.pendingTenantCount,
      propertyBreakdown: breakdown,
      transactionCount: count,
      updatedAt: DateTime.now(),
    );
  }
}
