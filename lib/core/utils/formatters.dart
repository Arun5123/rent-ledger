import 'package:intl/intl.dart';

import '../constants/app_constants.dart';

/// Currency + date formatting helpers (Indian numbering by default).
abstract final class Formatters {
  static const String _defaultLocale = 'en_IN';

  /// `₹1,23,456.00`
  static String currency(
    num amount, {
    String? currencyCode,
    bool compact = false,
  }) {
    final symbol = _symbolFor(currencyCode);
    if (compact && amount.abs() >= 10000000) {
      return '$symbol${(amount / 10000000).toStringAsFixed(2)} Cr';
    }
    if (compact && amount.abs() >= 100000) {
      return '$symbol${(amount / 100000).toStringAsFixed(2)} L';
    }
    final formatter = NumberFormat.currency(
      locale: _defaultLocale,
      symbol: symbol,
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  /// `₹1,23,456` — used in tables where paise add noise.
  static String currencyShort(num amount, {String? currencyCode}) {
    final formatter = NumberFormat.currency(
      locale: _defaultLocale,
      symbol: _symbolFor(currencyCode),
      decimalDigits: 0,
    );
    return formatter.format(amount);
  }

  static String number(num value) =>
      NumberFormat.decimalPattern(_defaultLocale).format(value);

  static String units(num value) => NumberFormat('0.##').format(value);

  static String percent(num value) =>
      '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)}%';

  static String date(DateTime value) =>
      DateFormat('dd MMM yyyy').format(value);

  static String dateTime(DateTime value) =>
      DateFormat('dd MMM yyyy, hh:mm a').format(value);

  static String monthYear(DateTime value) => DateFormat('MMM yyyy').format(value);

  /// Firestore period key: `YYYY-MM`.
  static String periodKey(DateTime value) =>
      DateFormat(AppConstants.monthPeriodFormat).format(value);

  static String monthLabel(String periodKey) {
    final parsed = parsePeriodKey(periodKey);
    return parsed == null ? periodKey : monthYear(parsed);
  }

  static DateTime? parsePeriodKey(String periodKey) {
    final parts = periodKey.split('-');
    if (parts.length != 2) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) return null;
    return DateTime(year, month);
  }

  static DateTime monthStart(DateTime value) => DateTime(value.year, value.month);

  static DateTime monthEnd(DateTime value) =>
      DateTime(value.year, value.month + 1, 0, 23, 59, 59);

  static String relative(DateTime value) {
    final now = DateTime.now();
    final diff = now.difference(value);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return date(value);
  }

  static String _symbolFor(String? currencyCode) {
    switch ((currencyCode ?? AppConstants.defaultCurrency).toUpperCase()) {
      case 'INR':
        return AppConstants.currencySymbol;
      case 'USD':
        return r'$';
      case 'EUR':
        return '\u20AC';
      case 'GBP':
        return '\u00A3';
      case 'AED':
        return 'AED ';
      default:
        return '';
    }
  }
}
