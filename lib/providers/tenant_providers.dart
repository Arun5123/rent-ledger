import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/enums.dart';
import '../domain/models/ledger_transaction.dart';
import '../domain/models/property.dart';
import '../domain/models/tenant.dart';
import 'app_providers.dart';
import 'auth_providers.dart';
import 'property_providers.dart';
import 'transaction_providers.dart';

/// Collection-group stream of every tenant the user owns (active + exited),
/// which powers the dashboard and the past-tenants history.
final allTenantsProvider = StreamProvider<List<Tenant>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream<List<Tenant>>.value(const <Tenant>[]);
  return ref.watch(tenantRepositoryProvider).watchAllTenants(uid);
});

final activeTenantsProvider = Provider<List<Tenant>>(
  (ref) => (ref.watch(allTenantsProvider).valueOrNull ?? const <Tenant>[])
      .where((t) => t.isActive)
      .toList(growable: false),
);

final exitedTenantsProvider = Provider<List<Tenant>>(
  (ref) => (ref.watch(allTenantsProvider).valueOrNull ?? const <Tenant>[])
      .where((t) => t.isExited)
      .toList(growable: false),
);

/// Tenants of a single property (active first, then history).
final propertyTenantsProvider =
    StreamProvider.family<List<Tenant>, String>((ref, propertyId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream<List<Tenant>>.value(const <Tenant>[]);
  return ref.watch(tenantRepositoryProvider).watchTenants(uid, propertyId);
});

/// The tenant currently occupying a property, if any.
final activeTenantForPropertyProvider =
    Provider.family<Tenant?, String>((ref, propertyId) {
  final property = ref.watch(propertyProvider(propertyId));
  final activeId = property?.activeTenantId;

  // 1. Try property-scoped tenants subcollection
  final tenants = ref.watch(propertyTenantsProvider(propertyId)).valueOrNull;
  if (tenants != null && tenants.isNotEmpty) {
    for (final tenant in tenants) {
      if (tenant.isActive) return tenant;
    }
    if (activeId != null) {
      for (final tenant in tenants) {
        if (tenant.tenantId == activeId) return tenant;
      }
    }
  }

  // 2. Fall back to allTenantsProvider (already warm from dashboard)
  final all = ref.watch(allTenantsProvider).valueOrNull;
  if (all != null && all.isNotEmpty) {
    for (final tenant in all) {
      if (tenant.propertyId == propertyId && tenant.isActive) return tenant;
    }
    if (activeId != null) {
      for (final tenant in all) {
        if (tenant.propertyId == propertyId && tenant.tenantId == activeId) {
          return tenant;
        }
      }
    }
  }

  return null;
});

/// Record key for tenant lookups: `(propertyId, tenantId)`.
typedef TenantKey = (String propertyId, String tenantId);

final tenantProvider = Provider.family<Tenant?, TenantKey>((ref, key) {
  final tenants =
      ref.watch(propertyTenantsProvider(key.$1)).valueOrNull ?? const <Tenant>[];
  for (final tenant in tenants) {
    if (tenant.tenantId == key.$2) return tenant;
  }
  final all = ref.watch(allTenantsProvider).valueOrNull ?? const <Tenant>[];
  for (final tenant in all) {
    if (tenant.tenantId == key.$2) return tenant;
  }
  return null;
});

/// Tenant + property + lifetime totals for the history screen.
class TenantHistory {
  const TenantHistory({
    required this.tenant,
    required this.property,
    required this.lifetimePaid,
    required this.transactionCount,
  });

  final Tenant tenant;
  final Property? property;
  final double lifetimePaid;
  final int transactionCount;
}

final tenantHistoryProvider = Provider<List<TenantHistory>>((ref) {
  final tenants = ref.watch(exitedTenantsProvider);
  final properties =
      ref.watch(propertiesProvider).valueOrNull ?? const <Property>[];
  final transactions =
      ref.watch(allTransactionsProvider).valueOrNull ??
          const <LedgerTransaction>[];

  return tenants.map((tenant) {
    Property? property;
    for (final candidate in properties) {
      if (candidate.propertyId == tenant.propertyId) {
        property = candidate;
        break;
      }
    }
    var paid = 0.0;
    var count = 0;
    for (final txn in transactions) {
      if (txn.tenantId != tenant.tenantId) continue;
      count++;
      if (txn.isIncome) paid += txn.amount;
    }
    return TenantHistory(
      tenant: tenant,
      property: property,
      lifetimePaid: paid,
      transactionCount: count,
    );
  }).toList(growable: false);
});

/// Tenant lifecycle writes.
class TenantController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// Onboards a tenant, records the advance and occupies the property.
  Future<String?> onboard({
    required Tenant tenant,
    LedgerTransaction? advanceTransaction,
  }) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return null;
    state = const AsyncLoading();
    try {
      final id = await ref.read(tenantRepositoryProvider).onboardTenant(
            uid,
            tenant,
            advanceTransaction: advanceTransaction,
          );
      state = const AsyncData<void>(null);
      return id;
    } catch (error, stackTrace) {
      state = AsyncError<void>(error, stackTrace);
      return null;
    }
  }

  Future<bool> saveTenant(Tenant tenant) async {
    final ok = await _run(
      () => ref
          .read(tenantRepositoryProvider)
          .updateTenant(ref.read(currentUidProvider)!, tenant),
    );
    if (ok) {
      ref.invalidate(propertyTenantsProvider(tenant.propertyId));
      ref.invalidate(allTenantsProvider);
      ref.invalidate(propertiesProvider);
    }
    return ok;
  }

  /// Completes the exit wizard: settlement snapshot, property freed,
  /// refund recorded — atomically.
  Future<bool> settleExit({
    required Property property,
    required Tenant tenant,
    required TenantExitDetails details,
  }) =>
      _run(
        () => ref.read(tenantRepositoryProvider).settleExit(
              uid: ref.read(currentUidProvider)!,
              property: property,
              tenant: tenant,
              details: details,
            ),
      );

  /// Records a post-exit settlement payment received from an exited tenant.
  Future<bool> recordPostExitSettlement({
    required Tenant tenant,
    required double amountPaid,
    required PaymentMethod paymentMethod,
    String? notes,
  }) async {
    final ok = await _run(
      () => ref.read(tenantRepositoryProvider).recordPostExitSettlement(
            uid: ref.read(currentUidProvider)!,
            tenant: tenant,
            amountPaid: amountPaid,
            paymentMethod: paymentMethod,
            notes: notes,
          ),
    );
    if (ok) {
      ref.invalidate(propertyTenantsProvider(tenant.propertyId));
      ref.invalidate(allTenantsProvider);
      ref.invalidate(propertyTransactionsProvider(tenant.propertyId));
      ref.invalidate(allTransactionsProvider);
    }
    return ok;
  }

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

final tenantControllerProvider =
    AsyncNotifierProvider<TenantController, void>(TenantController.new);
