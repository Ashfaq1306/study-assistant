import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'button_3d.dart';

/// A raised 3D "clay" tile: a solid face on a visible bottom edge, with a soft
/// highlight on top and a coloured glow underneath. Tappable tiles sink into
/// their edge when pressed, like [Button3D].
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
    this.depth = 6,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Face colour; the theme's card colour when null.
  final Color? color;

  /// Tint of the glow, the edge and the selected outline; the theme accent when null.
  final Color? glow;
  final double radius;

  /// Draws a thick accent outline, for choice cards.
  final bool selected;

  /// Height of the 3D edge. 0 gives a flat card.
  final double depth;

  @override
  State<ClayCard> createState() => _ClayCardState();
}

class _ClayCardState extends State<ClayCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap != null && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final glow = widget.glow ?? AppColors.violet;
    final face = widget.color ?? AppColors.card;
    final tinted = widget.color != null;
    // The edge: a deeper shade of a coloured face, or a soft accent-tinted clay for plain cards.
    final edge = tinted
        ? deeper(face, dark ? 0.14 : 0.12)
        : dark
        ? Color.lerp(face, Colors.black, 0.45)!
        : Color.alphaBlend(glow.withValues(alpha: 0.16), const Color(0xFFE9E5FA));
    final radius = BorderRadius.circular(widget.radius);
    final depth = widget.depth;
    final sink = _pressed ? depth * 0.7 : 0.0;

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      margin: EdgeInsets.only(top: sink, bottom: depth - sink),
      padding: widget.padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        // Light falls from the top: the face is a touch brighter there.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(face, Colors.white, dark ? 0.05 : (tinted ? 0.12 : 0.0))!, face],
        ),
        border: Border.all(
          color: widget.selected
              ? glow
              : dark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: tinted ? 0.35 : 1),
          width: widget.selected ? 3 : 1.5,
        ),
      ),
      child: widget.child,
    );

    final card = DecoratedBox(
      // The edge sits under the face; the glow sits under both.
      decoration: BoxDecoration(
        color: depth > 0 ? edge : null,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: glow.withValues(alpha: widget.selected ? 0.32 : (dark ? 0.22 : 0.14)),
            blurRadius: 26,
            offset: Offset(0, 12 - sink),
          ),
        ],
      ),
      child: tile,
    );

    if (widget.onTap == null) return card;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap!();
      },
      child: card,
    );
  }
}
