import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/formatters.dart';
import '../domain/models/enums.dart';
import '../domain/models/ledger_transaction.dart';
import '../domain/models/monthly_ledger.dart';
import '../domain/models/report.dart';
import '../domain/services/ledger_calculator.dart';
import 'app_providers.dart';
import 'auth_providers.dart';
import 'property_providers.dart';
import 'tenant_providers.dart';

/// Collection-group stream of every transaction the user owns.
///
/// Backed by the `ownerId` denormalised field so a single listener can power
/// the dashboard, the reports screen and the tenant history screen.
final allTransactionsProvider = StreamProvider<List<LedgerTransaction>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Stream<List<LedgerTransaction>>.value(const <LedgerTransaction>[]);
  }
  return ref.watch(transactionRepositoryProvider).watchAll(uid);
});

/// Transactions of a single property, newest first.
final propertyTransactionsProvider =
    StreamProvider.family<List<LedgerTransaction>, String>((ref, propertyId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Stream<List<LedgerTransaction>>.value(const <LedgerTransaction>[]);
  }
  return ref
      .watch(transactionRepositoryProvider)
      .watchForProperty(uid, propertyId);
});

/// Transactions of one tenant, derived from [allTransactionsProvider] so the
/// property detail screen never opens a second Firestore listener.
final tenantTransactionsProvider =
    Provider.family<List<LedgerTransaction>, String>((ref, tenantId) {
  final all =
      ref.watch(allTransactionsProvider).valueOrNull ??
          const <LedgerTransaction>[];
  return all
      .where((txn) => txn.tenantId == tenantId)
      .toList(growable: false)
    ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
});

// ----------------------------------------------------------------- reporting

/// Filter state shared by the reports screen and the exports.
final ledgerFilterProvider =
    NotifierProvider<LedgerFilterNotifier, LedgerFilter>(
  LedgerFilterNotifier.new,
);

class LedgerFilterNotifier extends Notifier<LedgerFilter> {
  @override
  LedgerFilter build() => LedgerFilter.thisMonth();

  void setRange(DateTime from, DateTime to) =>
      state = state.copyWith(from: from, to: to);

  void setProperty(String? propertyId) => state = propertyId == null
      ? state.clearProperty()
      : state.copyWith(propertyId: propertyId);

  void setTypes(Set<TransactionType> types) =>
      state = state.copyWith(types: types);

  void setCategory(TransactionCategory? category) => state = category == null
      ? state.clearCategory()
      : state.copyWith(category: category);

  void setPaymentMethod(PaymentMethod? method) =>
      state = state.copyWith(paymentMethod: method);

  void setSearch(String search) => state = state.copyWith(search: search);

  void reset() => state = LedgerFilter.thisMonth();
}

/// Every transaction matching the active filter, newest first.
final filteredTransactionsProvider = Provider<List<LedgerTransaction>>((ref) {
  final filter = ref.watch(ledgerFilterProvider);
  final all =
      ref.watch(allTransactionsProvider).valueOrNull ??
          const <LedgerTransaction>[];
  return all.where(filter.matches).toList(growable: false)
    ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
});

/// The immutable bundle handed to [ReportExporter]s.
final reportBundleProvider = Provider<ReportBundle>((ref) {
  final filter = ref.watch(ledgerFilterProvider);
  final properties =
      ref.watch(propertiesProvider).valueOrNull ?? const [];
  return LedgerCalculator.buildReport(
    transactions: ref.watch(filteredTransactionsProvider),
    filter: filter,
    properties: properties,
  );
});

// ------------------------------------------------------------ monthly ledger

/// Most recent monthly ledger documents, newest first.
final recentLedgersProvider = StreamProvider<List<MonthlyLedger>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream<List<MonthlyLedger>>.value(const []);
  return ref.watch(ledgerRepositoryProvider).watchRecent(uid);
});

/// A single `YYYY-MM` ledger, recomputed client-side when the server
/// document has not landed yet (offline / cold start).
final monthlyLedgerProvider =
    Provider.family<MonthlyLedger, String>((ref, period) {
  final ledgers = ref.watch(recentLedgersProvider).valueOrNull ?? const [];
  for (final ledger in ledgers) {
    if (ledger.period == period) return ledger;
  }
  final properties =
      ref.watch(propertiesProvider).valueOrNull ?? const [];
  final tenants = ref.watch(allTenantsProvider).valueOrNull ?? const [];
  final transactions =
      ref.watch(allTransactionsProvider).valueOrNull ?? const [];
  final month = Formatters.parsePeriodKey(period) ?? DateTime.now();
  return LedgerCalculator.rollUp(
    properties: properties,
    tenants: tenants,
    transactions: transactions,
    month: month,
  );
});

// -------------------------------------------------------------- dashboard

/// Everything the dashboard renders, computed in a single pass.
final dashboardMetricsProvider = Provider<DashboardMetrics>((ref) {
  final properties =
      ref.watch(propertiesProvider).valueOrNull ?? const [];
  final tenants = ref.watch(allTenantsProvider).valueOrNull ?? const [];
  final transactions =
      ref.watch(allTransactionsProvider).valueOrNull ?? const [];
  final ledgers = ref.watch(recentLedgersProvider).valueOrNull ?? const [];
  return LedgerCalculator.buildDashboard(
    properties: properties,
    tenants: tenants,
    transactions: transactions,
    ledgers: ledgers,
    now: DateTime.now(),
  );
});

/// True while every source feeding the dashboard is still loading its first
/// value — lets the UI show skeletons instead of zeros.
final dashboardLoadingProvider = Provider<bool>((ref) {
  return ref.watch(propertiesProvider).isLoading ||
      ref.watch(allTenantsProvider).isLoading ||
      ref.watch(allTransactionsProvider).isLoading;
});

// ---------------------------------------------------------------- controller

/// Writes for ledger transactions.
class TransactionController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// Adds a transaction; returns the new id (or null on failure).
  Future<String?> add(LedgerTransaction transaction) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return null;
    state = const AsyncLoading();
    try {
      final id = await ref
          .read(transactionRepositoryProvider)
          .addTransaction(uid, transaction);
      state = const AsyncData<void>(null);
      return id;
    } catch (error, stackTrace) {
      state = AsyncError<void>(error, stackTrace);
      return null;
    }
  }

  Future<bool> saveTransaction(LedgerTransaction transaction) => _run(
        () => ref
            .read(transactionRepositoryProvider)
            .updateTransaction(ref.read(currentUidProvider)!, transaction),
      );

  Future<bool> delete(LedgerTransaction transaction) => _run(
        () => ref
            .read(transactionRepositoryProvider)
            .deleteTransaction(ref.read(currentUidProvider)!, transaction),
      );

  Future<bool> _run(Future<void> Function() action) async {
    if (ref.read(currentUidProvider) == null) return false;
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData<void>(null);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError<void>(error, stackTrace);
      return false;
    }
  }
}

final transactionControllerProvider =
    AsyncNotifierProvider<TransactionController, void>(
  TransactionController.new,
);

/// Recomputes a month's ledger server-side.
class LedgerController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<bool> rebuild(String period) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return false;
    state = const AsyncLoading();
    try {
      await ref.read(ledgerRepositoryProvider).rebuild(uid, period);
      state = const AsyncData<void>(null);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError<void>(error, stackTrace);
      return false;
    }
  }
}

final ledgerControllerProvider =
    AsyncNotifierProvider<LedgerController, void>(LedgerController.new);
