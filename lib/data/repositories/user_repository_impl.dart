import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firestore_paths.dart';
import '../../domain/models/auth_user.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/repositories/repositories.dart';
import 'repository_guard.dart';

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.doc(FsPaths.user(uid));

  @override
  Stream<UserProfile?> watchProfile(String uid) => _doc(uid).snapshots().map(
        (snapshot) {
          final data = snapshot.data();
          if (!snapshot.exists || data == null) return null;
          return UserProfile.fromJson(uid, data);
        },
      );

  @override
  Future<UserProfile?> getProfile(String uid) => guardAsync(() async {
        final snapshot = await _doc(uid).get();
        final data = snapshot.data();
        if (!snapshot.exists || data == null) return null;
        return UserProfile.fromJson(uid, data);
      });

  @override
  Future<UserProfile> ensureProfile(AuthUser user) => guardAsync(() async {
        final reference = _doc(user.uid);
        final snapshot = await reference.get();
        final data = snapshot.data();
        if (snapshot.exists && data != null) {
          final existing = UserProfile.fromJson(user.uid, data);
          // Keep the auth-provided name/phone fresh when they were missing.
          final needsPatch =
              (existing.phone.isEmpty && (user.phone?.isNotEmpty ?? false)) ||
                  (existing.email == null && (user.email?.isNotEmpty ?? false));
          if (!needsPatch) return existing;
          final patched = existing.copyWith(
            phone: existing.phone.isEmpty ? user.phone : existing.phone,
            email: existing.email ?? user.email,
          );
          await reference.set(patched.toJson(), SetOptions(merge: true));
          return patched;
        }
        final profile = UserProfile.initial(
          uid: user.uid,
          name: user.displayName,
          phone: user.phone,
          email: user.email,
        );
        await reference.set(profile.toJson());
        return profile;
      });

  @override
  Future<void> saveProfile(UserProfile profile) => guardAsync(
        () => _doc(profile.uid).set(
          profile.copyWith(updatedAt: DateTime.now()).toJson(),
          SetOptions(merge: true),
        ),
      );
}
