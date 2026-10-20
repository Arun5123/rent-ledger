import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';

/// Thin typed wrapper over [SharedPreferences] for device-local settings.
///
/// Used for things that must be available before Firestore warms up (first
/// run onboarding, dark mode, notification toggles).
class LocalPreferences {
  LocalPreferences(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalPreferences> load() async =>
      LocalPreferences(await SharedPreferences.getInstance());

  bool get onboardingComplete =>
      _prefs.getBool(AppConstants.prefOnboardingComplete) ?? false;

  Future<void> setOnboardingComplete(bool value) =>
      _prefs.setBool(AppConstants.prefOnboardingComplete, value);

  bool get darkMode => _prefs.getBool(AppConstants.prefDarkMode) ?? false;

  Future<void> setDarkMode(bool value) =>
      _prefs.setBool(AppConstants.prefDarkMode, value);

  String get currency =>
      _prefs.getString(AppConstants.prefCurrency) ??
      AppConstants.defaultCurrency;

  Future<void> setCurrency(String value) =>
      _prefs.setString(AppConstants.prefCurrency, value);

  double get defaultRatePerUnit =>
      _prefs.getDouble(AppConstants.prefDefaultRatePerUnit) ??
      AppConstants.defaultRatePerUnit;

  Future<void> setDefaultRatePerUnit(double value) =>
      _prefs.setDouble(AppConstants.prefDefaultRatePerUnit, value);

  bool get notificationsEnabled =>
      _prefs.getBool(AppConstants.prefNotificationsEnabled) ?? true;

  Future<void> setNotificationsEnabled(bool value) =>
      _prefs.setBool(AppConstants.prefNotificationsEnabled, value);

  int get rentReminderDay =>
      _prefs.getInt(AppConstants.prefRentReminderDay) ?? 1;

  Future<void> setRentReminderDay(int value) =>
      _prefs.setInt(AppConstants.prefRentReminderDay, value);

  Future<void> clear() => _prefs.clear();
}
