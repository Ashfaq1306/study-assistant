import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// A soft, raised "clay" surface. Tappable cards shrink a little when pressed.
class ClayCard extends StatefulWidget {
  const ClayCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
    this.color = AppColors.card,
    this.glow = AppColors.violet,
    this.radius = 28,
    this.selected = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;

  /// Tint of the shadow, so cards can glow in their accent colour.
  final Color glow;
  final double radius;

  /// Draws a thick accent outline, for choice cards.
  final bool selected;

  @override
  State<ClayCard> createState() => _ClayCardState();
}

class _ClayCardState extends State<ClayCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: widget.selected ? widget.glow : Colors.white, width: widget.selected ? 3 : 1.5),
        boxShadow: [
          BoxShadow(
            color: widget.glow.withValues(alpha: widget.selected ? 0.28 : 0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(color: widget.glow.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: widget.child,
    );

    if (widget.onTap == null) return card;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap!();
      },
      child: AnimatedScale(scale: _pressed ? 0.97 : 1, duration: const Duration(milliseconds: 120), child: card),
    );
  }
}
