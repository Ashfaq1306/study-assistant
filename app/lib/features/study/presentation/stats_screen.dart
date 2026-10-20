import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/choice_controls.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../application/study_providers.dart';
import '../domain/study_session.dart';

/// How much the student studied: today, streak, this week, and past sessions.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(studyStatsProvider);
    final history = ref.watch(studyHistoryProvider);
    final text = Theme.of(context).textTheme;

    return PageShell(
      title: 'My study time',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          stats.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => MessageBanner.error(e is ApiException ? e.message : 'Could not load your stats.'),
            data: (s) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        icon: Icons.today_rounded,
                        value: formatMinutes(s.todayMinutes),
                        label: 'Today',
                        color: AppColors.violet,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatTile(
                        icon: Icons.local_fire_department_rounded,
                        value: '${s.streakDays}',
                        label: s.streakDays == 1 ? 'Day streak' : 'Days streak',
                        color: AppColors.coralDeep,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatTile(
                        icon: Icons.emoji_events_rounded,
                        value: '${s.sessionsCompleted}',
                        label: 'Exams passed',
                        color: AppColors.sunshineDeep,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ClayCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('This week', style: text.titleMedium),
                      Text(
                        '${formatMinutes(s.week.fold(0, (sum, d) => sum + d.minutes))} studied',
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      WeekBars(days: s.week),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Past sessions', style: text.titleLarge),
          const SizedBox(height: 12),
          history.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => MessageBanner.error(e is ApiException ? e.message : 'Could not load your sessions.'),
            data: (items) => items.isEmpty
                ? const MessageBanner.info('No sessions yet. Start one from home!')
                : Column(
                    children: [
                      for (final s in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SessionTile(session: s),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

String formatMinutes(int minutes) => minutes < 60 ? '${minutes}m' : '${minutes ~/ 60}h ${minutes % 60}m';

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.value, required this.label, required this.color});

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClayCard(
      glow: color,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      child: Column(
        children: [
          IconBadge(icon, size: 40, color: color),
          const SizedBox(height: 8),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.ink),
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

class SessionTile extends StatelessWidget {
  const SessionTile({super.key, required this.session});

  final StudySession session;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (session.status) {
      SessionStatus.passed => ('Passed', AppColors.mintDeep, Icons.verified_rounded),
      SessionStatus.examPending => ('Exam waiting', AppColors.sunshineDeep, Icons.hourglass_top_rounded),
      SessionStatus.studying => ('Studying', AppColors.violet, Icons.timer_rounded),
      SessionStatus.cancelled => ('Cancelled', AppColors.inkFaint, Icons.block_rounded),
    };
    final d = session.startedAt.toLocal();
    return ClayCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          IconBadge(icon, size: 44, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.subject, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '${session.topics} · ${formatMinutes(session.studiedMinutes)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  '${d.day}/${d.month}/${d.year}',
                  style: TextStyle(fontSize: 12, color: AppColors.inkFaint, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
