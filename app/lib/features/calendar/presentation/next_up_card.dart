import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../application/calendar_controller.dart';
import '../domain/calendar_event.dart';
import 'calendar_widgets.dart';

/// On home: the next exam (with a countdown) and today's remaining classes.
/// Hidden until the calendar has something coming up.
class NextUpCard extends ConsumerWidget {
  const NextUpCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(calendarProvider).value ?? const [];
    if (events.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final endOfDay = DateTime(now.year, now.month, now.day + 1);
    final nextExam = occurrencesBetween(
      events.where((e) => e.kind == CalendarKind.exam).toList(),
      now,
      now.add(const Duration(days: 120)),
    ).firstOrNull;
    final todaysClasses = occurrencesBetween(
      events.where((e) => e.kind == CalendarKind.classSession).toList(),
      now,
      endOfDay,
    );
    if (nextExam == null && todaysClasses.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: ClayCard(
        glow: AppColors.coralDeep,
        padding: const EdgeInsets.all(16),
        onTap: () => context.push(Routes.calendar),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (nextExam != null)
              Row(
                children: [
                  IconBadge(Icons.quiz_rounded, size: 48, color: AppColors.coralDeep),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Next exam · ${relativeDay(nextExam.start, now)}',
                          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.coralDeep),
                        ),
                        Text(
                          nextExam.event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.ink),
                        ),
                        Text(
                          occurrenceTime(nextExam),
                          style: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
                ],
              ),
            if (nextExam != null && todaysClasses.isNotEmpty) Divider(height: 24, color: AppColors.line),
            if (todaysClasses.isNotEmpty) ...[
              Text(
                'Classes today',
                style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.violet),
              ),
              const SizedBox(height: 6),
              for (final c in todaysClasses.take(3))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.school_rounded, size: 18, color: AppColors.violet),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          c.event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                      ),
                      Text(
                        formatTime(c.start),
                        style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
