import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../app/routes.dart';
import '../../auth/application/auth_controller.dart';

/// Greeting row with the logo and an account menu.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key, required this.greeting, required this.subtitle});

  final String greeting;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        const AppLogo(size: 58),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting, style: text.headlineSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(subtitle, style: text.bodyMedium),
            ],
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Account',
          icon: CircleAvatar(
            backgroundColor: AppColors.card,
            child: Icon(Icons.person_rounded, color: AppColors.violet),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          onSelected: (value) {
            if (value == 'logout') ref.read(authControllerProvider.notifier).logout();
            if (value == 'appearance') context.push(Routes.appearance);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'appearance',
              child: ListTile(leading: Icon(Icons.palette_rounded), title: Text('Appearance')),
            ),
            PopupMenuItem(
              value: 'logout',
              child: ListTile(leading: Icon(Icons.logout_rounded), title: Text('Sign out')),
            ),
          ],
        ),
      ],
    );
  }
}

/// Square feature tile. Features that are not built yet show a "Soon" tag.
class FeatureTile extends StatelessWidget {
  const FeatureTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  /// Null means "coming soon".
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final soon = onTap == null;
    return ClayCard(
      glow: color,
      padding: const EdgeInsets.all(16),
      onTap: onTap ?? () => showSnack(context, '$title is coming in the next update'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon, size: 46, color: color),
              const Spacer(),
              if (soon)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.sunshineSoft, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    'Soon',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.sunshineDeep),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13), maxLines: 2),
        ],
      ),
    );
  }
}

/// Two-column grid that keeps tiles the same height.
class FeatureGrid extends StatelessWidget {
  const FeatureGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: 14),
                Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}
