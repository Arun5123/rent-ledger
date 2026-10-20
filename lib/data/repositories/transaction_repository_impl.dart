import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/firestore_paths.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/ledger_transaction.dart';
import '../../domain/models/report.dart';
import '../../domain/repositories/repositories.dart';
import 'repository_guard.dart';

class FirestoreTransactionRepository implements TransactionRepository {
  FirestoreTransactionRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _collection(
    String uid,
    String propertyId,
  ) =>
      _db.collection(FsPaths.transactionsCol(uid, propertyId));

  List<LedgerTransaction> _map(QuerySnapshot<Map<String, dynamic>> snapshot) =>
      snapshot.docs
          .map((doc) => LedgerTransaction.fromJson(doc.id, doc.data()))
          .toList(growable: false);

  @override
  Stream<List<LedgerTransaction>> watchForProperty(
    String uid,
    String propertyId, {
    int limit = 200,
  }) =>
      _collection(uid, propertyId)
          .orderBy('recordedAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(_map);

  Stream<List<LedgerTransaction>> _fallbackWatchAll(
    String uid, {
    int limit = 500,
  }) async* {
    await for (final propSnap
        in _db.collection(FsPaths.propertiesCol(uid)).snapshots()) {
      final all = <LedgerTransaction>[];
      for (final propDoc in propSnap.docs) {
        try {
          final txSnap = await _collection(uid, propDoc.id).get();
          all.addAll(_map(txSnap));
        } catch (_) {}
      }
      all.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      if (all.length > limit) {
        yield all.sublist(0, limit);
      } else {
        yield all;
      }
    }
  }

  @override
  Stream<List<LedgerTransaction>> watchAll(String uid, {int limit = 500}) {
    late final StreamController<List<LedgerTransaction>> controller;
    StreamSubscription<List<LedgerTransaction>>? cgSub;
    StreamSubscription<List<LedgerTransaction>>? fallbackSub;

    void startFallback() {
      cgSub?.cancel();
      cgSub = null;
      fallbackSub = _fallbackWatchAll(uid, limit: limit).listen(
        (data) {
          if (!controller.isClosed) controller.add(data);
        },
        onError: (err) {
          if (!controller.isClosed) controller.addError(err);
        },
      );
    }

    controller = StreamController<List<LedgerTransaction>>.broadcast(
      onListen: () {
        try {
          cgSub = _db
              .collectionGroup(FsPaths.transactions)
              .where('ownerId', isEqualTo: uid)
              .snapshots()
              .map((snapshot) {
            final list = _map(snapshot)
              ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
            if (list.length > limit) {
              return list.sublist(0, limit);
            }
            return list;
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
  Future<List<LedgerTransaction>> query(String uid, LedgerFilter filter) =>
      guardAsync(() async {
        Query<Map<String, dynamic>> query = _db
            .collectionGroup(FsPaths.transactions)
            .where('ownerId', isEqualTo: uid)
            .where(
              'recordedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(filter.from),
            )
            .where(
              'recordedAt',
              isLessThanOrEqualTo: Timestamp.fromDate(filter.to),
            );

        if (filter.propertyId != null) {
          query = query.where('propertyId', isEqualTo: filter.propertyId);
        }
        if (filter.tenantId != null) {
          query = query.where('tenantId', isEqualTo: filter.tenantId);
        }

        final snapshot = await query
            .orderBy('recordedAt', descending: true)
            .limit(AppConstants.batchChunkSize * 5)
            .get();

        // Type / category / search filters are applied in memory so the number
        // of required composite indexes stays low.
        return _map(snapshot).where(filter.matches).toList(growable: false);
      });

  @override
  Future<LedgerTransaction?> getTransaction(
    String uid,
    String propertyId,
    String transactionId,
  ) =>
      guardAsync(() async {
        final snapshot = await _doc(uid, propertyId, transactionId).get();
        final data = snapshot.data();
        if (!snapshot.exists || data == null) return null;
        return LedgerTransaction.fromJson(transactionId, data);
      });

  @override
  Future<String> addTransaction(
    String uid,
    LedgerTransaction transaction,
  ) =>
      guardAsync(() async {
        final reference = _collection(uid, transaction.propertyId).doc();
        final payload = transaction.toJson()
          ..['transactionId'] = reference.id
          ..['ownerId'] = uid
          ..['propertyId'] = transaction.propertyId;

        final batch = _db.batch();
        batch.set(reference, payload);

        // Keep the property's sub-meter baseline in sync so the next EB bill
        // always starts from the latest reading.
        final reading = transaction.ebDetails?.currentReading;
        if (reading != null &&
            transaction.type == TransactionType.EB_BILL &&
            reading > 0) {
          batch.update(
            _db.doc(FsPaths.property(uid, transaction.propertyId)),
            <String, dynamic>{
              'currentEbMeterReading': reading,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
        }
        await batch.commit();
        return reference.id;
      });

  @override
  Future<void> updateTransaction(
    String uid,
    LedgerTransaction transaction,
  ) =>
      guardAsync(
        () => _doc(uid, transaction.propertyId, transaction.transactionId)
            .set(transaction.toJson(), SetOptions(merge: true)),
      );

  @override
  Future<void> deleteTransaction(
    String uid,
    LedgerTransaction transaction,
  ) =>
      guardAsync(
        () => _doc(uid, transaction.propertyId, transaction.transactionId)
            .delete(),
      );

  DocumentReference<Map<String, dynamic>> _doc(
    String uid,
    String propertyId,
    String transactionId,
  ) =>
      _db.doc(FsPaths.transaction(uid, propertyId, transactionId));
}
