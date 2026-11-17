import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/notification_service.dart';
import 'app_providers.dart';
import 'auth_providers.dart';
import 'transaction_providers.dart';

/// The shared local-notifications service.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});

/// (Re)schedules rent-due local notifications whenever the notification
/// toggle, the reminder day or the pending dues change.
final dueReminderSchedulerProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(notificationServiceProvider);
  final profile = ref.watch(userProfileProvider).valueOrNull;
  final preferences = ref.watch(localPreferencesProvider);
  final metrics = ref.watch(dashboardMetricsProvider);

  final enabled = profile?.notificationsEnabled ?? preferences.notificationsEnabled;
  final day = profile?.rentReminderDay ?? preferences.rentReminderDay;

  await service.scheduleReminders(
    enabled: enabled,
    reminderDay: day,
    dues: metrics.duesByTenant,
  );
});