import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// A frosted-glass surface: the background blurs through a translucent fill,
/// with a hairline light edge and a soft coloured glow. Tappable cards shrink a
/// little when pressed. Blurs share one pass per page (see [PageShell]).
class ClayCard extends StatefulWidget {
  const ClayCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.glow,
    this.radius = 28,
    this.selected = false,
    this.blur = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// A tint instead of plain glass (e.g. a warning colour).
  final Color? color;

  /// Tint of the shadow and the selected outline; the theme accent when null.
  final Color? glow;
  final double radius;

  /// Draws a thick accent outline, for choice cards.
  final bool selected;

  /// Turn off for long lists of small cards.
  final bool blur;

  @override
  State<ClayCard> createState() => _ClayCardState();
}

class _ClayCardState extends State<ClayCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final glow = widget.glow ?? AppColors.violet;
    final radius = BorderRadius.circular(widget.radius);
    final fill = widget.color == null
        ? AppColors.glass
        : widget.color!.withValues(alpha: AppColors.isDark ? 0.9 : 0.86);

    Widget surface = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        // The fill, with a faint sheen from the top-left like light on glass.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(Colors.white.withValues(alpha: AppColors.isDark ? 0.06 : 0.3), fill),
            fill,
          ],
        ),
        border: Border.all(color: widget.selected ? glow : AppColors.glassEdge, width: widget.selected ? 2.6 : 1.2),
      ),
      child: widget.child,
    );

    if (widget.blur) {
      surface = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter.grouped(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: surface),
      );
    }

    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: glow.withValues(alpha: widget.selected ? 0.3 : (AppColors.isDark ? 0.18 : 0.12)),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: surface,
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
