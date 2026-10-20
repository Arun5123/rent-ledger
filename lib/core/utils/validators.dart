/// Reusable form validators for every input in the app.
abstract final class Validators {
  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  static String? name(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Name is required';
    if (trimmed.length < 2) return 'Name is too short';
    return null;
  }

  static String? phone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 'Phone number is required';
    if (digits.length < 10) return 'Enter a valid 10-digit number';
    if (digits.length > 15) return 'Phone number is too long';
    return null;
  }

  static String? otp(String? value) {
    final digits = (value ?? '').trim();
    if (digits.length != 6) return 'Enter the 6-digit OTP';
    return null;
  }

  static String? email(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null; // email is optional in most forms
    final regex = RegExp(r'^[\w.!#$%&*+/=?^`{|}~-]+@[\w-]+(\.[\w-]+)+$');
    return regex.hasMatch(trimmed) ? null : 'Enter a valid email';
  }

  static String? requiredEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Email is required';
    return email(trimmed);
  }

  static String? password(String? value) {
    final trimmed = value ?? '';
    if (trimmed.isEmpty) return 'Password is required';
    if (trimmed.length < 6) return 'Use at least 6 characters';
    return null;
  }

  static String? amount(String? value, {String field = 'Amount'}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return '$field is required';
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return 'Enter a valid number';
    if (parsed < 0) return '$field cannot be negative';
    return null;
  }

  static String? positiveAmount(String? value, {String field = 'Amount'}) {
    final error = amount(value, field: field);
    if (error != null) return error;
    if (double.parse(value!.trim()) <= 0) return '$field must be greater than 0';
    return null;
  }

  /// Like [amount], but an empty field is accepted and read as `0`.
  ///
  /// Used by fields whose placeholder already shows `0`, so the user can leave
  /// them untouched instead of having to clear a pre-filled digit.
  static String? optionalAmount(String? value, {String field = 'Amount'}) {
    if ((value ?? '').trim().isEmpty) return null;
    return amount(value, field: field);
  }

  static String? meterReading(String? value, {double? previous}) {
    final error = amount(value, field: 'Meter reading');
    if (error != null) return error;
    final parsed = double.parse(value!.trim());
    if (previous != null && parsed < previous) {
      return 'Reading cannot be lower than the previous reading';
    }
    return null;
  }

  static String? dateRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return null;
    if (end.isBefore(start)) return 'End date must be after the start date';
    return null;
  }

  static String? idProof(String? value) => email(value);
}
