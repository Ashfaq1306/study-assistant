import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../../../core/widgets/pencil_3d.dart';
import '../../app_lock/application/app_lock_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../../study/application/study_providers.dart';
import '../../study/domain/study_session.dart';
import '../../study/presentation/stats_screen.dart';
import 'home_widgets.dart';
import '../../updates/update_card.dart';

class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthSignedIn) return const SizedBox.shrink();
    final user = auth.user;
    final text = Theme.of(context).textTheme;
    final activeAsync = ref.watch(activeSessionProvider);
    final active = activeAsync.value;
    final stats = ref.watch(studyStatsProvider).value;
    final announcement = ref.watch(remoteConfigProvider).value?.announcement;

    return PageShell(
      showBack: false,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeHeader(greeting: 'Hi ${user.firstName}!', subtitle: 'Ready to learn something today?'),
          const UpdateCard(),
          if (announcement != null && announcement.isNotEmpty) ...[
            const SizedBox(height: 16),
            MessageBanner.info(announcement),
          ],
          const SizedBox(height: 22),
          if (activeAsync.hasError && active == null) ...[
            _RetryBanner(onRetry: () => ref.invalidate(activeSessionProvider)),
            const SizedBox(height: 14),
          ],
          if (active != null && active.status.isActive)
            _ActiveCard(session: active)
          else
            _StartCard(onStart: () => context.push(Routes.studyNew)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.today_rounded,
                  value: formatMinutes(stats?.todayMinutes ?? 0),
                  label: 'Today',
                  color: AppColors.violet,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  icon: Icons.local_fire_department_rounded,
                  value: '${stats?.streakDays ?? 0}',
                  label: 'Day streak',
                  color: AppColors.coralDeep,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  icon: Icons.emoji_events_rounded,
                  value: '${stats?.sessionsCompleted ?? 0}',
                  label: 'Exams passed',
                  color: AppColors.sunshineDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text('Your toolkit', style: text.titleLarge),
          const SizedBox(height: 12),
          FeatureGrid(
            children: [
              FeatureTile(
                icon: Icons.insights_rounded,
                title: 'Study time',
                subtitle: 'Your week and past sessions',
                color: AppColors.mintDeep,
                onTap: () => context.push(Routes.stats),
              ),
              FeatureTile(
                icon: Icons.lock_rounded,
                title: 'App lock',
                subtitle: switch (ref.watch(appLockProvider).value) {
                  final s? when !s.supported => 'Needs an Android phone',
                  final s? when s.protectionOn => 'On: ready to lock apps',
                  _ => 'Off: tap to turn it on',
                },
                color: AppColors.violet,
                onTap: () => context.push(Routes.appLock),
              ),
              FeatureTile(
                icon: Icons.smart_toy_rounded,
                title: 'AI helper',
                subtitle: 'Ask anything about your lesson',
                color: AppColors.sky,
                onTap: () => context.push(Routes.tutor),
              ),
              FeatureTile(
                icon: Icons.family_restroom_rounded,
                title: 'Family',
                subtitle: user.linkedParents == 0 ? 'Link a parent (optional)' : '${user.linkedParents} parent linked',
                color: AppColors.coral,
                onTap: () => context.push(Routes.family),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RetryBanner extends StatelessWidget {
  const _RetryBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.coralSoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onRetry,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: AppColors.coralDeep),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Couldn't check your study session. Tap to try again.",
                  style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.coralDeep),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ClayCard(
      color: AppColors.hero,
      glow: AppColors.hero,
      padding: const EdgeInsets.fromLTRB(22, 18, 12, 22),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Today's focus", style: text.titleMedium?.copyWith(color: Colors.white70)),
                const SizedBox(height: 4),
                Text(
                  'Pick a subject, lock distractions, pass the quiz.',
                  style: text.titleLarge?.copyWith(color: Colors.white, height: 1.2),
                ),
                const SizedBox(height: 16),
                Button3D(
                  label: 'Start studying',
                  icon: Icons.play_arrow_rounded,
                  height: 50,
                  color: AppColors.sunshine,
                  edgeColor: AppColors.sunshineDeep,
                  foreground: AppColors.onBright,
                  onPressed: onStart,
                ),
              ],
            ),
          ),
          const Pencil3D(size: 120, interactive: false),
        ],
      ),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.session});

  final StudySession session;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pending = session.status == SessionStatus.examPending;
    final color = pending ? AppColors.sunshineDeep : AppColors.mintDeep;
    return ClayCard(
      glow: color,
      onTap: () => context.push(Routes.studySession),
      child: Row(
        children: [
          IconBadge(pending ? Icons.quiz_rounded : Icons.timer_rounded, size: 60, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pending ? 'Exam waiting' : 'Studying now', style: text.titleMedium?.copyWith(color: color)),
                Text(session.subject, style: text.titleLarge),
                Text(pending ? 'Pass it to unlock your apps' : 'Tap to see your timer', style: text.bodyMedium),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: color, size: 32),
        ],
      ),
    );
  }
}
