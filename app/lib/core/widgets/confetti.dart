import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A short burst of falling confetti, played once (e.g. when an exam is passed).
class Confetti extends StatefulWidget {
  const Confetti({super.key});

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final random = math.Random();
    final colors = [AppColors.violet, AppColors.sunshine, AppColors.mint, AppColors.coral, AppColors.sky];
    _pieces = List.generate(
      90,
      (_) => _Piece(
        x: random.nextDouble(),
        delay: random.nextDouble() * 0.35,
        speed: 0.7 + random.nextDouble() * 0.6,
        drift: (random.nextDouble() - 0.5) * 0.3,
        spin: random.nextDouble() * 8,
        size: 6 + random.nextDouble() * 7,
        color: colors[random.nextInt(colors.length)],
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) && !_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(size: Size.infinite, painter: _ConfettiPainter(_controller, _pieces)),
  );
}

class _Piece {
  const _Piece({
    required this.x,
    required this.delay,
    required this.speed,
    required this.drift,
    required this.spin,
    required this.size,
    required this.color,
  });

  final double x, delay, speed, drift, spin, size;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.animation, this.pieces) : super(repaint: animation);

  final Animation<double> animation;
  final List<_Piece> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t == 0 || t == 1) return;
    final paint = Paint();
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local == 0) continue;
      final y = -20 + local * p.speed * (size.height + 40);
      final x = (p.x + p.drift * local) * size.width;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * local * math.pi);
      paint.color = p.color.withValues(alpha: 1 - local * 0.6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
