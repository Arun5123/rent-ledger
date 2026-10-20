import '../../core/constants/app_constants.dart';
import '../../core/utils/json_utils.dart';

/// The landlord's profile document: `users/{uid}`.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.name,
    this.phone = '',
    this.email,
    this.currency = AppConstants.defaultCurrency,
    this.defaultRatePerUnit = AppConstants.defaultRatePerUnit,
    this.notificationsEnabled = true,
    this.rentReminderDay = 1,
    this.onboardingComplete = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String uid;
  final String name;
  final String phone;
  final String? email;
  final String currency;
  final double defaultRatePerUnit;
  final bool notificationsEnabled;

  /// Day of month (1–28) on which rent reminders are sent.
  final int rentReminderDay;
  final bool onboardingComplete;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory UserProfile.initial({
    required String uid,
    String? name,
    String? phone,
    String? email,
  }) {
    final now = DateTime.now();
    return UserProfile(
      uid: uid,
      name: name?.trim().isNotEmpty == true ? name!.trim() : 'Landlord',
      phone: phone ?? '',
      email: email,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory UserProfile.fromJson(String uid, Map<String, dynamic> json) {
    final created = JsonUtils.toDateTimeOr(json['createdAt'], DateTime.now());
    return UserProfile(
      uid: JsonUtils.toStr(json['uid'], uid),
      name: JsonUtils.toStr(json['name'], 'Landlord'),
      phone: JsonUtils.toStr(json['phone']),
      email: JsonUtils.toNullableStr(json['email']),
      currency: JsonUtils.toStr(json['currency'], AppConstants.defaultCurrency),
      defaultRatePerUnit: JsonUtils.toDouble(
        json['defaultRatePerUnit'],
        AppConstants.defaultRatePerUnit,
      ),
      notificationsEnabled: JsonUtils.toBool(json['notificationsEnabled'], true),
      rentReminderDay: JsonUtils.toInt(json['rentReminderDay'], 1),
      onboardingComplete: JsonUtils.toBool(json['onboardingComplete']),
      createdAt: created,
      updatedAt: JsonUtils.toDateTimeOr(json['updatedAt'], created),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uid': uid,
        'name': name,
        'phone': phone,
        'email': email,
        'currency': currency,
        'defaultRatePerUnit': defaultRatePerUnit,
        'notificationsEnabled': notificationsEnabled,
        'rentReminderDay': rentReminderDay,
        'onboardingComplete': onboardingComplete,
        'createdAt': JsonUtils.fromDateTime(createdAt),
        'updatedAt': JsonUtils.fromDateTime(updatedAt),
      };

  UserProfile copyWith({
    String? name,
    String? phone,
    String? email,
    String? currency,
    double? defaultRatePerUnit,
    bool? notificationsEnabled,
    int? rentReminderDay,
    bool? onboardingComplete,
    DateTime? updatedAt,
  }) =>
      UserProfile(
        uid: uid,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        currency: currency ?? this.currency,
        defaultRatePerUnit: defaultRatePerUnit ?? this.defaultRatePerUnit,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        rentReminderDay: rentReminderDay ?? this.rentReminderDay,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  @override
  bool operator ==(Object other) =>
      other is UserProfile && other.uid == uid && other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(uid, updatedAt);
}
