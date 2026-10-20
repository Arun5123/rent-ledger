import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exception.dart';
import '../core/utils/validators.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../domain/models/auth_user.dart';
import '../domain/models/user_profile.dart';
import 'app_providers.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState({required this.status, this.user});

  final AuthStatus status;
  final AuthUser? user;

  bool get isSignedIn => status == AuthStatus.signedIn && user != null;
  bool get isResolved => status != AuthStatus.unknown;

  static const AuthState unknown = AuthState(status: AuthStatus.unknown);
}

/// Synchronous view of the auth session.
///
/// The router needs to make an immediate redirect decision, so the latest
/// stream value is mirrored into a [Notifier] instead of an `AsyncValue`.
class AuthStateNotifier extends Notifier<AuthState> {
  StreamSubscription<AuthUser?>? _subscription;

  @override
  AuthState build() {
    final repository = ref.watch(authRepositoryProvider);
    final current = repository.currentUser;
    _subscription = repository.authStateChanges().listen((user) {
      state = AuthState(
        status: user == null ? AuthStatus.signedOut : AuthStatus.signedIn,
        user: user,
      );
    });
    ref.onDispose(() => _subscription?.cancel());

    if (current != null) {
      return AuthState(status: AuthStatus.signedIn, user: current);
    }
    return AuthState.unknown;
  }
}

final authStateProvider = NotifierProvider<AuthStateNotifier, AuthState>(
  AuthStateNotifier.new,
);

final currentUserProvider = Provider<AuthUser?>(
  (ref) => ref.watch(authStateProvider).user,
);

final currentUidProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider).user?.uid,
);

/// The landlord's profile document (currency, defaults, notification prefs).
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream<UserProfile?>.value(null);
  return ref.watch(userRepositoryProvider).watchProfile(uid);
});

/// Ensures `users/{uid}` exists for the freshly signed-in user.
final profileBootstrapProvider = FutureProvider<UserProfile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.watch(userRepositoryProvider).ensureProfile(user);
});

// ------------------------------------------------------------- phone sign-in

class PhoneAuthState {
  const PhoneAuthState({
    this.phoneNumber = '',
    this.verificationId,
    this.sendingCode = false,
    this.verifying = false,
    this.error,
    this.codeSent = false,
    this.resendToken,
  });

  final String phoneNumber;
  final String? verificationId;
  final bool sendingCode;
  final bool verifying;
  final String? error;
  final bool codeSent;
  final int? resendToken;

  PhoneAuthState copyWith({
    String? phoneNumber,
    String? verificationId,
    bool? sendingCode,
    bool? verifying,
    String? error,
    bool? codeSent,
    int? resendToken,
    bool clearError = false,
  }) =>
      PhoneAuthState(
        phoneNumber: phoneNumber ?? this.phoneNumber,
        verificationId: verificationId ?? this.verificationId,
        sendingCode: sendingCode ?? this.sendingCode,
        verifying: verifying ?? this.verifying,
        error: clearError ? null : (error ?? this.error),
        codeSent: codeSent ?? this.codeSent,
        resendToken: resendToken ?? this.resendToken,
      );
}

class PhoneAuthController extends Notifier<PhoneAuthState> {
  @override
  PhoneAuthState build() => const PhoneAuthState();

  /// Sends (or re-sends) the OTP. Returns true when SMS was dispatched.
  Future<bool> sendCode(String rawPhone) async {
    final error = Validators.phone(rawPhone);
    if (error != null) {
      state = state.copyWith(error: error, sendingCode: false);
      return false;
    }
    final phone = FirebaseAuthRepository.normalisePhone(rawPhone);
    state = state.copyWith(
      phoneNumber: phone,
      sendingCode: true,
      clearError: true,
    );

    final completer = Completer<bool>();
    await ref.read(authRepositoryProvider).verifyPhoneNumber(
          phoneNumber: phone,
          resendToken: state.resendToken,
          onCodeSent: (verificationId, token) {
            state = state.copyWith(
              verificationId: verificationId,
              resendToken: token,
              sendingCode: false,
              codeSent: true,
            );
            if (!completer.isCompleted) completer.complete(true);
          },
          onError: (message) {
            state = state.copyWith(sendingCode: false, error: message);
            if (!completer.isCompleted) completer.complete(false);
          },
          onAutoVerified: (verificationId, code) async {
            state = state.copyWith(verificationId: verificationId);
            try {
              await ref
                  .read(authRepositoryProvider)
                  .signInWithSmsCode(verificationId: verificationId, smsCode: code);
              if (!completer.isCompleted) completer.complete(true);
            } catch (_) {
              // Manual entry still works if auto-retrieval fails.
            }
          },
        );

    // Safety net: never leave the UI spinning if the SDK stays silent.
    return completer.future.timeout(
      const Duration(seconds: 65),
      onTimeout: () {
        state = state.copyWith(
          sendingCode: false,
          error: 'We could not send the OTP. Please retry.',
        );
        return false;
      },
    );
  }

