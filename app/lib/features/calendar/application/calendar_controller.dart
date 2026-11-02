import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/calendar_api.dart';
import '../domain/calendar_event.dart';
import 'reminders.dart';

final calendarApiProvider = Provider<CalendarApi>((ref) => CalendarApi(ref.watch(apiClientProvider)));

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) => ReminderScheduler());

final calendarProvider = AsyncNotifierProvider<CalendarController, List<CalendarEvent>>(CalendarController.new);

/// The signed-in account's calendar. Every change reschedules the phone's reminders.
class CalendarController extends AsyncNotifier<List<CalendarEvent>> {
  CalendarApi get _api => ref.read(calendarApiProvider);

  @override
  Future<List<CalendarEvent>> build() async {
    final userId = ref.watch(authControllerProvider.select((s) => s is AuthSignedIn ? s.user.id : null));
    if (userId == null) {
      unawaited(ref.read(reminderSchedulerProvider).clear().catchError((_) {}));
      return const [];
    }
    final events = await _api.list();
    _reschedule(events);
    return events;
  }

  Future<void> refresh() async {
    final events = await _api.list();
    state = AsyncData(events);
    _reschedule(events);
  }

  Future<CalendarEvent> save(CalendarEvent event) async {
    final saved = event.id == null ? await _api.create(event) : await _api.update(event);
    await refresh();
    return saved;
  }

  Future<void> saveAll(List<CalendarEvent> events) async {
    await _api.saveAll(events);
    await refresh();
  }

  Future<void> delete(CalendarEvent event) async {
    await _api.delete(event.id!);
    await refresh();
  }

  void _reschedule(List<CalendarEvent> events) =>
      unawaited(ref.read(reminderSchedulerProvider).scheduleAll(events).catchError((_) => 0));
}
