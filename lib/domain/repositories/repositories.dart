import 'dart:typed_data';

import '../models/auth_user.dart';
import '../models/enums.dart';
import '../models/ledger_transaction.dart';
import '../models/monthly_ledger.dart';
import '../models/property.dart';
import '../models/report.dart';
import '../models/tenant.dart';
import '../models/user_profile.dart';

/// Contracts implemented by the `data` layer and consumed by Riverpod
/// providers. Screens depend on these abstractions, never on Firestore.

abstract interface class AuthRepository {
  AuthUser? get currentUser;
  Stream<AuthUser?> authStateChanges();

  /// Starts phone verification. [onCodeSent] receives the verification id used
  /// by [signInWithSmsCode]; Android may auto-verify via [onAutoVerified].
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String message) onError,
    void Function(String verificationId, String smsCode)? onAutoVerified,
    int? resendToken,
  });

  Future<AuthUser> signInWithSmsCode({
    required String verificationId,
    required String smsCode,
    String? phoneNumber,
  });

  Future<AuthUser> signInWithGoogle();
  Future<AuthUser> signInWithEmail({
    required String email,
    required String password,
  });

  Future<AuthUser> signUpWithEmail({
    required String email,
    required String password,
    String? name,
  });

  Future<void> sendPasswordReset(String email);
  Future<void> updateDisplayName(String name);
  Future<void> signOut();

  /// Deletes the Firebase Auth user *and* cascades all Firestore data.
  Future<void> deleteAccount();
}

abstract interface class UserRepository {
  Stream<UserProfile?> watchProfile(String uid);
  Future<UserProfile?> getProfile(String uid);

  /// Creates the profile document on first sign-in (idempotent).
  Future<UserProfile> ensureProfile(AuthUser user);
  Future<void> saveProfile(UserProfile profile);
}

abstract interface class PropertyRepository {
  Stream<List<Property>> watchProperties(
    String uid, {
    bool includeArchived = false,
  });
  Future<Property?> getProperty(String uid, String propertyId);
  Future<String> createProperty(String uid, Property property);
  Future<void> updateProperty(String uid, Property property);
  Future<void> setArchived(String uid, String propertyId, bool archived);

  /// Recursively deletes the property with its tenants and transactions.
  Future<void> deletePropertyCascade(String uid, String propertyId);
}

abstract interface class TenantRepository {
  Stream<List<Tenant>> watchTenants(
    String uid,
    String propertyId, {
    TenantStatus? status,
  });

  /// Collection-group stream of every tenant the user owns.
  Stream<List<Tenant>> watchAllTenants(String uid, {TenantStatus? status});
  Future<List<Tenant>> fetchAllTenants(String uid, {TenantStatus? status});
  Future<Tenant?> getTenant(String uid, String propertyId, String tenantId);

  /// Adds the tenant, records the advance and flips the property to OCCUPIED
  /// inside a single Firestore transaction.
  Future<String> onboardTenant(
    String uid,
    Tenant tenant, {
    LedgerTransaction? advanceTransaction,
  });

  Future<void> updateTenant(String uid, Tenant tenant);

  /// Atomic exit: writes exitDetails, marks the tenant EXITED, frees the
  /// property and records the ADVANCE_REFUND transaction when money moves.
  Future<void> settleExit({
    required String uid,
    required Property property,
    required Tenant tenant,
    required TenantExitDetails details,
  });

  /// Records a post-exit settlement payment received from an exited tenant.
  Future<void> recordPostExitSettlement({
    required String uid,
    required Tenant tenant,
    required double amountPaid,
    required PaymentMethod paymentMethod,
    String? notes,
  });
}

abstract interface class TransactionRepository {
  Stream<List<LedgerTransaction>> watchForProperty(
    String uid,
    String propertyId, {
    int limit = 200,
  });

  /// Collection-group stream over every property the user owns.
  Stream<List<LedgerTransaction>> watchAll(String uid, {int limit = 500});

  Future<List<LedgerTransaction>> query(String uid, LedgerFilter filter);
  Future<LedgerTransaction?> getTransaction(
    String uid,
    String propertyId,
    String transactionId,
  );
  Future<String> addTransaction(String uid, LedgerTransaction transaction);
  Future<void> updateTransaction(String uid, LedgerTransaction transaction);
  Future<void> deleteTransaction(String uid, LedgerTransaction transaction);
}

abstract interface class LedgerRepository {
  Stream<MonthlyLedger> watchLedger(String uid, String period);

  /// Most recent [months] ledger documents, newest first.
  Stream<List<MonthlyLedger>> watchRecent(String uid, {int months = 6});

  /// Recomputes a month from the raw transactions and stores the roll-up.
  Future<void> rebuild(String uid, String period);
}

abstract interface class StorageRepository {
  /// Uploads [bytes] under [path] and returns the public URL.
  Future<String> uploadBytes({
    required String path,
    required Uint8List bytes,
    String contentType = 'application/octet-stream',
  });

  /// Deletes the file stored at [url].
  ///
  /// Only the Cloudinary implementation can remove files; this is a no-op
  /// fallback for repositories that do not support deletion.
  Future<bool> deleteBytes({required String url});
}

abstract interface class ReportExporter {
  ExportFormat get format;

  /// Renders the report into bytes. Persisting/sharing is the caller's job so
  /// this stays testable without touching the file system.
  Future<Uint8List> build(ReportBundle bundle, {String? propertyName});
}

abstract interface class SettlementStatementBuilder {
  /// Renders the tenant exit settlement statement PDF.
  Future<Uint8List> buildStatement({
    required Property property,
    required Tenant tenant,
    required TenantExitDetails details,
    required String currency,
  });
}
