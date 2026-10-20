import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/float_in.dart';
import '../../../core/widgets/mascot_stage.dart';
import '../../../core/widgets/page_shell.dart';

/// The first screen: the 3D pencil on its stage with friends orbiting it, then
/// the promise and the way in, floating up one after another.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PageShell(
      showBack: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          FloatIn(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const AppLogo(size: 40),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(AppConfig.appName, style: text.titleLarge, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          const FloatIn(
            delay: Duration(milliseconds: 100),
            offset: 40,
            child: Center(child: MascotStage(size: 290)),
          ),
          FloatIn(
            delay: const Duration(milliseconds: 220),
            child: Text(
              'Study smart.\nUnlock by learning.',
              textAlign: TextAlign.center,
              style: text.displaySmall?.copyWith(fontSize: 34, height: 1.1),
            ),
          ),
          const SizedBox(height: 12),
          FloatIn(
            delay: const Duration(milliseconds: 340),
            child: Text(
              'Pick what you will study, lock distracting apps, and win them back by passing a quick quiz.',
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
            ),
          ),
          const SizedBox(height: 20),
          FloatIn(
            delay: const Duration(milliseconds: 460),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(Icons.lock_rounded, 'Lock apps', AppColors.violet),
                _Chip(Icons.psychology_rounded, 'AI quizzes', AppColors.sunshineDeep),
                _Chip(Icons.timer_rounded, 'Study timer', AppColors.mintDeep),
                _Chip(Icons.family_restroom_rounded, 'Family', AppColors.coralDeep),
              ],
            ),
          ),
          const SizedBox(height: 28),
          FloatIn(
            delay: const Duration(milliseconds: 580),
            child: Button3D(
              label: 'Create my account',
              icon: Icons.auto_awesome_rounded,
              onPressed: () => context.push(Routes.register),
            ),
          ),
          const SizedBox(height: 14),
          FloatIn(
            delay: const Duration(milliseconds: 680),
            child: Button3D.secondary(label: 'I already have an account', onPressed: () => context.push(Routes.login)),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.label, this.color);

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(40)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}
