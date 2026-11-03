import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';

/// A pane of liquid glass: the backdrop is frosted (blurred), lightly tinted, and the edge
/// catches the light (a bright rim at the top-left fading towards the bottom-right), with a
/// soft sheen across the top. Corners are superellipses ("squircles"), like iOS app icons.
///
/// Blur is grouped with the screen's [BackdropGroup] (DreamyBackground), so many panes share
/// one blur pass and stay smooth on budget phones. Set [blur] to false for panes over flat
/// colour (no visible difference there, and cheaper).
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = Radii.lg,
    this.padding = EdgeInsets.zero,
    this.tint,
    this.rim,
    this.rimWidth = Glass.rimWidth,
    this.blur = true,
    this.shadow,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Colour mixed into the glass (selected cards, accents). Plain glass when null.
  final Color? tint;

  /// Rim colour; light by default, the accent for selected panes.
  final Color? rim;
  final double rimWidth;
  final bool blur;

  /// Colour of the soft shadow under the pane; the theme accent when null.
  final Color? shadow;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final borderRadius = BorderRadius.circular(radius);
    final tint = this.tint;
    final top = dark ? Glass.darkFillTop : Glass.lightFillTop;
    final bottom = dark ? Glass.darkFillBottom : Glass.lightFillBottom;
    Color layer(double alpha, double tintAlpha) {
      final glass = Colors.white.withValues(alpha: alpha);
      return tint == null ? glass : Color.alphaBlend(tint.withValues(alpha: tintAlpha), glass);
    }

    final fill = [layer(top, 0.18), layer(bottom, 0.12)];
    final shadow = this.shadow ?? AppColors.violet;

    Widget pane = DecoratedBox(
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(borderRadius: borderRadius),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: fill),
      ),
      child: CustomPaint(
        foregroundPainter: GlassRimPainter(radius: radius, width: rimWidth, rim: rim, dark: dark),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (blur) {
      pane = BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(sigmaX: Glass.blur, sigmaY: Glass.blur),
        child: pane,
      );
    }
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(borderRadius: borderRadius),
        shadows: [
          BoxShadow(
            color: shadow.withValues(alpha: dark ? 0.28 : 0.13),
            blurRadius: 30,
            spreadRadius: -6,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.25 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRSuperellipse(borderRadius: borderRadius, child: pane),
    );
  }
}

/// The light-catching edge and the top sheen of a glass pane.
class GlassRimPainter extends CustomPainter {
  const GlassRimPainter({
    required this.radius,
    this.width = Glass.rimWidth,
    required this.rim,
    required this.dark,
    this.onColor = false,
  });

  final double radius;
  final double width;
  final Color? rim;
  final bool dark;

  /// The pane is a solid colour, not clear glass: the sheen and rim are tuned for that.
  final bool onColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Sheen: light falling on the upper part of the glass.
    final sheenRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.5);
    canvas.drawRSuperellipse(
      ui.RSuperellipse.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: onColor ? 0.2 : (dark ? 0.09 : 0.35)),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(sheenRect),
    );

    // Rim: bright where the light hits (top-left), faint on the far side.
    final inset = rect.deflate(width / 2);
    final rim = this.rim;
    canvas.drawRSuperellipse(
      ui.RSuperellipse.fromRectAndRadius(inset, Radius.circular(radius - width / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rim == null ? width : width * 2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: rim == null
              ? [
                  Colors.white.withValues(alpha: onColor ? 0.6 : (dark ? 0.32 : 0.95)),
                  Colors.white.withValues(alpha: onColor ? 0.08 : (dark ? 0.06 : 0.35)),
                  Colors.white.withValues(alpha: onColor ? 0.25 : (dark ? 0.14 : 0.7)),
                ]
              : [rim, rim.withValues(alpha: 0.75), rim],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(GlassRimPainter old) =>
      old.radius != radius || old.width != width || old.rim != rim || old.dark != dark || old.onColor != onColor;
}

/// An icon on a glossy glass tile, like a premium app icon: a vivid gradient in [color],
/// a curved highlight across the top, a bright rim and a soft coloured glow beneath.
/// Replaces flat "sticker" badges across the app.
class GlassIconTile extends StatelessWidget {
  const GlassIconTile({super.key, required this.icon, required this.color, this.size = 56});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final radius = BorderRadius.circular(size * Radii.iconRatio);
    final hsl = HSLColor.fromColor(color);
    final light = hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 0.82)).toColor();
    final deep = hsl.withLightness((hsl.lightness - 0.1).clamp(0.12, 1.0)).toColor();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(borderRadius: radius),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [light, deep]),
          shadows: [
            BoxShadow(
              color: color.withValues(alpha: dark ? 0.45 : 0.38),
              blurRadius: size * 0.34,
              spreadRadius: -size * 0.06,
              offset: Offset(0, size * 0.14),
            ),
          ],
        ),
        child: CustomPaint(
          painter: _IconGlossPainter(radius: size * Radii.iconRatio),
          child: Center(
            child: Icon(
              icon,
              size: size * 0.52,
              color: Colors.white,
              shadows: [
                Shadow(color: deep.withValues(alpha: 0.55), blurRadius: size * 0.08, offset: Offset(0, size * 0.025)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The curved highlight and bright rim of a glass icon tile.
class _IconGlossPainter extends CustomPainter {
  const _IconGlossPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = ui.RSuperellipse.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.save();
    canvas.clipRSuperellipse(shape);

    // A curved highlight over the top half, like light on a glass bead.
    final gloss = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.42)
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.62, 0, size.height * 0.42)
      ..close();
    canvas.drawPath(
      gloss,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.42), Colors.white.withValues(alpha: 0.04)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.6)),
    );

    // A faint glow at the bottom: light refracting back out of the glass.
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 1.05),
      size.width * 0.55,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: Offset(size.width / 2, size.height * 1.05), radius: size.width * 0.55)),
    );
    canvas.restore();

    // Rim.
    final w = size.width * 0.03;
    canvas.drawRSuperellipse(
      ui.RSuperellipse.fromRectAndRadius(rect.deflate(w / 2), Radius.circular(radius - w / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: 0.7), Colors.white.withValues(alpha: 0.08)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_IconGlossPainter old) => old.radius != radius;
}

/// A glass capsule with a small glossy icon tile and a label: for feature highlights and tags.
class GlassChip extends StatelessWidget {
  const GlassChip({super.key, required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: StadiumBorder(
          side: BorderSide(color: dark ? Colors.white.withValues(alpha: 0.14) : Colors.white, width: 1.2),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.05)]
              : [Colors.white.withValues(alpha: 0.9), Colors.white.withValues(alpha: 0.6)],
        ),
        shadows: [
          BoxShadow(
            color: color.withValues(alpha: dark ? 0.22 : 0.14),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassIconTile(icon: icon, color: color, size: 28),
            const SizedBox(width: Space.xs),
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
