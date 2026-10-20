import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/features/calendar/application/reminders.dart';
import 'package:study_assistant/features/calendar/domain/calendar_event.dart';

void main() {
  final monday = DateTime(2026, 6, 1, 8); // a Monday, 8 AM local

  CalendarEvent maths({DateTime? until}) => CalendarEvent(
    id: 'c1',
    kind: CalendarKind.classSession,
    title: 'Maths',
    startsAt: monday,
    endsAt: monday.add(const Duration(minutes: 45)),
    weekly: true,
    repeatUntil: until,
    reminders: const [15],
  );

  group('occurrences', () {
    test('a weekly class happens every week at the same time', () {
      final found = occurrencesBetween([maths()], DateTime(2026, 6, 10), DateTime(2026, 6, 30));
      expect(found.map((o) => o.start), [DateTime(2026, 6, 15, 8), DateTime(2026, 6, 22, 8), DateTime(2026, 6, 29, 8)]);
      expect(found.first.end, DateTime(2026, 6, 15, 8, 45));
    });

    test('a weekly class stops after its last date', () {
      final found = occurrencesBetween(
        [maths(until: DateTime(2026, 6, 16))],
        DateTime(2026, 6, 1),
        DateTime(2026, 7, 1),
      );
      expect(found, hasLength(3));
    });

    test('a holiday week shows on every day it covers', () {
      final eid = CalendarEvent(
        kind: CalendarKind.holiday,
        title: 'Eid break',
        startsAt: DateTime(2026, 6, 25),
        endsAt: DateTime(2026, 6, 30, 23, 59),
        allDay: true,
      );
      final june = occurrencesBetween([eid], DateTime(2026, 6), DateTime(2026, 7));
      expect(june.single.onDay(DateTime(2026, 6, 27)), isTrue);
      expect(june.single.onDay(DateTime(2026, 7, 1)), isFalse);
      // Still found when the range starts in the middle of it.
      expect(occurrencesBetween([eid], DateTime(2026, 6, 28), DateTime(2026, 6, 29)), hasLength(1));
    });
  });

  group('reminders', () {
    test('plans each reminder before each occurrence, soonest first', () {
      final exam = CalendarEvent(
        id: 'e1',
        kind: CalendarKind.exam,
        title: 'Physics',
        startsAt: DateTime(2026, 6, 10, 10),
        reminders: const [1440, 60],
        location: 'Hall 2',
      );
      final plan = planReminders([exam, maths()], DateTime(2026, 6, 1, 9));
      final examReminders = plan.where((r) => r.title == 'Exam: Physics').toList();
      expect(examReminders.map((r) => r.at), [DateTime(2026, 6, 9, 10), DateTime(2026, 6, 10, 9)]);
      expect(examReminders.first.body, 'Tomorrow at 10:00 AM · Hall 2');
      expect(examReminders.last.body, 'In 1 hour at 10:00 AM · Hall 2');
      // The class's first reminder (7:45 today) has passed; the next is a week later.
      expect(plan.where((r) => r.title == 'Class: Maths').first.at, DateTime(2026, 6, 8, 7, 45));
      expect(plan.map((r) => r.at).toList(), [...plan.map((r) => r.at)]..sort());
    });

    test('ids are stable, so rescheduling replaces instead of duplicating', () {
      final now = DateTime(2026, 6, 1);
      expect(planReminders([maths()], now).map((r) => r.id), planReminders([maths()], now).map((r) => r.id));
      expect(planReminders([maths()], now).map((r) => r.id).toSet(), hasLength(planReminders([maths()], now).length));
    });

    test('never schedules more than the phone allows', () {
      final daily = [
        for (var i = 0; i < 20; i++)
          CalendarEvent(
            id: 'c$i',
            kind: CalendarKind.classSession,
            title: 'Class $i',
            startsAt: monday.add(Duration(hours: i % 8)),
            weekly: true,
            reminders: const [15, 0],
          ),
      ];
      expect(planReminders(daily, DateTime(2026, 6, 1)), hasLength(maxScheduledReminders));
    });

    test('kinds bring sensible default reminders', () {
      expect(CalendarKind.exam.defaultReminders, [1440, 60]);
      expect(CalendarKind.holiday.defaultReminders, isEmpty);
      expect(CalendarKind.fromApi('CLASS'), CalendarKind.classSession);
    });
  });
}
