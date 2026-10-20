import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// A rounded, selectable pill with an optional icon.
class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// The theme accent when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppColors.hero;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? color : AppColors.card,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: selected ? color : AppColors.line, width: 1.6),
            boxShadow: [
              BoxShadow(
                color: (selected ? color : AppColors.violet).withValues(alpha: selected ? 0.3 : 0.06),
                blurRadius: selected ? 12 : 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: selected ? Colors.white : color),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "− 10 +" control with big round buttons.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.suffix = '',
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink),
          ),
        ),
        _RoundButton(
          icon: Icons.remove_rounded,
          tooltip: 'Less',
          onTap: value > min ? () => onChanged((value - step).clamp(min, max)) : null,
        ),
        SizedBox(
          width: 72,
          child: Text(
            '$value$suffix',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.ink),
          ),
        ),
        _RoundButton(
          icon: Icons.add_rounded,
          tooltip: 'More',
          onTap: value < max ? () => onChanged((value + step).clamp(min, max)) : null,
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? AppColors.violetSoft : AppColors.cloud,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        icon: Icon(icon, color: enabled ? AppColors.violet : AppColors.inkFaint),
      ),
    );
  }
}

/// Seven chunky bars, one per day, tallest day = full height.
class WeekBars extends StatelessWidget {
  const WeekBars({super.key, required this.days, this.height = 150});

  final List<({DateTime day, int minutes})> days;
  final double height;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final most = days.fold<int>(0, (m, d) => d.minutes > m ? d.minutes : m);
    return Semantics(
      label: 'Study minutes for the last 7 days: ${days.map((d) => d.minutes).join(', ')}',
      excludeSemantics: true,
      child: SizedBox(
        height: height + 44,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, d) in days.indexed)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      d.minutes > 0 ? '${d.minutes}' : '',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.inkSoft),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: Duration(milliseconds: 400 + i * 60),
                      curve: Curves.easeOutBack,
                      height: most == 0 ? 8 : 8 + (height - 8) * d.minutes / most,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: i == days.length - 1
                              ? [AppColors.sunshine, AppColors.sunshineDeep]
                              : [const Color(0xFF8D80F0), AppColors.violet],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (i == days.length - 1 ? AppColors.sunshineDeep : AppColors.violetDeep).withValues(
                              alpha: 0.35,
                            ),
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _letters[d.day.weekday - 1],
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: i == days.length - 1 ? AppColors.ink : AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
