import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentledger/core/errors/app_exception.dart';

void main() {
  group('AppException error handling & sanitization', () {
    test('userMessageOf returns polite fallback on null or empty error', () {
      expect(
        AppException.userMessageOf(null),
        'Something went wrong. Please try again.',
      );
      expect(
        AppException.userMessageOf(''),
        'Something went wrong. Please try again.',
      );
      expect(
        AppException.userMessageOf(null, fallback: 'Custom fallback'),
        'Custom fallback',
      );
    });

    test('sanitizeMessage strips Exception: and Firebase bracket prefixes', () {
      expect(
        AppException.sanitizeMessage('Exception: That property no longer exists.'),
        'That property no longer exists.',
      );
      expect(
        AppException.sanitizeMessage(
          '[firebase_auth/invalid-email] The email address is badly formatted.',
        ),
        'The email address is badly formatted.',
      );
      expect(
        AppException.sanitizeMessage(
          '[cloud_firestore/permission-denied] Missing or insufficient permissions.',
        ),
        'Missing or insufficient permissions.',
      );
    });

    test('technical exceptions and dumps are replaced with friendly messages', () {
      expect(
        AppException.sanitizeMessage(
          'PlatformException(sign_in_failed, com.google.android.gms.common.api.ApiException: 10: , null, null)',
        ),
        'Something went wrong. Please try again.',
      );
      expect(
        AppException.sanitizeMessage(
          'LateInitializationError: Field "_state" has not been initialized.',
        ),
        'Something went wrong. Please try again.',
      );
      expect(
        AppException.sanitizeMessage(
          'NoSuchMethodError: The getter "name" was called on null.',
        ),
        'Something went wrong. Please try again.',
      );
    });

    test('PlatformException for Google Sign-In developer error is translated gracefully', () {
      final platformError = PlatformException(
        code: '10',
        message: 'DEVELOPER_ERROR: Google sign-in is not configured for this build.',
      );
      final msg = AppException.userMessageOf(platformError);
      expect(msg.contains('DEVELOPER_ERROR'), isFalse);
      expect(msg.contains('fingerprint'), isFalse);
      expect(
        msg,
        'Google sign-in is temporarily unavailable. Please sign in with email or phone.',
      );
    });

    test('PlatformException for cancelled sign in is translated gracefully', () {
      final platformError = PlatformException(
        code: '12501',
        message: 'Sign in was cancelled by user.',
      );
      expect(AppException.userMessageOf(platformError), 'Sign-in was cancelled.');
    });

    test('network and socket exceptions translate to network messages', () {
      final socketError = const SocketException('Failed host lookup: firestore.googleapis.com');
      final msg = AppException.userMessageOf(socketError);
      expect(msg, 'No internet connection. Please check your network and retry.');
    });

    test('AppException keeps clean message intact', () {
      const cleanException = AppException('This property still has an active tenant.');
      expect(
        AppException.userMessageOf(cleanException),
        'This property still has an active tenant.',
      );
    });
  });
}
