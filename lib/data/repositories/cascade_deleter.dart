import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/firestore_paths.dart';

/// Client-side replacement for the `deletePropertyCascade` and
/// `cascadeDeleteAccount` Cloud Functions.
///
/// Cloud Functions require the Blaze pricing plan, so the same recursive
/// delete runs on the device instead. Every document already lives under
/// `users/{uid}` and the security rules scope each write to its owner, so a
/// signed-in landlord is always allowed to remove their own data.
class CascadeDeleter {
  const CascadeDeleter(this._db);

  final FirebaseFirestore _db;

  /// Removes a property together with its `tenants` and `transactions`
  /// sub-collections.
  Future<void> deleteProperty(String uid, String propertyId) async {
    await _deleteCollection(FsPaths.tenantsCol(uid, propertyId));
    await _deleteCollection(FsPaths.transactionsCol(uid, propertyId));
    await _db.doc(FsPaths.property(uid, propertyId)).delete();
  }

  /// Wipes every document owned by [uid], ready for the auth record to be
  /// removed straight afterwards.
  Future<void> deleteUserData(String uid) async {
    final properties = await _db.collection(FsPaths.propertiesCol(uid)).get();
    for (final property in properties.docs) {
      await deleteProperty(uid, property.id);
    }
    await _deleteCollection(FsPaths.monthlyLedgersCol(uid));
    await _deleteCollection(FsPaths.notificationsCol(uid));
    await _deleteCollection(FsPaths.exportJobsCol(uid));
    await _db.doc(FsPaths.user(uid)).delete();
  }

  /// Empties a collection in chunks, looping until nothing is left.
  ///
  /// Firestore caps a batch at 500 writes, so each pass removes at most
  /// [AppConstants.batchChunkSize] documents.
  Future<void> _deleteCollection(String path) async {
    while (true) {
      final snapshot =
          await _db.collection(path).limit(AppConstants.batchChunkSize).get();
      if (snapshot.docs.isEmpty) return;

      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < AppConstants.batchChunkSize) return;
    }
  }
}
