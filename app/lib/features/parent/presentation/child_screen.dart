import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/choice_controls.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../../study/domain/study_session.dart';
import '../../study/presentation/stats_screen.dart';
import '../application/parent_providers.dart';
import '../domain/parent_models.dart';

/// Everything a parent can see and do for one child.
class ChildScreen extends ConsumerWidget {
  const ChildScreen({super.key, required this.childId});

  final String childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(childDetailProvider(childId));
    return PageShell(
      title: detail.value?.summary.firstName ?? 'Your child',
      child: detail.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Column(
          children: [
            MessageBanner.error(e is ApiException ? e.message : 'Could not load this child.'),
            const SizedBox(height: 12),
            Button3D.secondary(label: 'Try again', onPressed: () => ref.invalidate(childDetailProvider(childId))),
          ],
        ),
        data: (d) => _Body(d),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.d);

  final ChildDetail d;

  Future<void> _lift(BuildContext context, WidgetRef ref, ParentLock lock) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lift this lock?'),
        content: Text('"${lock.title}" unlocks right away, without an exam.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lift lock')),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    try {
      await ref.read(parentApiProvider).cancelLock(lock.id);
      ref
        ..invalidate(childDetailProvider(d.summary.id))
        ..invalidate(childrenProvider);
      if (context.mounted) showSnack(context, 'Lock lifted.');
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final s = d.summary;
    final session = s.activeSession;
    final today = d.screenTime.isEmpty ? null : d.screenTime.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClayCard(
          glow: AppColors.sky,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(Icons.backpack_rounded, size: 56, color: AppColors.sky),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: text.titleLarge),
                        Text('${s.age} years old', style: text.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _Number(formatMinutes(s.todayStudyMinutes), 'Studied today', AppColors.mintDeep),
                  _Number(formatMinutes(s.todayScreenMinutes), 'Phone today', AppColors.skyDeep),
                  _Number('${s.streakDays}', 'Day streak', AppColors.coralDeep),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ProtectionCard(s),
        if (session != null) ...[
          const SizedBox(height: 12),
          MessageBanner.info(
            session.status == SessionStatus.studying
                ? 'Studying ${session.subject} now, until ${TimeOfDay.fromDateTime(session.endsAt).format(context)}.'
                : 'Finished studying ${session.subject}. The exam is next.',
          ),
        ],
        const SizedBox(height: 24),
        Text('Locks you set', style: text.titleLarge),
        const SizedBox(height: 4),
        Text('Apps stay locked until ${s.firstName} passes the exam.', style: text.bodyMedium),
        const SizedBox(height: 12),
        if (s.activeLocks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('No locks right now.', style: text.bodyMedium),
          ),
        for (final lock in s.activeLocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LockCard(
              lock,
              appLabels: {for (final a in d.installedApps) a.package: a.label},
              onLift: () => _lift(context, ref, lock),
            ),
          ),
        Button3D(
          label: 'Lock apps',
          icon: Icons.lock_rounded,
          onPressed: () => context.push('${Routes.child(s.id)}/lock'),
        ),
        const SizedBox(height: 26),
        Text('Phone time', style: text.titleLarge),
        const SizedBox(height: 12),
        ClayCard(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: d.screenTime.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('No phone time reported yet.', style: text.bodyMedium),
                )
              : WeekBars(days: _week(d.screenTime), height: 120),
        ),
        if (today != null && today.apps.isNotEmpty) ...[
          const SizedBox(height: 12),
          ClayCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Most used today', style: text.titleMedium),
                const SizedBox(height: 6),
                for (final app in today.apps.take(6)) _AppRow(app.label, app.minutes, today.apps.first.minutes),
              ],
            ),
          ),
        ],
        const SizedBox(height: 26),
        Text('Study time', style: text.titleLarge),
        const SizedBox(height: 12),
        ClayCard(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: WeekBars(days: d.stats.week, height: 120),
        ),
        const SizedBox(height: 26),
        Text('Exams', style: text.titleLarge),
        const SizedBox(height: 12),
        if (d.recentExams.isEmpty) Text('No exams yet.', style: text.bodyMedium),
        for (final exam in d.recentExams) _ExamRow(exam),
      ],
    );
  }

  /// Seven local days, oldest first, with missing days as zero.
  static List<({DateTime day, int minutes})> _week(List<ScreenTimeDay> days) {
    final byDay = {for (final d in days) d.day: d.totalMinutes};
    final now = DateTime.now();
    return [
      for (var i = 6; i >= 0; i--)
        if (DateTime(now.year, now.month, now.day - i) case final day) (day: day, minutes: byDay[day] ?? 0),
    ];
  }
}

class _Number extends StatelessWidget {
  const _Number(this.value, this.label, this.color);

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: color),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _ProtectionCard extends StatelessWidget {
  const _ProtectionCard(this.s);

  final ChildSummary s;

  @override
  Widget build(BuildContext context) {
    final p = s.protection;
    final help = switch (p) {
      Protection.on => 'Locks work on ${s.firstName}’s phone.',
      Protection.off =>
        'App lock is switched off on ${s.firstName}’s phone, so locks cannot work. Ask them to turn it on.',
      Protection.shortcutOn =>
        'The accessibility shortcut is on, so App lock could be switched off quickly. Ask ${s.firstName} to turn the shortcut off.',
      Protection.stale => 'The phone has not checked in for a while. It may be off or offline.',
      Protection.noPhone => '${s.firstName} has not opened Study Assistant on a phone yet.',
    };
    return p.ok ? MessageBanner.success(help) : MessageBanner.error(help);
  }
}

class _LockCard extends StatelessWidget {
  const _LockCard(this.lock, {required this.appLabels, required this.onLift});

  final ParentLock lock;
  final Map<String, String> appLabels;
  final VoidCallback onLift;

  @override
  Widget build(BuildContext context) {
    final apps = lock.wholePhone
        ? 'The whole phone'
        : [for (final p in lock.lockedApps) appLabels[p] ?? p.split('.').last].join(', ');
    return ClayCard(
      glow: AppColors.sunshineDeep,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(Icons.lock_rounded, size: 44, color: AppColors.sunshineDeep),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lock.title, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      '${lock.subject} · pass ${lock.exam.passMarks}/${lock.exam.totalMarks}'
                      '${lock.questionSetId != null ? ' · your questions' : ''}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            apps,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onLift,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Lift lock'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow(this.label, this.minutes, this.most);

  final String label;
  final int minutes;
  final int most;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: most == 0 ? 0 : minutes / most,
                minHeight: 10,
                color: AppColors.skyDeep,
                backgroundColor: AppColors.line,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              formatMinutes(minutes),
              textAlign: TextAlign.right,
              style: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamRow extends StatelessWidget {
  const _ExamRow(this.exam);

  final ExamSummary exam;

  @override
  Widget build(BuildContext context) {
    final score = exam.score;
    final scoreText = score == null
        ? '–'
        : (score == score.roundToDouble() ? '${score.toInt()}' : score.toStringAsFixed(1));
    final l = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClayCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            IconBadge(
              exam.passed ? Icons.emoji_events_rounded : Icons.replay_rounded,
              size: 42,
              color: exam.passed ? AppColors.sunshineDeep : AppColors.inkSoft,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exam.subject, style: Theme.of(context).textTheme.titleMedium),
                  Text(l.formatMediumDate(exam.createdAt), style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Text(
              '$scoreText/${exam.totalMarks}',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                color: exam.passed ? AppColors.mintDeep : AppColors.coralDeep,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
