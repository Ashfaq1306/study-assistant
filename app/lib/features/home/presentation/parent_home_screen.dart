import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../../auth/application/auth_controller.dart';
import '../../parent/application/parent_providers.dart';
import '../../parent/domain/parent_models.dart';
import '../../study/presentation/stats_screen.dart';
import '../../updates/update_card.dart';
import 'home_widgets.dart';

/// A parent's home: each child at a glance, alerts, and the parent tools.
class ParentHomeScreen extends ConsumerWidget {
  const ParentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthSignedIn) return const SizedBox.shrink();
    final children = ref.watch(childrenProvider);
    final unread = ref.watch(notificationsProvider).value?.unread ?? 0;
    final text = Theme.of(context).textTheme;

    return PageShell(
      showBack: false,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeHeader(greeting: 'Hi ${auth.user.firstName}!', subtitle: "Let's help your child shine."),
          const UpdateCard(),
          const SizedBox(height: 16),
          _AlertsBar(unread: unread),
          const SizedBox(height: 22),
          Text('Your children', style: text.titleLarge),
          const SizedBox(height: 12),
          children.when(
            loading: () => const Center(
              child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
            ),
            error: (e, _) => MessageBanner.error(e is ApiException ? e.message : 'Could not load your children.'),
            data: (items) => items.isEmpty
                ? const _NoChildren()
                : Column(
                    children: [
                      for (final child in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _ChildCard(child, onTap: () => context.push(Routes.child(child.id))),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          Button3D(
            label: 'Add a child',
            icon: Icons.qr_code_scanner_rounded,
            color: AppColors.mint,
            edgeColor: AppColors.mintDeep,
            onPressed: () => context.push(Routes.addChild),
          ),
          const SizedBox(height: 26),
          Text('Parent tools', style: text.titleLarge),
          const SizedBox(height: 12),
          FeatureGrid(
            children: [
              FeatureTile(
                icon: Icons.quiz_rounded,
                title: 'Your questions',
                subtitle: 'Write the quiz that unlocks a lock',
                color: AppColors.sunshineDeep,
                onTap: () => context.push(Routes.questionSets),
              ),
              FeatureTile(
                icon: Icons.notifications_active_rounded,
                title: 'Alerts',
                subtitle: unread == 0 ? 'Exams, locks and app-lock status' : '$unread new',
                color: AppColors.coral,
                onTap: () => context.push(Routes.parentAlerts),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertsBar extends StatelessWidget {
  const _AlertsBar({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    if (unread == 0) return const SizedBox.shrink();
    return ClayCard(
      color: AppColors.coralSoft,
      glow: AppColors.coralDeep,
      padding: const EdgeInsets.all(14),
      onTap: () => context.push(Routes.parentAlerts),
      child: Row(
        children: [
          Icon(Icons.notifications_active_rounded, color: AppColors.coralDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              unread == 1 ? '1 new alert' : '$unread new alerts',
              style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.coralDeep),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.coralDeep),
        ],
      ),
    );
  }
}

class _NoChildren extends StatelessWidget {
  const _NoChildren();

  @override
  Widget build(BuildContext context) {
    return ClayCard(
      child: Column(
        children: [
          IconBadge(Icons.child_care_rounded, size: 64, color: AppColors.sky),
          const SizedBox(height: 8),
          Text('No child linked yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            "Open Study Assistant on your child's phone. It shows a QR code: tap \"Add a child\" and scan it.",
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard(this.child, {required this.onTap});

  final ChildSummary child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final session = child.activeSession;
    return ClayCard(
      glow: child.protection.ok ? AppColors.sky : AppColors.coralDeep,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(Icons.backpack_rounded, size: 52, color: AppColors.sky),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(child.name, style: text.titleMedium),
                    Text('${child.age} years old', style: text.bodyMedium),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Mini(
                icon: Icons.menu_book_rounded,
                value: formatMinutes(child.todayStudyMinutes),
                label: 'Studied',
                color: AppColors.mintDeep,
              ),
              _Mini(
                icon: Icons.smartphone_rounded,
                value: formatMinutes(child.todayScreenMinutes),
                label: 'Screen',
                color: AppColors.skyDeep,
              ),
              _Mini(
                icon: Icons.local_fire_department_rounded,
                value: '${child.streakDays}',
                label: 'Streak',
                color: AppColors.coralDeep,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StatusLine(
            icon: child.protection.ok ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded,
            color: child.protection.ok ? AppColors.mintDeep : AppColors.coralDeep,
            text: child.protection.label,
          ),
          if (session != null)
            _StatusLine(
              icon: Icons.timer_rounded,
              color: AppColors.violet,
              text: session.status.name == 'studying'
                  ? 'Studying ${session.subject} now'
                  : '${session.subject} exam waiting',
            ),
          for (final lock in child.activeLocks)
            _StatusLine(icon: Icons.lock_rounded, color: AppColors.sunshineDeep, text: 'Locked: ${lock.title}'),
          if (child.lastExam case final exam?)
            _StatusLine(
              icon: exam.passed ? Icons.emoji_events_rounded : Icons.replay_rounded,
              color: exam.passed ? AppColors.sunshineDeep : AppColors.inkSoft,
              text: '${exam.passed ? 'Passed' : 'Tried'} ${exam.subject}: ${_score(exam.score)}/${exam.totalMarks}',
            ),
        ],
      ),
    );
  }

  static String _score(double? v) => v == null ? '–' : (v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1));
}

class _Mini extends StatelessWidget {
  const _Mini({required this.icon, required this.value, required this.label, required this.color});

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.ink),
          ),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
