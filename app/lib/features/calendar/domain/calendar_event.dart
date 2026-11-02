import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

enum CalendarKind {
  exam('EXAM', 'Exam', Icons.quiz_rounded),
  classSession('CLASS', 'Class', Icons.school_rounded),
  assignment('ASSIGNMENT', 'Assignment', Icons.assignment_rounded),
  holiday('HOLIDAY', 'Holiday', Icons.beach_access_rounded),
  event('EVENT', 'Event', Icons.event_rounded);

  const CalendarKind(this.api, this.label, this.icon);

  final String api;
  final String label;
  final IconData icon;

  Color get color => switch (this) {
    CalendarKind.exam => AppColors.coralDeep,
    CalendarKind.classSession => AppColors.violet,
    CalendarKind.assignment => AppColors.sunshineDeep,
    CalendarKind.holiday => AppColors.mintDeep,
    CalendarKind.event => AppColors.skyDeep,
  };

  /// Reminders when the student doesn't choose (minutes before; matches the server).
  List<int> get defaultReminders => switch (this) {
    CalendarKind.exam => const [1440, 60],
    CalendarKind.classSession => const [15],
    CalendarKind.assignment => const [1440],
    CalendarKind.holiday => const [],
    CalendarKind.event => const [60],
  };

  static CalendarKind fromApi(String value) => values.firstWhere((k) => k.api == value, orElse: () => event);
}

/// An item on the calendar. Weekly items (classes) repeat on the start's weekday.
@immutable
class CalendarEvent {
  const CalendarEvent({
    this.id,
    required this.kind,
    required this.title,
    required this.startsAt,
    this.subject = '',
    this.location = '',
    this.notes = '',
    this.endsAt,
    this.allDay = false,
    this.weekly = false,
    this.repeatUntil,
    this.reminders = const [],
    this.source = 'MANUAL',
  });

  /// Null until saved.
  final String? id;
  final CalendarKind kind;
  final String title;
  final String subject;
  final String location;
  final String notes;

  /// Local time (converted from the server's UTC).
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool allDay;
  final bool weekly;
  final DateTime? repeatUntil;

  /// Minutes before the start, largest first.
  final List<int> reminders;
  final String source;

  CalendarEvent copyWith({
    CalendarKind? kind,
    String? title,
    String? subject,
    String? location,
    String? notes,
    DateTime? startsAt,
    DateTime? Function()? endsAt,
    bool? allDay,
    bool? weekly,
    List<int>? reminders,
  }) => CalendarEvent(
    id: id,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    subject: subject ?? this.subject,
    location: location ?? this.location,
    notes: notes ?? this.notes,
    startsAt: startsAt ?? this.startsAt,
    endsAt: endsAt == null ? this.endsAt : endsAt(),
    allDay: allDay ?? this.allDay,
    weekly: weekly ?? this.weekly,
    repeatUntil: repeatUntil,
    reminders: reminders ?? this.reminders,
    source: source,
  );

  factory CalendarEvent.fromJson(Map<String, Object?> json) => CalendarEvent(
    id: json['id'] as String?,
    kind: CalendarKind.fromApi(json['kind']! as String),
    title: json['title']! as String,
    subject: json['subject'] as String? ?? '',
    location: json['location'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    startsAt: DateTime.parse(json['startsAt']! as String).toLocal(),
    endsAt: json['endsAt'] == null ? null : DateTime.parse(json['endsAt']! as String).toLocal(),
    allDay: json['allDay'] as bool? ?? false,
    weekly: json['weekly'] as bool? ?? false,
    repeatUntil: json['repeatUntil'] == null ? null : DateTime.parse(json['repeatUntil']! as String).toLocal(),
    reminders: [for (final r in json['reminders'] as List<Object?>? ?? const []) (r! as num).toInt()],
    source: json['source'] as String? ?? 'MANUAL',
  );

  Map<String, Object?> toJson() => {
    'kind': kind.api,
    'title': title.trim(),
    'subject': subject.trim(),
    'location': location.trim(),
    'notes': notes.trim(),
    'startsAt': startsAt.toUtc().toIso8601String(),
    'endsAt': endsAt?.toUtc().toIso8601String(),
    'allDay': allDay,
    'weekly': weekly,
    'repeatUntil': repeatUntil?.toUtc().toIso8601String(),
    'reminders': reminders,
  };
}

/// One time an event happens (weekly classes happen many times).
@immutable
class Occurrence {
  const Occurrence(this.event, this.start, this.end);

  final CalendarEvent event;
  final DateTime start;
  final DateTime? end;

  /// True if this occurrence touches the local [day].
  bool onDay(DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final last = end ?? start;
    return start.isBefore(dayEnd) && !last.isBefore(dayStart);
  }
}

/// Every occurrence that starts or runs within [from, to), in time order.
List<Occurrence> occurrencesBetween(List<CalendarEvent> events, DateTime from, DateTime to) {
  final result = <Occurrence>[];
  for (final e in events) {
    final length = e.endsAt?.difference(e.startsAt);
    if (!e.weekly) {
      final end = e.endsAt ?? e.startsAt;
      if (e.startsAt.isBefore(to) && !end.isBefore(from)) result.add(Occurrence(e, e.startsAt, e.endsAt));
      continue;
    }
    // Weekly: step whole weeks in local time (keeps the clock time across DST).
    var weeks = from.isAfter(e.startsAt) ? from.difference(e.startsAt).inDays ~/ 7 : 0;
    while (true) {
      final start = DateTime(
        e.startsAt.year,
        e.startsAt.month,
        e.startsAt.day + weeks * 7,
        e.startsAt.hour,
        e.startsAt.minute,
      );
      if (!start.isBefore(to) || (e.repeatUntil != null && start.isAfter(e.repeatUntil!))) break;
      final end = length == null ? null : start.add(length);
      if (!(end ?? start).isBefore(from)) result.add(Occurrence(e, start, end));
      weeks++;
    }
  }
  result.sort((a, b) => a.start.compareTo(b.start));
  return result;
}
