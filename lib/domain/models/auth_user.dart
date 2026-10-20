/// Provider-agnostic snapshot of the signed-in identity.
///
/// Keeping this in the domain layer means no screen ever imports
/// `firebase_auth`.
class AuthUser {
  const AuthUser({
    required this.uid,
    this.phone,
    this.email,
    this.displayName,
    this.photoUrl,
    this.isAnonymous = false,
  });

  final String uid;
  final String? phone;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final bool isAnonymous;

  static const AuthUser empty =
      AuthUser(uid: '', isAnonymous: true);

  bool get isEmpty => uid.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.uid == uid &&
      other.phone == phone &&
      other.email == email &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(uid, phone, email, displayName);
}
