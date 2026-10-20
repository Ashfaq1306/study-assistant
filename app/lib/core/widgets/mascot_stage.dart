import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'feedback.dart';
import 'pencil_3d.dart';

/// The 3D pencil on a glowing platform, with friendly icon badges orbiting it in
/// depth (passing in front of and behind the pencil) and sparkles twinkling.
/// Used on the opening screens. Still when the phone asks for reduced motion.
class MascotStage extends StatefulWidget {
  const MascotStage({super.key, this.size = 300, this.interactive = true});

  final double size;

  /// Lets the student spin the pencil with a finger.
  final bool interactive;

  @override
  State<MascotStage> createState() => _MascotStageState();
}

class _MascotStageState extends State<MascotStage> with SingleTickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(vsync: this, duration: const Duration(seconds: 14));

  static const _badges = [
    (Icons.lock_rounded, _Tone.violet),
    (Icons.quiz_rounded, _Tone.sunshine),
    (Icons.timer_rounded, _Tone.mint),
    (Icons.star_rounded, _Tone.coral),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _orbit.stop();
    } else if (!_orbit.isAnimating) {
      _orbit.repeat();
    }
  }

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: _orbit,
        builder: (context, pencil) {
          final t = _orbit.value * 2 * math.pi;
          // Each badge on a tilted ellipse: depth (sin) decides size, fade and draw order.
          final placed = [
            for (final (i, (icon, tone)) in _badges.indexed)
              () {
                final angle = t + i * math.pi / 2;
                final depth = math.sin(angle); // -1 far … 1 near
                return (
                  icon: icon,
                  tone: tone,
                  depth: depth,
                  offset: Offset(math.cos(angle) * s * 0.4, depth * s * 0.1 - s * 0.04 + math.sin(t * 2 + i) * 4),
                );
              }(),
          ];
          Widget badge(({IconData icon, _Tone tone, double depth, Offset offset}) b) {
            final scale = 0.78 + (b.depth + 1) * 0.16;
            return Transform.translate(
              offset: b.offset,
              child: Opacity(
                opacity: 0.55 + (b.depth + 1) * 0.225,
                child: Transform.scale(
                  scale: scale,
                  child: IconBadge(b.icon, size: s * 0.15, color: b.tone.color),
                ),
              ),
            );
          }

          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(child: CustomPaint(painter: _StagePainter(_orbit.value, AppColors.palette))),
              for (final b in placed.where((b) => b.depth < 0)) badge(b),
              pencil!,
              for (final b in placed.where((b) => b.depth >= 0)) badge(b),
            ],
          );
        },
        child: Transform.translate(
          offset: Offset(0, -s * 0.06),
          child: Pencil3D(size: s * 0.74, interactive: widget.interactive),
        ),
      ),
    );
  }
}

enum _Tone {
  violet,
  sunshine,
  mint,
  coral;

  Color get color => switch (this) {
    _Tone.violet => AppColors.violet,
    _Tone.sunshine => AppColors.sunshineDeep,
    _Tone.mint => AppColors.mintDeep,
    _Tone.coral => AppColors.coralDeep,
  };
}

/// The glowing 3D platform and the twinkling sparkles.
class _StagePainter extends CustomPainter {
  _StagePainter(this.t, this.palette);

  final double t;
  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height * 0.82);

    // Soft glow behind everything.
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.48),
      s * 0.46,
      Paint()
        ..shader = RadialGradient(
          colors: [
            palette.violet.withValues(alpha: palette.isDark ? 0.32 : 0.22),
            palette.violet.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(size.width / 2, size.height * 0.48), radius: s * 0.46)),
    );

    // The platform: a thick disc seen from above (side, then top face, then rim light).
    final top = Rect.fromCenter(center: center, width: s * 0.62, height: s * 0.14);
    final side = top.shift(Offset(0, s * 0.035));
    canvas.drawOval(
      side.inflate(s * 0.02),
      Paint()
        ..color = palette.violet.withValues(alpha: 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03),
    );
    canvas.drawOval(side, Paint()..color = Color.lerp(palette.violet, Colors.black, palette.isDark ? 0.35 : 0.15)!);
    canvas.drawRect(
      Rect.fromLTRB(top.left, center.dy, top.right, center.dy + s * 0.035),
      Paint()..color = Color.lerp(palette.violet, Colors.black, palette.isDark ? 0.35 : 0.15)!,
    );
    canvas.drawOval(
      top,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(palette.violet, Colors.white, 0.55)!, Color.lerp(palette.violet, Colors.white, 0.2)!],
        ).createShader(top),
    );
    canvas.drawOval(
      top.deflate(s * 0.03),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.006
        ..color = Colors.white.withValues(alpha: 0.6),
    );

    // Sparkles that twinkle in turn.
    final sparkle = Paint()..color = palette.isDark ? Colors.white : palette.sunshineDeep;
    for (final (i, (x, y, r)) in const [
      (0.12, 0.2, 0.026),
      (0.86, 0.16, 0.02),
      (0.9, 0.56, 0.024),
      (0.08, 0.62, 0.018),
    ].indexed) {
      final glow = (math.sin((t * 2 * math.pi * 3) + i * 1.7) + 1) / 2;
      final radius = s * r * (0.5 + glow * 0.7);
      final c = Offset(size.width * x, size.height * y);
      final k = radius * 0.22;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - radius)
          ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + radius, c.dy)
          ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + radius)
          ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - radius, c.dy)
          ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - radius)
          ..close(),
        sparkle..color = sparkle.color.withValues(alpha: 0.35 + glow * 0.65),
      );
    }
  }

  @override
  bool shouldRepaint(_StagePainter old) => old.t != t || old.palette != palette;
}
