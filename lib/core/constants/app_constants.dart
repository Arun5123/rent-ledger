/// Application-wide constants.
abstract final class AppConstants {
  static const String appName = 'Rent Ledger';
  static const String appTagline = 'Rental & Property Ledger';
  static const String defaultCurrency = 'INR';
  static const String currencySymbol = '\u20B9';

  /// Default electricity unit rate (INR per unit) used when onboarding.
  static const double defaultRatePerUnit = 8.0;

  /// Fallback country code for phone auth.
  static const String defaultCountryCode = '+91';

  /// Firestore batch limit is 500 writes; keep headroom for sub-deletes.
  static const int batchChunkSize = 400;

  /// Reporting / list defaults.
  static const int defaultPageSize = 50;

  /// Firestore billing-period key format (`YYYY-MM`).
  static const String monthPeriodFormat = 'yyyy-MM';

  /// Storage location for locally generated exports (PDF / XLSX / CSV).
  static const String exportFolderName = 'rentledger_exports';

  /// SharedPreferences keys.
  static const String prefOnboardingComplete = 'onboarding_complete';
  static const String prefCurrency = 'preferred_currency';
  static const String prefDefaultRatePerUnit = 'default_rate_per_unit';
  static const String prefNotificationsEnabled = 'notifications_enabled';
  static const String prefRentReminderDay = 'rent_reminder_day';
  static const String prefDarkMode = 'dark_mode';

  /// Phone (SMS OTP) sign-in only issues real verification codes on the Blaze
  /// plan, so the segment stays hidden unless the build opts in:
  ///
  /// ```sh
  /// flutter run --dart-define=ENABLE_PHONE_AUTH=true
  /// ```
  static const bool phoneAuthEnabled = bool.fromEnvironment(
    'ENABLE_PHONE_AUTH',
  );
}
