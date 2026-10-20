import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/models/auth_user.dart';
import '../../domain/repositories/repositories.dart';
import 'cascade_deleter.dart';
import 'repository_guard.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    fb.FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? fb.FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance,
        _googleSignIn = googleSignIn ?? _buildGoogleSignIn();

  final fb.FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final GoogleSignIn _googleSignIn;

  /// Android only returns an `idToken` — which is what Firebase Auth needs —
  /// when a server client ID is known. The Google Services Gradle plugin bakes
  /// one in from `google-services.json`, so this is only required when that
  /// file carries no web client:
  ///
  /// ```sh
  /// flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=…apps.googleusercontent.com
  /// ```
  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  static GoogleSignIn _buildGoogleSignIn() => GoogleSignIn(
        scopes: const <String>['email', 'profile'],
        serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
      );

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<AuthUser?> authStateChanges() =>
      _auth.authStateChanges().map(_map);

  @override
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String message) onError,
    void Function(String verificationId, String smsCode)? onAutoVerified,
    int? resendToken,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        forceResendingToken: resendToken,
        verificationCompleted: (credential) {
          final id = credential.verificationId;
          final code = credential.smsCode;
          if (onAutoVerified != null && id != null && code != null) {
            onAutoVerified(id, code);
          }
        },
        verificationFailed: (error) => onError(AppException.from(error).message),
        codeSent: onCodeSent,
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (error, stackTrace) {
      throw AppException.from(error, stackTrace);
    }
  }

  @override
  Future<AuthUser> signInWithSmsCode({
    required String verificationId,
    required String smsCode,
    String? phoneNumber,
  }) =>
      guardAsync(() async {
        final credential = fb.PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: smsCode,
        );
        final result = await _auth.signInWithCredential(credential);
        final user = result.user;
        if (user == null) {
          throw const AppException('Verification succeeded but no user returned.');
        }
        return _map(user)!;
      });

  @override
  Future<AuthUser> signInWithGoogle() => guardAsync(() async {
        final GoogleSignInAccount? account;
        try {
          account = await _googleSignIn.signIn();
        } on PlatformException catch (error) {
          // Everything Google Identity reports surfaces as a PlatformException
          // whose message embeds a Play-services status code, so translate it
          // into something the landlord can act on.
          throw AppException(
            _googleMessage(error),
            code: error.code,
            cause: error,
          );
        }
        if (account == null) {
          throw const AppException(
            'Google sign-in was cancelled. Tap "Continue with Google" again '
            'and pick an account.',
          );
        }

        final auth = await account.authentication;
        if (auth.idToken == null && auth.accessToken == null) {
          throw const AppException(
            'Google returned no token for this account. Register this build\'s '
            'SHA-1 fingerprint in the Firebase console and re-download '
            'google-services.json.',
          );
        }

        final credential = fb.GoogleAuthProvider.credential(
          idToken: auth.idToken,
          accessToken: auth.accessToken,
        );
        final fb.UserCredential result;
        try {
          result = await _auth.signInWithCredential(credential);
        } on fb.FirebaseAuthException catch (error) {
          throw AppException(
            _googleAuthMessage(error),
            code: error.code,
            cause: error,
          );
        }
        final user = result.user;
        if (user == null) {
          throw const AppException('Google sign-in failed. Please retry.');
        }
        return _map(user)!;
      });

  /// Turns a Play-services/Google Identity status into an actionable message.
  static String _googleMessage(PlatformException error) {
    final details = '${error.code} ${error.message ?? ''}';
    if (details.contains('10:') || details.contains('DEVELOPER_ERROR')) {
      return 'Google sign-in is not configured for this build. Add the app\'s '
          'SHA-1 fingerprint to the Android app in the Firebase console, then '
          're-download google-services.json and rebuild.';
    }
    if (details.contains('12502') ||
        details.contains('12500') ||
        details.contains('12501') ||
        details.contains('SIGN_IN_CANCELLED')) {
      return 'Google sign-in was cancelled.';
    }
    if (details.contains('7:') || details.contains('NETWORK_ERROR')) {
      return 'No internet connection. Check your network and retry.';
    }
    return 'Google sign-in failed. ${error.message ?? ''}'.trim();
  }

  /// Firebase's own verdict once the Google token reaches it.
  static String _googleAuthMessage(fb.FirebaseAuthException error) {
    switch (error.code) {
      case 'account-exists-with-different-credential':
        return 'This email already has an account signed up with a password. '
            'Sign in with the email option instead.';
      case 'operation-not-allowed':
        return 'Google sign-in is not enabled for this Firebase project. '
            'Enable the Google provider in the console.';
      case 'internal-error':
      case 'invalid-credential':
        return 'Google could not verify this account. Check that the SHA-1 '
            'fingerprint is registered, then try again.';
      default:
        return AppException.from(error).message;
    }
  }

  @override
  Future<AuthUser> signInWithEmail({
    required String email,
    required String password,
  }) =>
      guardAsync(() async {
        final result = await _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        return _map(result.user)!;
      });

  @override
  Future<AuthUser> signUpWithEmail({
    required String email,
    required String password,
    String? name,
  }) =>
      guardAsync(() async {
        final result = await _auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        final user = result.user;
        if (user == null) {
          throw const AppException('Could not create the account.');
        }
        final trimmed = name?.trim();
        if (trimmed != null && trimmed.isNotEmpty) {
          await user.updateDisplayName(trimmed);
          await user.reload();
        }
        return _map(_auth.currentUser ?? user)!;
      });

  @override
  Future<void> sendPasswordReset(String email) => guardAsync(
        () => _auth.sendPasswordResetEmail(email: email.trim()),
      );

  @override
  Future<void> updateDisplayName(String name) => guardAsync(() async {
        final user = _auth.currentUser;
        if (user == null) throw const AppException('You are not signed in.');
        await user.updateDisplayName(name.trim());
        await user.reload();
      });

  @override
  Future<void> signOut() => guardAsync(() async {
        try {
          await _googleSignIn.signOut();
        } catch (_) {
          // Google sign-out is best-effort; Firebase sign-out always runs.
        }
        await _auth.signOut();
      });

  @override
  Future<void> deleteAccount() => guardAsync(() async {
        final user = _auth.currentUser;
        if (user == null) throw const AppException('You are not signed in.');
        // Everything we own is wiped while we are still authenticated, then
        // the auth record itself is removed.
        await CascadeDeleter(_db).deleteUserData(user.uid);
        await user.delete();
      });

  AuthUser? _map(fb.User? user) {
    if (user == null) return null;
    return AuthUser(
      uid: user.uid,
      phone: user.phoneNumber,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
      isAnonymous: user.isAnonymous,
    );
  }

  /// Normalises a locally typed number to E.164 using the app default.
  static String normalisePhone(String input) {
    final trimmed = input.trim().replaceAll(RegExp(r'[\s-()]'), '');
    if (trimmed.startsWith('+')) return trimmed;
    if (trimmed.length == 10) {
      return '${AppConstants.defaultCountryCode}$trimmed';
    }
    return '${AppConstants.defaultCountryCode}$trimmed';
  }
}
