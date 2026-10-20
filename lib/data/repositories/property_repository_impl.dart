import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firestore_paths.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/models/property.dart';
import '../../domain/repositories/repositories.dart';
import 'cascade_deleter.dart';
import 'repository_guard.dart';

class FirestorePropertyRepository implements PropertyRepository {
  FirestorePropertyRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      _db.collection(FsPaths.propertiesCol(uid));

  DocumentReference<Map<String, dynamic>> _doc(String uid, String propertyId) =>
      _db.doc(FsPaths.property(uid, propertyId));

  @override
  Stream<List<Property>> watchProperties(
    String uid, {
    bool includeArchived = false,
  }) {
    Query<Map<String, dynamic>> query = _collection(uid);
    if (!includeArchived) {
      query = query.where('isArchived', isEqualTo: false);
    }
    return query
        .orderBy('propertyName')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Property.fromJson(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Future<Property?> getProperty(String uid, String propertyId) =>
      guardAsync(() async {
        final snapshot = await _doc(uid, propertyId).get();
        final data = snapshot.data();
        if (!snapshot.exists || data == null) return null;
        return Property.fromJson(propertyId, data);
      });

  @override
  Future<String> createProperty(String uid, Property property) =>
      guardAsync(() async {
        final reference = _collection(uid).doc();
        final payload = property.toJson()..['propertyId'] = reference.id;
        await reference.set(payload);
        return reference.id;
      });

  @override
  Future<void> updateProperty(String uid, Property property) => guardAsync(
        () => _doc(uid, property.propertyId).set(
          property.copyWith(updatedAt: DateTime.now()).toJson(),
          SetOptions(merge: true),
        ),
      );

  @override
  Future<void> setArchived(
    String uid,
    String propertyId,
    bool archived,
  ) =>
      guardAsync(() async {
        final snapshot = await _doc(uid, propertyId).get();
        if (!snapshot.exists) {
          throw const AppException('That property no longer exists.');
        }
        if (archived && snapshot.data()?['activeTenantId'] != null) {
          throw const AppException(
            'Exit the active tenant before archiving this property.',
          );
        }
        await _doc(uid, propertyId).update(<String, dynamic>{
          'isArchived': archived,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

  @override
  Future<void> deletePropertyCascade(String uid, String propertyId) =>
      guardAsync(() async {
        final existing = await _doc(uid, propertyId).get();
        if (existing.exists && existing.data()?['activeTenantId'] != null) {
          throw const AppException(
            'This property still has an active tenant. Exit the tenant first.',
          );
        }
        await CascadeDeleter(_db).deleteProperty(uid, propertyId);
      });
}
