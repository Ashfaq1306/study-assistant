import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Pastel backdrop with soft colour blobs that drift slowly. Cheap to draw:
/// radial gradients only, no blur filters.
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
      painter: _BlobPainter(reduceMotion ? const AlwaysStoppedAnimation(0) : _controller),
      child: widget.child,
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  static const _blobs = [
    (color: AppColors.violet, x: 0.15, y: 0.12, r: 0.55, phase: 0.0),
    (color: AppColors.sunshine, x: 0.9, y: 0.28, r: 0.45, phase: 2.1),
    (color: AppColors.mint, x: 0.2, y: 0.85, r: 0.5, phase: 4.2),
    (color: AppColors.coral, x: 0.95, y: 0.95, r: 0.4, phase: 1.3),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7F5FF), Color(0xFFFFF9EE)],
        ).createShader(Offset.zero & size),
    );

    final t = animation.value * 2 * math.pi;
    final unit = size.shortestSide;
    for (final b in _blobs) {
      final center = Offset(
        size.width * b.x + math.sin(t + b.phase) * unit * 0.06,
        size.height * b.y + math.cos(t + b.phase) * unit * 0.05,
      );
      final radius = unit * b.r;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(colors: [b.color.withValues(alpha: 0.22), b.color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_BlobPainter oldDelegate) => oldDelegate.animation != animation;
}
