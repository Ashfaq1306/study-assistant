import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/calendar_event.dart';

/// One notification to show at [at].
typedef PlannedReminder = ({int id, DateTime at, String title, String body});

/// How far ahead reminders are scheduled; refreshed whenever the app opens.
const reminderWindow = Duration(days: 30);

/// Android keeps a limited number of alarms per app: stay well under it.
const maxScheduledReminders = 60;

String _before(int minutes) {
  if (minutes == 0) return 'Now';
  if (minutes % 1440 == 0) return minutes == 1440 ? 'Tomorrow' : 'In ${minutes ~/ 1440} days';
  if (minutes % 60 == 0) return minutes == 60 ? 'In 1 hour' : 'In ${minutes ~/ 60} hours';
  return 'In $minutes minutes';
}

/// The reminders due between [now] and the window's end, soonest first.
List<PlannedReminder> planReminders(List<CalendarEvent> events, DateTime now) {
  final planned = <PlannedReminder>[];
  final longest = Duration(minutes: events.expand((e) => e.reminders).fold(0, (a, b) => a > b ? a : b));
  for (final o in occurrencesBetween(events, now, now.add(reminderWindow + longest))) {
    for (final minutes in o.event.reminders) {
      final at = o.start.subtract(Duration(minutes: minutes));
      if (!at.isAfter(now) || at.isAfter(now.add(reminderWindow))) continue;
      final e = o.event;
      final where = e.location.isEmpty ? '' : ' · ${e.location}';
      final when = e.allDay ? '' : ' at ${_clock(o.start)}';
      planned.add((
        // Stable per event, occurrence and reminder, so rescheduling replaces rather than duplicates.
        id: Object.hash(e.id ?? e.title, o.start.millisecondsSinceEpoch, minutes) & 0x7fffffff,
        at: at,
        title: '${e.kind.label}: ${e.title}',
        body: '${_before(minutes)}$when$where',
      ));
    }
  }
  planned.sort((a, b) => a.at.compareTo(b.at));
  return planned.take(maxScheduledReminders).toList();
}

String _clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// Schedules calendar reminders as phone notifications, so they work offline and
/// with the app closed.
class ReminderScheduler {
  ReminderScheduler({FlutterLocalNotificationsPlugin? plugin}) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'calendar_reminders',
    'Calendar reminders',
    channelDescription: 'Exams, classes, deadlines and other calendar items.',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
  );

  bool get _supported => !kIsWeb && Platform.isAndroid;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> _init() async {
    if (_ready) return;
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } on Object {
      tz.setLocalLocation(tz.UTC);
    }
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    _ready = true;
  }

  /// Asks for notification permission (Android 13+). True when reminders can show.
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    await _init();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  /// Whether reminders can fire on the minute ("Alarms & reminders" allowed).
  Future<bool> canBeExact() async {
    if (!_supported) return false;
    await _init();
    return await _android?.canScheduleExactNotifications() ?? false;
  }

  Future<void> requestExact() async {
    if (!_supported) return;
    await _init();
    await _android?.requestExactAlarmsPermission();
  }

  /// Replaces every scheduled reminder with the plan for [events].
  Future<int> scheduleAll(List<CalendarEvent> events) async {
    if (!_supported) return 0;
    await _init();
    await _plugin.cancelAllPendingNotifications();
    final exact = await canBeExact();
    final plan = planReminders(events, DateTime.now());
    for (final r in plan) {
      await _plugin.zonedSchedule(
        id: r.id,
        scheduledDate: tz.TZDateTime.from(r.at, tz.local),
        notificationDetails: const NotificationDetails(android: _channel),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
      );
    }
    return plan.length;
  }

  Future<void> clear() async {
    if (!_supported) return;
    await _init();
    await _plugin.cancelAllPendingNotifications();
  }
}
