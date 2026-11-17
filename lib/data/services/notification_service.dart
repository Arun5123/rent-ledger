import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rentledger/core/utils/formatters.dart';
import 'package:rentledger/domain/models/report.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Schedules local rent-due reminders so the landlord never misses an
/// unpaid tenant due.
///
/// Reminders are purely local (no server/FCM dependency):
///   * when notifications are enabled and there are pending dues, a
///     "beginning of month" reminder fires at 7:00 AM on the 1st of every
///     month;
///   * when the reminder day is set to `1`, a daily reminder fires at
///     7:00 AM instead;
///   * when the reminder day is `5` / `10` / `15` / `30`, an additional
///     reminder fires on that day of the month at 7:00 AM.
///
/// Tapping a reminder opens the dashboard where the pending dues list lives.
final class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Invoked when the user taps a due-reminder notification.
  void Function()? onReminderTapped;

  /// Channel id used for all rent-due reminders.
  static const String _channelId = 'rent_dues';
  static const String _channelName = 'Rent due reminders';

  /// Notification ids — kept stable so re-scheduling replaces previous ones.
  static const int _idDaily = 1001;
  static const int _idMonthStart = 1002;
  static const int _idDayOfMonth = 1003;

  /// Days of month offered in settings; anything else means "no reminder".
  static bool _isReminderDay(int day) =>
      day == 1 || day == 5 || day == 10 || day == 15 || day == 30;

  /// Initializes the plugin and requests notification permissions. Safe to
  /// call multiple times; only the first call does anything.
  Future<bool> init() async {
    if (_initialized) return true;
    tz.initializeTimeZones();

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload ?? '';
        if (payload.startsWith('dues_')) onReminderTapped?.call();
      },
    );

    final android =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();

    final ios =
        _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(sound: true, alert: true, badge: true);

    _initialized = true;
    return true;
  }

  /// (Re)schedules all due reminders based on the current preference state.
  ///
  /// Call this whenever notifications are toggled, the reminder day changes
  /// or the pending dues change (e.g. from the dashboard).
  Future<void> scheduleReminders({
    required bool enabled,
    required int reminderDay,
    required List<TenantDue> dues,
  }) async {
    await init();
    await _plugin.cancelAll();

    if (!enabled || dues.isEmpty || reminderDay == 0) return;

    final total = dues.fold<double>(0, (sum, d) => sum + d.dueAmount);
    final names = dues.map((d) => d.tenantName).take(2).join(', ');
    final more = dues.length > 2 ? ' and ${dues.length - 2} more' : '';
    final body =
        '${dues.length} pending due${dues.length == 1 ? '' : 's'} totaling '
        '${Formatters.currencyShort(total)}$more ($names$more). Tap to review.';
    final title = 'Rent due reminder';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Reminders for unpaid tenant rents.',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    final now = tz.TZDateTime.now(tz.local);

    if (reminderDay == 1) {
      // Daily at 7:00 AM — covers the start of the month too.
      await _plugin.zonedSchedule(
        _idDaily,
        title,
        body,
        _sevenAm(now, now.day),
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.wallClockTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'dues_daily',
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return;
    }

    if (_isReminderDay(reminderDay)) {
      // Beginning-of-month reminder (1st at 7:00 AM).
      await _plugin.zonedSchedule(
        _idMonthStart,
        title,
        body,
        _sevenAm(now, 1),
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.wallClockTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'dues_month_start',
        matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
      );

      // Reminder on the chosen day of month at 7:00 AM.
      await _plugin.zonedSchedule(
        _idDayOfMonth,
        title,
        body,
        _sevenAm(now, reminderDay),
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.wallClockTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'dues_day_$reminderDay',
        matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
      );
    }
  }

  /// 7:00 AM local on [day] of the current month, rolled to the next month if
  /// that time has already passed.
  static tz.TZDateTime _sevenAm(tz.TZDateTime now, int day) {
    final candidate =
        tz.TZDateTime.from(DateTime(now.year, now.month, day, 7, 0), tz.local);
    return candidate.isAfter(now) ? candidate : _sevenAm(_nextMonth(now), day);
  }

  static tz.TZDateTime _nextMonth(tz.TZDateTime now) =>
      tz.TZDateTime.from(DateTime(now.year, now.month + 1), tz.local);
}