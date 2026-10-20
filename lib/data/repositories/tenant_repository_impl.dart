import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firestore_paths.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/ledger_transaction.dart';
import '../../domain/models/property.dart';
import '../../domain/models/tenant.dart';
import '../../domain/repositories/repositories.dart';
import 'repository_guard.dart';

class FirestoreTenantRepository implements TenantRepository {
  FirestoreTenantRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _collection(
    String uid,
    String propertyId,
  ) =>
      _db.collection(FsPaths.tenantsCol(uid, propertyId));

  DocumentReference<Map<String, dynamic>> _doc(
    String uid,
    String propertyId,
    String tenantId,
  ) =>
      _db.doc(FsPaths.tenant(uid, propertyId, tenantId));

  List<Tenant> _map(QuerySnapshot<Map<String, dynamic>> snapshot) =>
      snapshot.docs
          .map((doc) => Tenant.fromJson(doc.id, doc.data()))
          .toList(growable: false);

  @override
  Stream<List<Tenant>> watchTenants(
    String uid,
    String propertyId, {
    TenantStatus? status,
  }) =>
      _collection(uid, propertyId)
          .orderBy('leaseStartDate', descending: true)
          .snapshots()
          .map((snapshot) {
        final tenants = _map(snapshot);
        if (status == null) return tenants;
        return tenants.where((t) => t.status == status).toList(growable: false);
      });

  Stream<List<Tenant>> _fallbackWatchAllTenants(
    String uid, {
    TenantStatus? status,
  }) async* {
    await for (final propSnap
        in _db.collection(FsPaths.propertiesCol(uid)).snapshots()) {
      final all = <Tenant>[];
      for (final propDoc in propSnap.docs) {
        try {
          final tSnap = await _collection(uid, propDoc.id).get();
          all.addAll(_map(tSnap));
        } catch (_) {}
      }
      all.sort((a, b) => b.leaseStartDate.compareTo(a.leaseStartDate));
      if (status == null) {
        yield all;
      } else {
        yield all.where((t) => t.status == status).toList(growable: false);
      }
    }
  }

  @override
  Stream<List<Tenant>> watchAllTenants(String uid, {TenantStatus? status}) {
    late final StreamController<List<Tenant>> controller;
    StreamSubscription<List<Tenant>>? cgSub;
    StreamSubscription<List<Tenant>>? fallbackSub;

    void startFallback() {
      cgSub?.cancel();
      cgSub = null;
      fallbackSub = _fallbackWatchAllTenants(uid, status: status).listen(
        (data) {
          if (!controller.isClosed) controller.add(data);
        },
        onError: (err) {
          if (!controller.isClosed) controller.addError(err);
        },
      );
    }

    controller = StreamController<List<Tenant>>.broadcast(
      onListen: () {
        try {
          cgSub = _db
              .collectionGroup(FsPaths.tenants)
              .where('ownerId', isEqualTo: uid)
              .snapshots()
              .map((snapshot) {
            final tenants = _map(snapshot)
              ..sort((a, b) => b.leaseStartDate.compareTo(a.leaseStartDate));
            if (status == null) return tenants;
            return tenants
                .where((t) => t.status == status)
                .toList(growable: false);
          }).listen(
            (data) {
              if (!controller.isClosed) controller.add(data);
            },
            onError: (_) => startFallback(),
          );
        } catch (_) {
          startFallback();
        }
      },
      onCancel: () async {
        await cgSub?.cancel();
        await fallbackSub?.cancel();
      },
    );

    return controller.stream;
  }

  @override
  Future<List<Tenant>> fetchAllTenants(String uid, {TenantStatus? status}) =>
      guardAsync(() async {
        try {
          final snapshot = await _db
              .collectionGroup(FsPaths.tenants)
              .where('ownerId', isEqualTo: uid)
              .get();
          final tenants = _map(snapshot)
            ..sort((a, b) => b.leaseStartDate.compareTo(a.leaseStartDate));
          if (status == null) return tenants;
          return tenants
              .where((t) => t.status == status)
              .toList(growable: false);
        } catch (_) {
          final propSnap =
              await _db.collection(FsPaths.propertiesCol(uid)).get();
          final all = <Tenant>[];
          for (final doc in propSnap.docs) {
            try {
              final tSnap = await _collection(uid, doc.id).get();
              all.addAll(_map(tSnap));
            } catch (_) {}
          }
          all.sort((a, b) => b.leaseStartDate.compareTo(a.leaseStartDate));
          if (status == null) return all;
          return all
              .where((t) => t.status == status)
              .toList(growable: false);
        }
      });

