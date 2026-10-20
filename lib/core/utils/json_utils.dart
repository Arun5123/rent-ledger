import 'package:cloud_firestore/cloud_firestore.dart';

/// Defensive JSON coercion helpers shared by every Firestore model.
///
/// Firestore may hand back `int`, `double`, `String`, `Timestamp` or `null`
/// depending on how a value was written (and on legacy documents), so models
/// never cast directly.
abstract final class JsonUtils {
  static DateTime? toDateTime(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static DateTime toDateTimeOr(Object? value, DateTime fallback) =>
      toDateTime(value) ?? fallback;

  static Timestamp? fromDateTime(DateTime? value) =>
      value == null ? null : Timestamp.fromDate(value);

  static double toDouble(Object? value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is double) return value.isFinite ? value : fallback;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static int toInt(Object? value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static bool toBool(Object? value, [bool fallback = false]) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return fallback;
  }

  static String toStr(Object? value, [String fallback = '']) {
    if (value == null) return fallback;
    return value.toString();
  }

  static String? toNullableStr(Object? value) {
    if (value == null) return null;
    final str = value.toString().trim();
    return str.isEmpty ? null : str;
  }

  static Map<String, dynamic> toMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, v) => MapEntry(key.toString(), v));
    }
    return const <String, dynamic>{};
  }

  static Map<String, dynamic>? toNullableMap(Object? value) {
    if (value == null) return null;
    final map = toMap(value);
    return map.isEmpty ? null : map;
  }

  static List<String> toStringList(Object? value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList(growable: false);
    }
    return const <String>[];
  }

  /// Rounds to two decimals — money is always stored clean.
  static double money(double value) => (value * 100).roundToDouble() / 100;
}
