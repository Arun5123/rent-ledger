import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firestore_paths.dart';
import '../../domain/models/ledger_transaction.dart';
import '../../domain/models/monthly_ledger.dart';
import '../../domain/models/property.dart';
import '../../domain/models/tenant.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/ledger_calculator.dart';
import 'repository_guard.dart';

class FirestoreLedgerRepository implements LedgerRepository {
  FirestoreLedgerRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Stream<MonthlyLedger> watchLedger(String uid, String period) =>
      _db.doc(FsPaths.monthlyLedger(uid, period)).snapshots().map((snapshot) {
        final data = snapshot.data();
        if (!snapshot.exists || data == null) {
          return MonthlyLedger.empty(period, DateTime.now());
        }
        return MonthlyLedger.fromJson(period, data);
      });

  @override
  Stream<List<MonthlyLedger>> watchRecent(String uid, {int months = 6}) =>
      _db
          .collection(FsPaths.monthlyLedgersCol(uid))
          .orderBy('period', descending: true)
          .limit(months)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => MonthlyLedger.fromJson(doc.id, doc.data()))
                .toList(growable: false),
          );

  @override
  Future<void> rebuild(String uid, String period) => guardAsync(() async {
        final properties = await _db.collection(FsPaths.propertiesCol(uid)).get();
        final tenants = await _db
            .collectionGroup(FsPaths.tenants)
            .where('ownerId', isEqualTo: uid)
            .get();
        final transactions = await _db
            .collectionGroup(FsPaths.transactions)
            .where('ownerId', isEqualTo: uid)
            .get();

        final ledger = LedgerCalculator.rollUp(
          properties: properties.docs
              .map((doc) => Property.fromJson(doc.id, doc.data()))
              .toList(growable: false),
          tenants: tenants.docs
              .map((doc) => Tenant.fromJson(doc.id, doc.data()))
              .toList(growable: false),
          transactions: transactions.docs
              .map((doc) => LedgerTransaction.fromJson(doc.id, doc.data()))
              .toList(growable: false),
          month: _monthOf(period),
        );

        await _db.doc(FsPaths.monthlyLedger(uid, period)).set(ledger.toJson());
      });

  /// Turns a `YYYY-MM` billing period into the first day of that month.
  static DateTime _monthOf(String period) {
    final parts = period.split('-');
    final year = int.tryParse(parts.first) ?? DateTime.now().year;
    final month = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
    return DateTime(year, month);
  }
}
