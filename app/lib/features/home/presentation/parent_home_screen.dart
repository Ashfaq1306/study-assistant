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
import '../../family/application/family_providers.dart';
import '../../family/data/family_api.dart';
import 'home_widgets.dart';

class ParentHomeScreen extends ConsumerWidget {
  const ParentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthSignedIn) return const SizedBox.shrink();
    final children = ref.watch(familyLinksProvider);
    final text = Theme.of(context).textTheme;

    return PageShell(
      showBack: false,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeHeader(greeting: 'Hi ${auth.user.firstName}! 🌷', subtitle: "Let's help your child shine."),
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
                        Padding(padding: const EdgeInsets.only(bottom: 12), child: _ChildCard(child)),
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
          const FeatureGrid(
            children: [
              FeatureTile(
                emoji: '📊',
                title: 'Screen time',
                subtitle: 'See daily phone and study time',
                color: AppColors.sky,
              ),
              FeatureTile(
                emoji: '🔒',
                title: 'Block apps',
                subtitle: 'Lock apps or the whole phone',
                color: AppColors.violet,
              ),
              FeatureTile(
                emoji: '📝',
                title: 'Set quizzes',
                subtitle: 'Write questions for your child',
                color: AppColors.sunshineDeep,
              ),
              FeatureTile(emoji: '🔔', title: 'Alerts', subtitle: 'Know when a quiz is passed', color: AppColors.coral),
            ],
          ),
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
          const Text('🧒', style: TextStyle(fontSize: 48)),
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
  const _ChildCard(this.link);

  final FamilyLink link;

  @override
  Widget build(BuildContext context) {
    return ClayCard(
      glow: AppColors.sky,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const EmojiBadge('🎒', size: 52, color: AppColors.skySoft),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(link.personName, style: Theme.of(context).textTheme.titleMedium),
                Text('${link.personAge} years old', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const Icon(Icons.verified_rounded, color: AppColors.mintDeep),
        ],
      ),
    );
  }
}
