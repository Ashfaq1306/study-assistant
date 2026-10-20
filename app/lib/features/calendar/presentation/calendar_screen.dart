import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../application/calendar_controller.dart';
import '../domain/calendar_event.dart';
import 'calendar_widgets.dart';

/// Whether reminders can show, and on the minute.
final reminderAccessProvider = FutureProvider.autoDispose<({bool allowed, bool exact})>((ref) async {
  final scheduler = ref.watch(reminderSchedulerProvider);
  return (allowed: await scheduler.requestPermission(), exact: await scheduler.canBeExact());
});

/// The calendar: a month of exams, classes, deadlines and holidays, the chosen
/// day's agenda, and what's coming up next.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _month = DateTime.now();
  DateTime _selected = DateUtils.dateOnly(DateTime.now());

  void _shiftMonth(int by) => setState(() => _month = DateTime(_month.year, _month.month + by));

  void _edit([CalendarEvent? event]) => context.push(
    Routes.calendarEdit,
    extra: event ?? CalendarEvent(kind: CalendarKind.exam, title: '', startsAt: _defaultStart()),
  );

  DateTime _defaultStart() => DateTime(_selected.year, _selected.month, _selected.day, 10);

  @override
  Widget build(BuildContext context) {
    final calendar = ref.watch(calendarProvider);
    final access = ref.watch(reminderAccessProvider).value;
    final text = Theme.of(context).textTheme;

    return PageShell(
      title: 'Calendar',
      actions: [
        IconButton(
          tooltip: 'Import academic calendar',
          icon: Icon(Icons.auto_awesome_rounded, color: AppColors.violet),
          onPressed: () => context.push(Routes.calendarImport),
        ),
      ],
      child: calendar.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => MessageBanner.error(e is ApiException ? e.message : "Couldn't load your calendar."),
        data: (events) {
          final monthStart = DateTime(_month.year, _month.month);
          final monthEnd = DateTime(_month.year, _month.month + 1);
          final inMonth = occurrencesBetween(events, monthStart, monthEnd);
          final dayItems = inMonth.where((o) => o.onDay(_selected)).toList();
          final now = DateTime.now();
          final upcoming = occurrencesBetween(
            events.where((e) => e.kind == CalendarKind.exam || e.kind == CalendarKind.assignment).toList(),
            now,
            now.add(const Duration(days: 60)),
          ).take(4).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (access != null && !access.allowed) ...[
                ClayCard(
                  color: AppColors.coralSoft,
                  glow: AppColors.coralDeep,
                  padding: const EdgeInsets.all(14),
                  onTap: () => ref.invalidate(reminderAccessProvider),
                  child: Row(
                    children: [
                      Icon(Icons.notifications_off_rounded, color: AppColors.coralDeep),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Reminders are off. Tap to allow notifications so you never miss an exam.',
                          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.coralDeep),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ] else if (access != null && !access.exact) ...[
                ClayCard(
                  color: AppColors.skySoft,
                  glow: AppColors.skyDeep,
                  padding: const EdgeInsets.all(14),
                  onTap: () async {
                    await ref.read(reminderSchedulerProvider).requestExact();
                    ref.invalidate(reminderAccessProvider);
                  },
                  child: Row(
                    children: [
                      Icon(Icons.alarm_rounded, color: AppColors.skyDeep),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'For on-the-minute class reminders, tap and allow "Alarms & reminders".',
                          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.skyDeep),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (events.isEmpty) ...[_EmptyState(onAdd: _edit), const SizedBox(height: 18)],
              ClayCard(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous month',
                          icon: const Icon(Icons.chevron_left_rounded),
                          onPressed: () => _shiftMonth(-1),
                        ),
                        Expanded(
                          child: Text(
                            DateFormat('MMMM yyyy').format(_month),
                            textAlign: TextAlign.center,
                            style: text.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next month',
                          icon: const Icon(Icons.chevron_right_rounded),
                          onPressed: () => _shiftMonth(1),
                        ),
                      ],
                    ),
                    MonthGrid(
                      month: _month,
                      selected: _selected,
                      occurrences: inMonth,
                      onSelect: (d) => setState(() => _selected = d),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: Text(relativeDay(_selected, now), style: text.titleLarge)),
                  Text(formatDay(_selected), style: text.bodyMedium),
                ],
              ),
              const SizedBox(height: 10),
              if (dayItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('Nothing planned. A good day to revise!', style: text.bodyMedium),
                )
              else
                for (final o in dayItems) OccurrenceTile(occurrence: o, onTap: () => _edit(o.event)),
              const SizedBox(height: 8),
              Button3D(label: 'Add to calendar', icon: Icons.add_rounded, onPressed: _edit),
              if (upcoming.isNotEmpty) ...[
                const SizedBox(height: 26),
                Text('Coming up', style: text.titleLarge),
                const SizedBox(height: 10),
                for (final o in upcoming)
                  OccurrenceTile(
                    occurrence: o,
                    onTap: () => _edit(o.event),
                    showDate: true,
                    trailing: _CountdownChip(o.start, now),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CountdownChip extends StatelessWidget {
  const _CountdownChip(this.at, this.now);

  final DateTime at;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(20)),
      child: Text(
        relativeDay(at, now),
        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.coralDeep),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ClayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: IconBadge(Icons.calendar_month_rounded, size: 72)),
          const SizedBox(height: 12),
          Text(
            'Add your exams and classes',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Upload your school or university calendar and the AI fills it in for you, with reminders.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Button3D(
            label: 'Import my academic calendar',
            icon: Icons.auto_awesome_rounded,
            onPressed: () => context.push(Routes.calendarImport),
          ),
          const SizedBox(height: 10),
          Button3D.secondary(label: 'Add one myself', icon: Icons.edit_calendar_rounded, onPressed: onAdd),
        ],
      ),
    );
  }
}
