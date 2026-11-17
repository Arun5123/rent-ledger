import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

/// Single exception type surfaced to the presentation layer.
///
/// Repositories translate platform exceptions ([FirebaseException],
/// [PlatformException], socket errors) into this type so that screens only
/// ever deal with a friendly [message] and an optional [code].
class AppException implements Exception {
  const AppException(this.message, {this.code, this.cause});

  final String message;
  final String? code;
  final Object? cause;

  /// Translates any error object into a clean, human-readable user message.
  /// Never leaks stack traces, class names, or technical codes to the UI.
  static String userMessageOf(
    Object? error, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (error == null) return fallback;
    if (error is AppException) {
      return sanitizeMessage(error.message, fallback: fallback);
    }
    return AppException.from(error).message;
  }

  /// Sanitizes raw error strings by stripping prefixes like `[firebase_auth/...]`,
  /// `Exception: `, `PlatformException(...)`, and technical exception dumps.
  static String sanitizeMessage(
    String? raw, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (raw == null) return fallback;
    var text = raw.trim();
    if (text.isEmpty) return fallback;

    // Strip "Exception: " prefix
    if (text.startsWith('Exception:')) {
      text = text.substring('Exception:'.length).trim();
    }

    // Strip Firebase code prefixes like [firebase_auth/invalid-email] or [cloud_firestore/permission-denied]
    final bracketRegex = RegExp(r'^\[[a-zA-Z0-9_\-]+/[a-zA-Z0-9_\-]+\]\s*');
    text = text.replaceFirst(bracketRegex, '').trim();

    // Check for technical error dump artifacts that should not be shown to users
    final lower = text.toLowerCase();
    if (lower.contains('platformexception(') ||
        lower.contains('apiexception:') ||
        lower.contains('developer_error') ||
        lower.contains('lateinitializationerror') ||
        lower.contains('nosuchmethoderror') ||
        lower.contains('typeerror') ||
        lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('handshakeexception') ||
        lower.contains('status code 4') ||
        lower.contains('status code 5') ||
        lower.contains('stack trace:') ||
        lower.contains('at package:')) {
      return fallback;
    }

    return text.isEmpty ? fallback : text;
  }

  factory AppException.from(Object error, [StackTrace? stackTrace]) {
    if (error is AppException) {
      return AppException(
        sanitizeMessage(error.message),
        code: error.code,
        cause: error.cause ?? error,
      );
    }

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

    if (error is PlatformException) {
      return AppException(
        _platformMessage(error),
        code: error.code,
        cause: error,
      );
    }

    final str = error.toString();
    final lower = str.toLowerCase();

    if (lower.contains('socketexception') ||
        lower.contains('handshakeexception') ||
        lower.contains('clientexception') ||
        lower.contains('failed host lookup')) {
      return AppException(
        'No internet connection. Please check your network and retry.',
        code: 'network-error',
        cause: error,
      );
    }

    if (lower.contains('timeoutexception')) {
      return AppException(
        'The request timed out. Please check your connection and retry.',
        code: 'timeout',
        cause: error,
      );
    }

    if (lower.contains('formatexception')) {
      return AppException(
        'Invalid data received. Please verify and try again.',
        code: 'format-error',
        cause: error,
      );
    }

    return AppException(
      sanitizeMessage(str, fallback: 'Something went wrong. Please try again.'),
      cause: error,
    );
  }

  static String _authMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-phone-number':
        return 'Please enter a valid phone number with country code.';
      case 'invalid-verification-code':
        return 'The OTP you entered is incorrect.';
      case 'session-expired':
        return 'The OTP has expired. Please request a new one.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Incorrect email or password. Please verify your details.';
      case 'user-not-found':
        return 'No account found with this email. Please check the email or sign up.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'weak-password':
        return 'Please choose a stronger password (at least 6 characters).';
      case 'network-request-failed':
        return 'No internet connection. Please check your network and retry.';
      case 'requires-recent-login':
        return 'Please sign in again to complete this action.';
      case 'operation-not-allowed':
        return 'This sign-in method is currently disabled. Please use another option.';
      case 'quota-exceeded':
        return 'Daily SMS limit reached. Please try again tomorrow or sign in with email.';
      case 'app-not-authorized':
      case 'captcha-check-failed':
      case 'missing-client-identifier':
        return 'Phone verification is temporarily unavailable. Please sign in with email.';
      default:
        return sanitizeMessage(
          error.message,
          fallback: 'Authentication failed. Please check your details and try again.',
        );
    }
  }

  static String _firebaseMessage(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'You do not have permission to perform this action.';
      case 'unavailable':
        return 'You appear to be offline. Changes will sync automatically when back online.';
      case 'deadline-exceeded':
        return 'The request timed out. Please check your internet connection.';
      case 'not-found':
        return 'The requested record was not found.';
      case 'already-exists':
        return 'This record already exists.';
      case 'failed-precondition':
        return 'This request could not be completed right now. Please try again in a moment.';
      case 'resource-exhausted':
        return 'Server is busy right now. Please try again in a moment.';
      case 'cancelled':
        return 'The operation was cancelled.';
      default:
        return sanitizeMessage(
          error.message,
          fallback: 'Unable to save or load data. Please check your connection and try again.',
        );
    }
  }

  static String _platformMessage(PlatformException error) {
    final details = '${error.code} ${error.message ?? ''}'.toLowerCase();
    if (details.contains('developer_error') || details.contains('10:')) {
      return 'Google sign-in is temporarily unavailable. Please sign in with email or phone.';
    }
    if (details.contains('sign_in_canceled') ||
        details.contains('sign_in_cancelled') ||
        details.contains('12501') ||
        details.contains('12502')) {
      return 'Sign-in was cancelled.';
    }
    if (details.contains('network_error') || details.contains('7:')) {
      return 'No internet connection. Please check your network and retry.';
    }
    if (details.contains('camera_access_denied')) {
      return 'Camera permission was denied. Please allow camera access in Settings.';
    }
    if (details.contains('photo_access_denied')) {
      return 'Photo access was denied. Please allow photo access in Settings.';
    }
    return sanitizeMessage(
      error.message,
      fallback: 'A device error occurred. Please try again.',
    );
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
