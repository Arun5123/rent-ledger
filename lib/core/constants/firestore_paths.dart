/// Canonical Firestore & Cloud Storage path builders.
///
/// Every document is scoped under `users/{uid}` so that security rules can be
/// expressed with a single ownership check.
abstract final class FsPaths {
  static const String users = 'users';
  static const String properties = 'properties';
  static const String tenants = 'tenants';
  static const String transactions = 'transactions';
  static const String monthlyLedgers = 'monthly_ledgers';
  static const String notifications = 'notifications';
  static const String exportJobs = 'export_jobs';
  static const String settings = 'settings';

  static String user(String uid) => '$users/$uid';

  static String propertiesCol(String uid) => '${user(uid)}/$properties';

  static String property(String uid, String propertyId) =>
      '${propertiesCol(uid)}/$propertyId';

  static String tenantsCol(String uid, String propertyId) =>
      '${property(uid, propertyId)}/$tenants';

  static String tenant(String uid, String propertyId, String tenantId) =>
      '${tenantsCol(uid, propertyId)}/$tenantId';

  static String transactionsCol(String uid, String propertyId) =>
      '${property(uid, propertyId)}/$transactions';

  static String transaction(
    String uid,
    String propertyId,
    String transactionId,
  ) =>
      '${transactionsCol(uid, propertyId)}/$transactionId';

  static String monthlyLedgersCol(String uid) =>
      '${user(uid)}/$monthlyLedgers';

  static String monthlyLedger(String uid, String period) =>
      '${monthlyLedgersCol(uid)}/$period';

  static String notificationsCol(String uid) => '${user(uid)}/$notifications';

  static String exportJobsCol(String uid) => '${user(uid)}/$exportJobs';

  // ---------------------------------------------------------------- Storage

  /// Root folder that holds every binary belonging to a single property.
  static String storagePropertyRoot(String uid, String propertyId) =>
      'users/$uid/properties/$propertyId';

  static String storageTenantFolder(
    String uid,
    String propertyId,
    String tenantId,
  ) =>
      '${storagePropertyRoot(uid, propertyId)}/tenants/$tenantId';

  static String storageTransactionReceipt({
    required String uid,
    required String propertyId,
    required String transactionId,
    required String fileName,
  }) =>
      '${storagePropertyRoot(uid, propertyId)}/receipts/$transactionId/$fileName';

  static String storagePropertyPhoto({
    required String uid,
    required String propertyId,
    required String fileName,
  }) =>
      '${storagePropertyRoot(uid, propertyId)}/photos/$fileName';
}
