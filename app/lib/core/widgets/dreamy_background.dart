import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The app's backdrop: a soft gradient with slowly drifting colour glows
/// (pastel by day, an aurora at night). Glass cards on top share one blur
/// pass through the [BackdropGroup] here.
class DreamyBackground extends StatefulWidget {
  const DreamyBackground({super.key, required this.child});

  final Widget child;

  @override
  State<DreamyBackground> createState() => _DreamyBackgroundState();
}

class _DreamyBackgroundState extends State<DreamyBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 18))
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return CustomPaint(
      painter: _BlobPainter(reduceMotion ? const AlwaysStoppedAnimation(0) : _controller, AppColors.palette),
      child: BackdropGroup(child: widget.child),
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.animation, this.palette) : super(repaint: animation);

  final Animation<double> animation;
  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: palette.backdrop,
        ).createShader(Offset.zero & size),
    );

    final strength = palette.isDark ? 0.34 : 0.22;
    final blobs = [
      (color: palette.violet, x: 0.15, y: 0.12, r: 0.6, phase: 0.0),
      (color: palette.isDark ? palette.sky : palette.sunshine, x: 0.9, y: 0.3, r: 0.45, phase: 2.1),
      (color: palette.mint, x: 0.2, y: 0.85, r: 0.5, phase: 4.2),
      (color: palette.isDark ? palette.violet : palette.coral, x: 0.95, y: 0.95, r: 0.45, phase: 1.3),
    ];

    final t = animation.value * 2 * math.pi;
    final unit = size.shortestSide;
    for (final b in blobs) {
      final center = Offset(
        size.width * b.x + math.sin(t + b.phase) * unit * 0.06,
        size.height * b.y + math.cos(t + b.phase) * unit * 0.05,
      );
      final radius = unit * b.r;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              b.color.withValues(alpha: strength),
              b.color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_BlobPainter oldDelegate) => oldDelegate.animation != animation || oldDelegate.palette != palette;
}
