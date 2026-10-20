import 'package:firebase_auth/firebase_auth.dart';

/// Single exception type surfaced to the presentation layer.
///
/// Repositories translate platform exceptions ([FirebaseException],
/// [FirestoreException], socket errors) into this type so that screens only
/// ever deal with a friendly [message] and an optional [code].
class AppException implements Exception {
  const AppException(this.message, {this.code, this.cause});

  final String message;
  final String? code;
  final Object? cause;

  factory AppException.from(Object error, [StackTrace? stackTrace]) {
    if (error is AppException) return error;

    if (error is FirebaseAuthException) {
      return AppException(_authMessage(error), code: error.code, cause: error);
    }
    if (error is FirebaseException) {
      return AppException(
        _firebaseMessage(error),
        code: error.code,
        cause: error,
      );
    }
    return AppException(
      'Something went wrong. Please try again.',
      cause: error,
    );
  }

  static String _authMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-phone-number':
        return 'That phone number looks invalid. Check the country code.';
      case 'invalid-verification-code':
        return 'The OTP you entered is incorrect.';
      case 'session-expired':
        return 'The OTP expired. Please request a new one.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and retry.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Please choose a stronger password.';
      case 'network-request-failed':
        return 'No internet connection. Check your network and retry.';
      case 'requires-recent-login':
        return 'Please sign in again to complete this action.';
      default:
        return error.message ?? 'Authentication failed.';
    }
  }

  static String _firebaseMessage(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'You do not have access to this data.';
      case 'unavailable':
        return 'You appear to be offline. Changes will sync automatically.';
      case 'deadline-exceeded':
        return 'The request timed out. Please try again.';
      case 'not-found':
        return 'That record no longer exists.';
      case 'already-exists':
        return 'That record already exists.';
      case 'failed-precondition':
        return 'A required Firestore index is still building. Try again shortly.';
      default:
        return error.message ?? 'A database error occurred.';
    }
  }

  @override
  String toString() => 'AppException($code): $message';
}

/// Convenience wrappers that convert any thrown object into [AppException].
extension FutureAppException<T> on Future<T> {
  Future<T> mapErrors() => catchError(
        (Object error, StackTrace stackTrace) =>
            throw AppException.from(error, stackTrace),
      );
}
