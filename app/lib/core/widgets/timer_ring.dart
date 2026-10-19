import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A thick, glossy progress ring with a knob at the tip, for countdowns.
class TimerRing extends StatelessWidget {
  const TimerRing({super.key, required this.progress, required this.child, this.size = 260, this.done = false});

  /// 0 = just started, 1 = finished.
  final double progress;
  final Widget child;
  final double size;

  /// Turns the ring green when the time is up.
  final bool done;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(progress.clamp(0.0, 1.0), done),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.done);

  final double progress;
  final bool done;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - stroke;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Soft raised disc behind the ring.
    canvas.drawCircle(
      center.translate(0, stroke * 0.35),
      radius + stroke * 0.9,
      Paint()
        ..color = AppColors.violet.withValues(alpha: 0.14)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke),
    );
    canvas.drawCircle(center, radius + stroke * 0.85, Paint()..color = Colors.white);

    // Recessed track: a darker ring offset down under a lighter one.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center.translate(0, 2), radius, track..color = AppColors.line);
    canvas.drawCircle(center, radius, track..color = AppColors.violetSoft);

    if (progress <= 0) return;
    final sweep = progress * 2 * math.pi;
    final colors = done
        ? [AppColors.mint, AppColors.mintDeep, AppColors.mint]
        : [AppColors.violet, AppColors.sky, AppColors.violet];
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(colors: colors, transform: const GradientRotation(-math.pi / 2)).createShader(rect),
    );

    // Glossy highlight along the arc for a 3D tube look.
    canvas.drawArc(
      rect.deflate(stroke * 0.18),
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.22
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.35),
    );

    final angle = -math.pi / 2 + sweep;
    final knob = center + Offset(math.cos(angle), math.sin(angle)) * radius;
    canvas.drawCircle(
      knob.translate(0, 2),
      stroke * 0.7,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(knob, stroke * 0.7, Paint()..color = Colors.white);
    canvas.drawCircle(knob, stroke * 0.38, Paint()..color = done ? AppColors.mintDeep : AppColors.violet);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.done != done;
}