  @override
  Future<Tenant?> getTenant(
    String uid,
    String propertyId,
    String tenantId,
  ) =>
      guardAsync(() async {
        final snapshot = await _doc(uid, propertyId, tenantId).get();
        final data = snapshot.data();
        if (!snapshot.exists || data == null) return null;
        return Tenant.fromJson(tenantId, data);
      });

  @override
  Future<String> onboardTenant(
    String uid,
    Tenant tenant, {
    LedgerTransaction? advanceTransaction,
  }) =>
      guardAsync(() async {
        final tenantRef = _collection(uid, tenant.propertyId).doc();
        final propertyRef = _db.doc(FsPaths.property(uid, tenant.propertyId));
        final transactionRef = advanceTransaction == null
            ? null
            : _db
                .collection(FsPaths.transactionsCol(uid, tenant.propertyId))
                .doc();

        await _db.runTransaction((transaction) async {
          // All reads must happen before any write.
          final propertySnapshot = await transaction.get(propertyRef);
          if (!propertySnapshot.exists) {
            throw const AppException('That property no longer exists.');
          }
          final property =
              Property.fromJson(tenant.propertyId, propertySnapshot.data()!);
          if (property.activeTenantId != null) {
            throw const AppException(
              'This property is already occupied. Exit the current tenant first.',
            );
          }

          final payload = tenant.toJson()
            ..['tenantId'] = tenantRef.id
            ..['ownerId'] = uid
            ..['propertyId'] = tenant.propertyId;
          transaction.set(tenantRef, payload);
          transaction.update(propertyRef, <String, dynamic>{
            'currentStatus': PropertyStatus.OCCUPIED.name,
            'activeTenantId': tenantRef.id,
            'activeTenantName': tenant.name,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          if (transactionRef != null && advanceTransaction != null) {
            final txnPayload = advanceTransaction.toJson()
              ..['transactionId'] = transactionRef.id
              ..['ownerId'] = uid
              ..['propertyId'] = tenant.propertyId
              ..['tenantId'] = tenantRef.id
              ..['tenantName'] = tenant.name;
            transaction.set(transactionRef, txnPayload);
          }
        });

        return tenantRef.id;
      });

  @override
  Future<void> updateTenant(String uid, Tenant tenant) => guardAsync(
        () async {
          final tenantRef = _doc(uid, tenant.propertyId, tenant.tenantId);
          final propertyRef = _db.doc(FsPaths.property(uid, tenant.propertyId));

          await _db.runTransaction((transaction) async {
            final propertySnapshot = await transaction.get(propertyRef);

            transaction.set(
              tenantRef,
              tenant.copyWith(updatedAt: DateTime.now()).toJson(),
              SetOptions(merge: true),
            );

            if (propertySnapshot.exists) {
              final activeTenantId = propertySnapshot.data()?['activeTenantId'];
              if (activeTenantId == tenant.tenantId) {
                transaction.update(propertyRef, <String, dynamic>{
                  'activeTenantName': tenant.name,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
              }
            }
          });
        },
      );

  @override
  Future<void> settleExit({
    required String uid,
    required Property property,
    required Tenant tenant,
    required TenantExitDetails details,
  }) =>
      guardAsync(() async {
        final tenantRef = _doc(uid, property.propertyId, tenant.tenantId);
        final propertyRef = _db.doc(FsPaths.property(uid, property.propertyId));
        final refundRef = details.depositRefunded > 0
            ? _db
                .collection(FsPaths.transactionsCol(uid, property.propertyId))
                .doc()
            : null;
        final paymentRef = details.amountPaidByTenant > 0
            ? _db
                .collection(FsPaths.transactionsCol(uid, property.propertyId))
                .doc()
            : null;

        await _db.runTransaction((transaction) async {
          final tenantSnapshot = await transaction.get(tenantRef);
          if (!tenantSnapshot.exists) {
            throw const AppException('That tenant record no longer exists.');
          }

          transaction.update(tenantRef, <String, dynamic>{
            'status': TenantStatus.EXITED.name,
            'exitDetails': details.toJson(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          final propertyPatch = <String, dynamic>{
            'currentStatus': PropertyStatus.VACANT.name,
            'activeTenantId': null,
            'activeTenantName': null,
            'updatedAt': FieldValue.serverTimestamp(),
          };
          if (details.finalMeterReading > 0 &&
              property.electricityBillingType !=
                  ElectricityBillingType.DIRECT_EB) {
            // Carry the handover reading forward so the next tenant starts
            // from a clean baseline.
            propertyPatch['currentEbMeterReading'] = details.finalMeterReading;
          }
          transaction.update(propertyRef, propertyPatch);

          if (refundRef != null) {
            final refund = LedgerTransaction(
              transactionId: refundRef.id,
              propertyId: property.propertyId,
              ownerId: uid,
              tenantId: tenant.tenantId,
              tenantName: tenant.name,
              type: TransactionType.ADVANCE_REFUND,
              category: TransactionCategory.EXPENSE,
              amount: details.depositRefunded,
              paymentMethod: details.paymentMethod ?? PaymentMethod.UPI,
              billingPeriod: _periodKey(details.exitedAt),
              notes: 'Security deposit refund on exit settlement',
              recordedAt: details.exitedAt,
              createdBy: uid,
              createdAt: DateTime.now(),
            );
            transaction.set(refundRef, refund.toJson());
          }

          if (paymentRef != null) {
            final payment = LedgerTransaction(
              transactionId: paymentRef.id,
              propertyId: property.propertyId,
              ownerId: uid,
              tenantId: tenant.tenantId,
              tenantName: tenant.name,
              type: TransactionType.RENT_PAYMENT,
              category: TransactionCategory.INCOME,
              amount: details.amountPaidByTenant,
              paymentMethod: details.paymentMethod ?? PaymentMethod.UPI,
              billingPeriod: _periodKey(details.exitedAt),
              notes: 'Exit dues settlement paid by tenant',
              recordedAt: details.exitedAt,
              createdBy: uid,
              createdAt: DateTime.now(),
            );
            transaction.set(paymentRef, payment.toJson());
          }
        });
      });

  @override
  Future<void> recordPostExitSettlement({
    required String uid,
    required Tenant tenant,
    required double amountPaid,
    required PaymentMethod paymentMethod,
    String? notes,
  }) =>
      guardAsync(() async {
        final exit = tenant.exitDetails;
        if (exit == null) {
          throw const AppException('Tenant has no exit settlement records.');
        }

        final tenantRef = _db
            .collection('users')
            .doc(uid)
            .collection('properties')
            .doc(tenant.propertyId)
            .collection('tenants')
            .doc(tenant.tenantId);

        final paymentRef = _db
            .collection('users')
            .doc(uid)
            .collection('properties')
            .doc(tenant.propertyId)
            .collection('transactions')
            .doc();

        final remainingDue = math.max(0.0, exit.amountDueFromTenant - amountPaid);
        final totalPaid = exit.amountPaidByTenant + amountPaid;
        final updatedExit = exit.copyWith(
          amountDueFromTenant: remainingDue,
          amountPaidByTenant: totalPaid,
        );

        final now = DateTime.now();
        final payment = LedgerTransaction(
          transactionId: paymentRef.id,
          propertyId: tenant.propertyId,
          ownerId: uid,
          tenantId: tenant.tenantId,
          tenantName: tenant.name,
          type: TransactionType.RENT_PAYMENT,
          category: TransactionCategory.INCOME,
          amount: amountPaid,
          paymentMethod: paymentMethod,
          billingPeriod: _periodKey(now),
          notes: notes?.isNotEmpty == true
              ? notes
              : 'Post-exit settlement payment received from tenant',
          recordedAt: now,
          createdBy: uid,
          createdAt: now,
        );

        await _db.runTransaction((transaction) async {
          transaction.update(tenantRef, <String, dynamic>{
            'exitDetails': updatedExit.toJson(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          transaction.set(paymentRef, payment.toJson());
        });
      });

  static String _periodKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}';
}
