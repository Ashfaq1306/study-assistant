import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/appearance.dart';
import '../../core/widgets/button_3d.dart';
import '../../core/widgets/clay_card.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/page_shell.dart';
import '../../core/widgets/wizard.dart';

/// Light, dark or follow the phone, and the accent colour.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final controller = ref.read(appearanceProvider.notifier);

    return PageShell(
      title: 'Appearance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Preview(),
          const SizedBox(height: 24),
          const FieldLabel('Mode'),
          ClayCard(
            padding: const EdgeInsets.all(6),
            radius: 22,
            child: Row(
              children: [
                for (final (mode, icon, label) in const [
                  (ThemeMode.system, Icons.brightness_auto_rounded, 'Phone'),
                  (ThemeMode.light, Icons.light_mode_rounded, 'Light'),
                  (ThemeMode.dark, Icons.dark_mode_rounded, 'Dark'),
                ])
                  Expanded(
                    child: _ModeChip(
                      icon: icon,
                      label: label,
                      selected: appearance.mode == mode,
                      onTap: () => controller.setMode(mode),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const FieldLabel('Accent colour'),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final accent in AppAccent.values)
                _Swatch(
                  accent: accent,
                  selected: appearance.accent == accent,
                  onTap: () => controller.setAccent(accent),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const MessageBanner.info('Dark mode is easier on the eyes at night and saves battery on most phones.'),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    return ClayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(Icons.auto_awesome_rounded, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Looking good!', style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      '${AppColors.palette.accent.label} · ${AppColors.isDark ? 'Dark' : 'Light'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Button3D(label: 'A shiny button', icon: Icons.bolt_rounded, onPressed: () {}),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.hero : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? Colors.white : AppColors.inkSoft),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.accent, required this.selected, required this.onTap});

  final AppAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${accent.label} accent',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(accent.color, Colors.white, 0.25)!, accent.deep],
                ),
                border: Border.all(color: selected ? AppColors.ink : Colors.transparent, width: 3),
                boxShadow: [
                  BoxShadow(color: accent.color.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 6)),
                ],
              ),
              child: selected ? const Icon(Icons.check_rounded, color: Colors.white) : null,
            ),
            const SizedBox(height: 6),
            Text(
              accent.label,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}
