import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import 'liquid_glass.dart';

/// The app's card: a pane of liquid glass (see [LiquidGlass]). Tappable cards give a little
/// when pressed. The name is historical; cards used to be matte "clay".
class ClayCard extends StatefulWidget {
  const ClayCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(Space.lg),
    this.color,
    this.glow,
    this.radius = Radii.lg,
    this.selected = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// A solid colour for the pane (hero and status cards). Clear glass when null.
  final Color? color;

  /// Tint of the shadow, so cards can glow in their accent colour; the theme accent when null.
  final Color? glow;
  final double radius;

  /// Tints the glass and draws an accent rim, for choice cards.
  final bool selected;

  @override
  State<ClayCard> createState() => _ClayCardState();
}

class _ClayCardState extends State<ClayCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final glow = widget.glow ?? AppColors.violet;
    final color = widget.color;
    final Widget card = color == null
        ? LiquidGlass(
            radius: widget.radius,
            padding: widget.padding,
            tint: widget.selected ? glow : null,
            rim: widget.selected ? glow : null,
            shadow: glow,
            // Cards sit on the soft, already-blurry backdrop: translucency alone reads as glass
            // and keeps long lists smooth on budget phones.
            blur: false,
            child: widget.child,
          )
        : _SolidGlass(
            color: color,
            radius: widget.radius,
            padding: widget.padding,
            glow: glow,
            rim: widget.selected ? glow : null,
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
      child: AnimatedScale(
        scale: _pressed ? Motion.pressScale : 1,
        duration: Motion.fast,
        curve: Motion.ease,
        child: card,
      ),
    );
  }
}

/// A coloured glass pane: a rich gradient of [color] with the same sheen and bright rim as clear glass.
class _SolidGlass extends StatelessWidget {
  const _SolidGlass({
    required this.color,
    required this.radius,
    required this.padding,
    required this.glow,
    required this.rim,
    required this.child,
  });

  final Color color;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color glow;
  final Color? rim;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final hsl = HSLColor.fromColor(color);
    final top = hsl.withLightness((hsl.lightness + 0.06).clamp(0.0, 0.97)).toColor();
    final bottom = hsl.withLightness((hsl.lightness - 0.05).clamp(0.0, 1.0)).toColor();
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius)),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [top, bottom]),
        shadows: [
          BoxShadow(
            color: glow.withValues(alpha: dark ? 0.35 : 0.26),
            blurRadius: 32,
            spreadRadius: -6,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: GlassRimPainter(radius: radius, rim: rim, dark: dark, onColor: true),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