  /// Verifies the typed OTP. Returns the signed-in user on success.
  Future<AuthUser?> verify(String smsCode) async {
    final verificationId = state.verificationId;
    if (verificationId == null) {
      state = state.copyWith(error: 'Please request a new OTP.');
      return null;
    }
    final formatError = Validators.otp(smsCode);
    if (formatError != null) {
      state = state.copyWith(error: formatError);
      return null;
    }

    state = state.copyWith(verifying: true, clearError: true);
    try {
      final user = await ref.read(authRepositoryProvider).signInWithSmsCode(
            verificationId: verificationId,
            smsCode: smsCode.trim(),
            phoneNumber: state.phoneNumber,
          );
      state = state.copyWith(verifying: false);
      return user;
    } catch (error) {
      state = state.copyWith(
        verifying: false,
        error: error is AppException ? error.message : 'Verification failed.',
      );
      return null;
    }
  }

  void resetError() => state = state.copyWith(clearError: true);
}

final phoneAuthControllerProvider =
    NotifierProvider<PhoneAuthController, PhoneAuthState>(
  PhoneAuthController.new,
);

// ------------------------------------------------------------------- actions

class AuthActionController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<bool> signInWithGoogle() => _run(
        () => ref.read(authRepositoryProvider).signInWithGoogle(),
      );

  Future<bool> signInWithEmail(String email, String password) => _run(
        () => ref
            .read(authRepositoryProvider)
            .signInWithEmail(email: email, password: password),
      );

  Future<bool> signUpWithEmail(
    String email,
    String password, {
    String? name,
  }) =>
      _run(
        () => ref.read(authRepositoryProvider).signUpWithEmail(
              email: email,
              password: password,
              name: name,
            ),
      );

  Future<bool> sendPasswordReset(String email) => _run(
        () => ref.read(authRepositoryProvider).sendPasswordReset(email),
      );

  Future<bool> signOut() => _run(
        () => ref.read(authRepositoryProvider).signOut(),
      );

  Future<bool> deleteAccount() => _run(
        () => ref.read(authRepositoryProvider).deleteAccount(),
      );

  /// Persists display-name changes to both Auth and the profile document.
  Future<bool> updateName(String name) => _run(() async {
        final uid = ref.read(currentUidProvider);
        if (uid == null) throw const AppException('You are not signed in.');
        await ref.read(authRepositoryProvider).updateDisplayName(name);
        final profile = await ref.read(userRepositoryProvider).getProfile(uid);
        final base = profile ?? (await _ensureProfile(uid));
        await ref
            .read(userRepositoryProvider)
            .saveProfile(base.copyWith(name: name.trim()));
      });

  Future<UserProfile> _ensureProfile(String uid) async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      throw const AppException('You are not signed in.');
    }
    return ref.read(userRepositoryProvider).ensureProfile(user);
  }

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData<void>(null);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError<void>(error, stackTrace);
      return false;
    }
  }
}

final authActionControllerProvider =
    AsyncNotifierProvider<AuthActionController, void>(
  AuthActionController.new,
);

/// Human-readable message for the most recent auth failure.
final authErrorProvider = Provider<String?>((ref) {
  final error = ref.watch(authActionControllerProvider).error;
  if (error == null) return null;
  return error is AppException ? error.message : error.toString();
});
