import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../../../core/widgets/pencil_3d.dart';
import '../../auth/application/auth_controller.dart';
import 'home_widgets.dart';

class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthSignedIn) return const SizedBox.shrink();
    final user = auth.user;
    final text = Theme.of(context).textTheme;

    return PageShell(
      showBack: false,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeHeader(greeting: 'Hi ${user.firstName}! 👋', subtitle: 'Ready to learn something today?'),
          const SizedBox(height: 22),
          ClayCard(
            color: AppColors.violet,
            glow: AppColors.violetDeep,
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
                        height: 50,
                        color: AppColors.sunshine,
                        edgeColor: AppColors.sunshineDeep,
                        foreground: AppColors.ink,
                        onPressed: () => showSnack(context, 'Study sessions arrive in the next update ✨'),
                      ),
                    ],
                  ),
                ),
                const Pencil3D(size: 120, interactive: false),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text('Your toolkit', style: text.titleLarge),
          const SizedBox(height: 12),
          FeatureGrid(
            children: [
              const FeatureTile(
                emoji: '⏱️',
                title: 'Study timer',
                subtitle: 'See how long you studied',
                color: AppColors.mint,
              ),
              const FeatureTile(
                emoji: '🔒',
                title: 'App lock',
                subtitle: 'Block apps while you study',
                color: AppColors.violet,
              ),
              const FeatureTile(
                emoji: '📝',
                title: 'Exams',
                subtitle: 'Pass to unlock your apps',
                color: AppColors.sunshineDeep,
              ),
              const FeatureTile(
                emoji: '🤖',
                title: 'AI helper',
                subtitle: 'Ask anything about your lesson',
                color: AppColors.sky,
              ),
              FeatureTile(
                emoji: '🏡',
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
