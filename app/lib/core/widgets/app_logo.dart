import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The Study Assistant mark: a pencil that has just drawn a tick, meaning
/// "you passed". One painter is the source for the in-app logo and for
/// every launcher icon (see tool/icon/render_icon_test.dart).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Study Assistant logo',
      image: true,
      child: CustomPaint(size: Size.square(size), painter: const LogoPainter()),
    );
  }
}

class LogoPainter extends CustomPainter {
  const LogoPainter({this.background = true, this.monochrome = false, this.contentScale = 1, this.rounded = true});

  /// Draws the violet gradient tile behind the mark.
  final bool background;

  /// Paints everything white, for Android themed (monochrome) icons.
  final bool monochrome;

  /// Shrinks the mark around the centre, e.g. into an adaptive icon's safe zone.
  final double contentScale;

  /// Rounded tile corners. iOS icons need a square tile (the OS rounds it).
  final bool rounded;

  static const _gradientTop = Color(0xFF8172F7);
  static const _gradientBottom = Color(0xFF4F3DD6);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (background) _paintTile(canvas, s);

    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.scale(contentScale);
    canvas.translate(-s / 2, -s / 2);
    _paintSparkles(canvas, s);
    _paintTick(canvas, s);
    _paintPencil(canvas, s);
    canvas.restore();
  }

  void _paintTile(Canvas canvas, double s) {
    final rect = Offset.zero & Size.square(s);
    final tile = rounded ? RRect.fromRectAndRadius(rect, Radius.circular(s * 0.23)) : RRect.fromRectXY(rect, 0, 0);
    canvas.drawRRect(
      tile,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_gradientTop, _gradientBottom],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipRRect(tile);
    final glowCenter = Offset(s * 0.22, s * 0.18);
    canvas.drawCircle(
      glowCenter,
      s * 0.55,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: glowCenter, radius: s * 0.55)),
    );
    canvas.restore();
  }

  void _paintTick(Canvas canvas, double s) {
    final tick = Path()
      ..moveTo(s * 0.2, s * 0.55)
      ..lineTo(s * 0.36, s * 0.71)
      ..lineTo(s * 0.575, s * 0.495);
    if (!monochrome) {
      canvas.drawPath(
        tick.shift(Offset(0, s * 0.025)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.09
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = AppColors.violetDeep.withValues(alpha: 0.45),
      );
    }
    canvas.drawPath(
      tick,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.09
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  void _paintPencil(Canvas canvas, double s) {
    final w = s * 0.072; // half the pencil's width
    Color c(Color color) => monochrome ? Colors.white : color;

    canvas.save();
    canvas.translate(s * 0.575, s * 0.495); // the tip sits where the tick ends
    canvas.rotate(-math.pi / 4);

    if (!monochrome) {
      canvas.drawRRect(
        RRect.fromLTRBR(s * 0.05, -w + s * 0.035, s * 0.42, w + s * 0.035, Radius.circular(w)),
        Paint()
          ..color = AppColors.violetDeep.withValues(alpha: 0.45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.012),
      );
    }

    final tipEnd = s * 0.065;
    final woodEnd = s * 0.15;
    final bodyEnd = s * 0.315;
    final ferruleEnd = s * 0.36;
    final end = s * 0.41;

    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(tipEnd, -w * 0.36)
        ..lineTo(tipEnd, w * 0.36)
        ..close(),
      Paint()..color = c(AppColors.ink),
    );
    canvas.drawPath(
      Path()
        ..moveTo(tipEnd, -w * 0.36)
        ..lineTo(woodEnd, -w)
        ..lineTo(woodEnd, w)
        ..lineTo(tipEnd, w * 0.36)
        ..close(),
      Paint()..color = c(const Color(0xFFFBD9AE)),
    );

    // Three bands suggest the hexagonal faces of the body.
    final third = 2 * w / 3;
    for (final (i, color) in [const Color(0xFFFFE27D), AppColors.sunshine, const Color(0xFFF2AE12)].indexed) {
      canvas.drawRect(
        Rect.fromLTRB(woodEnd, -w + third * i, bodyEnd, -w + third * (i + 1) + 0.5),
        Paint()..color = c(color),
      );
    }

    canvas.drawRect(Rect.fromLTRB(bodyEnd, -w, ferruleEnd, w), Paint()..color = c(const Color(0xFFDDE0EA)));
    if (!monochrome) {
      final band = Paint()..color = const Color(0xFFA9AFC2);
      for (final x in [bodyEnd + s * 0.012, ferruleEnd - s * 0.016]) {
        canvas.drawRect(Rect.fromLTRB(x, -w, x + s * 0.006, w), band);
      }
    }

    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        ferruleEnd,
        -w,
        end,
        w,
        topRight: Radius.circular(w * 0.7),
        bottomRight: Radius.circular(w * 0.7),
      ),
      Paint()..color = c(const Color(0xFFFF8FA3)),
    );
    canvas.restore();
  }

  void _paintSparkles(Canvas canvas, double s) {
    final paint = Paint()..color = monochrome ? Colors.white : Colors.white.withValues(alpha: 0.95);
    for (final (x, y, r) in [(0.27, 0.27, 0.06), (0.4, 0.17, 0.035), (0.8, 0.72, 0.04)]) {
      canvas.drawPath(_sparkle(Offset(s * x, s * y), s * r), paint);
    }
  }

  /// A four-pointed star with curved sides.
  Path _sparkle(Offset c, double r) {
    final k = r * 0.22;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r)
      ..close();
  }

  @override
  bool shouldRepaint(LogoPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.monochrome != monochrome ||
      oldDelegate.contentScale != contentScale ||
      oldDelegate.rounded != rounded;
}
