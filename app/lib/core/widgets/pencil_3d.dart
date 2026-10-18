import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The app mascot: a real 3D pencil mesh (eraser, metal ferrule, hexagonal
/// body, sharpened wood and graphite) rendered with perspective, lighting,
/// back-face culling and depth sorting. It spins on its own and can be
/// dragged. No 3D engine or model file needed.
class Pencil3D extends StatefulWidget {
  const Pencil3D({super.key, this.size = 220, this.interactive = true});

  final double size;
  final bool interactive;

  @override
  State<Pencil3D> createState() => _Pencil3DState();
}

class _Pencil3DState extends State<Pencil3D> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 7));
  final _drag = ValueNotifier(Offset.zero);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _spin.value = 0.12;
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pencil = RepaintBoundary(
      child: CustomPaint(size: Size.square(widget.size), painter: _PencilPainter(_spin, _drag)),
    );
    if (!widget.interactive) return ExcludeSemantics(child: pencil);
    return Semantics(
      label: 'Pencil mascot. Drag to spin it.',
      child: GestureDetector(
        onPanUpdate: (d) {
          final next = _drag.value + Offset(d.delta.dx * 0.012, -d.delta.dy * 0.006);
          _drag.value = Offset(next.dx, next.dy.clamp(-0.5, 0.5));
        },
        child: pencil,
      ),
    );
  }
}

class _V3 {
  const _V3(this.x, this.y, this.z);
  final double x, y, z;

  _V3 operator +(_V3 o) => _V3(x + o.x, y + o.y, z + o.z);
  _V3 operator -(_V3 o) => _V3(x - o.x, y - o.y, z - o.z);
  _V3 scale(double s) => _V3(x * s, y * s, z * s);
  double dot(_V3 o) => x * o.x + y * o.y + z * o.z;
  _V3 cross(_V3 o) => _V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  _V3 normalized() {
    final length = math.sqrt(dot(this));
    return length == 0 ? this : scale(1 / length);
  }

  /// Roll around the pencil's own axis, then tilt, then turn.
  _V3 rotate(_Rotation r) {
    final y1 = y * r.cosSpin - z * r.sinSpin;
    final z1 = y * r.sinSpin + z * r.cosSpin;
    final x2 = x * r.cosTilt - y1 * r.sinTilt;
    final y2 = x * r.sinTilt + y1 * r.cosTilt;
    return _V3(x2 * r.cosYaw + z1 * r.sinYaw, y2, -x2 * r.sinYaw + z1 * r.cosYaw);
  }
}

class _Rotation {
  _Rotation(double spin, double tilt, double yaw)
    : cosSpin = math.cos(spin),
      sinSpin = math.sin(spin),
      cosTilt = math.cos(tilt),
      sinTilt = math.sin(tilt),
      cosYaw = math.cos(yaw),
      sinYaw = math.sin(yaw);

  final double cosSpin, sinSpin, cosTilt, sinTilt, cosYaw, sinYaw;
}

class _Face {
  _Face(this.points, this.color, this.normal) : centroid = points.reduce((a, b) => a + b).scale(1 / points.length);

  final List<_V3> points;
  final Color color;
  final _V3 normal;
  final _V3 centroid;
}

/// Built once: the pencil lies along X, eraser at -0.95, graphite tip at +0.95.
final List<_Face> _mesh = _buildMesh();

List<_Face> _buildMesh() {
  final faces = <_Face>[];
  _V3 ring(double x, double r, double a) => _V3(x, r * math.cos(a), r * math.sin(a));

  _V3 outward(List<_V3> p) {
    final n = (p[1] - p[0]).cross(p[2] - p[0]).normalized();
    final c = p.reduce((a, b) => a + b);
    return n.dot(_V3(0, c.y, c.z)) < 0 ? n.scale(-1) : n;
  }

  void band(double x0, double r0, double x1, double r1, int sides, Color Function(int) color, {double offset = 0}) {
    for (var i = 0; i < sides; i++) {
      final a0 = offset + i * 2 * math.pi / sides;
      final a1 = offset + (i + 1) * 2 * math.pi / sides;
      final quad = [ring(x0, r0, a0), ring(x1, r1, a0), ring(x1, r1, a1), ring(x0, r0, a1)];
      final poly = r1 == 0 ? [quad[0], quad[1], quad[3]] : quad;
      faces.add(_Face(poly, color(i), outward(poly)));
    }
  }

  void cap(double x, double r, int sides, Color color, double direction) {
    faces.add(
      _Face([for (var i = 0; i < sides; i++) ring(x, r, i * 2 * math.pi / sides)], color, _V3(direction, 0, 0)),
    );
  }

  const hex = math.pi / 6;
  const eraser = Color(0xFFFF8FA3);
  const metal = Color(0xFFD5D9E4);
  const metalDark = Color(0xFFA9AFC2);
  const wood = Color(0xFFF6CFA0);
  const graphite = Color(0xFF3A3654);

  band(-0.95, 0.17, -0.76, 0.17, 18, (_) => eraser);
  cap(-0.95, 0.17, 18, const Color(0xFFF07A90), -1);
  cap(-0.76, 0.195, 18, metalDark, -1);
  band(-0.76, 0.195, -0.71, 0.195, 18, (_) => metalDark);
  band(-0.71, 0.195, -0.62, 0.195, 18, (_) => metal);
  band(-0.62, 0.195, -0.57, 0.195, 18, (_) => metalDark);
  band(-0.57, 0.2, 0.48, 0.2, 6, (i) => i.isEven ? AppColors.sunshine : const Color(0xFFFFD45E), offset: hex);
  band(0.48, 0.2, 0.78, 0.066, 6, (_) => wood, offset: hex);
  band(0.78, 0.066, 0.95, 0, 6, (_) => graphite, offset: hex);
  return faces;
}

class _PencilPainter extends CustomPainter {
  _PencilPainter(this.spin, this.drag) : super(repaint: Listenable.merge([spin, drag]));

  final Animation<double> spin;
  final ValueListenable<Offset> drag;

  static const _cameraDistance = 4.0;
  static final _light = const _V3(-0.45, 0.65, 0.62).normalized();
  static final _halfway = (_light + const _V3(0, 0, 1)).normalized();

  @override
  void paint(Canvas canvas, Size size) {
    final t = spin.value * 2 * math.pi;
    final rotation = _Rotation(t + drag.value.dx, 0.6 + drag.value.dy, math.sin(t) * 0.45);
    final bob = math.sin(t * 2) * size.height * 0.02;
    final center = size.center(Offset(0, bob - size.height * 0.03));
    final scale = size.shortestSide * 0.46;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.88),
        width: size.width * (0.5 - bob / size.height),
        height: size.height * 0.07,
      ),
      Paint()
        ..color = AppColors.violet.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    final visible = <({double depth, Path path, Color color})>[];
    for (final face in _mesh) {
      final normal = face.normal.rotate(rotation);
      final centroid = face.centroid.rotate(rotation);
      if (normal.dot(_V3(-centroid.x, -centroid.y, _cameraDistance - centroid.z)) <= 0) continue;

      final path = Path();
      for (var i = 0; i < face.points.length; i++) {
        final p = face.points[i].rotate(rotation);
        final perspective = _cameraDistance / (_cameraDistance - p.z);
        final screen = Offset(center.dx + p.x * scale * perspective, center.dy - p.y * scale * perspective);
        i == 0 ? path.moveTo(screen.dx, screen.dy) : path.lineTo(screen.dx, screen.dy);
      }
      path.close();
      visible.add((depth: centroid.z, path: path, color: _shade(face.color, normal)));
    }

    visible.sort((a, b) => a.depth.compareTo(b.depth));
    final fill = Paint()..isAntiAlias = true;
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeJoin = StrokeJoin.round;
    for (final f in visible) {
      canvas.drawPath(f.path, fill..color = f.color);
      canvas.drawPath(f.path, seam..color = f.color); // hides hairline gaps between faces
    }
  }

  /// Soft violet shadows instead of black keep the look friendly.
  Color _shade(Color base, _V3 normal) {
    final diffuse = math.max(0.0, normal.dot(_light));
    final specular = math.pow(math.max(0.0, normal.dot(_halfway)), 28) * 0.45;
    final shadowTone = Color.lerp(base, AppColors.violetDeep, 0.5)!;
    final lit = Color.lerp(shadowTone, base, (0.3 + 0.75 * diffuse).clamp(0.0, 1.0))!;
    return Color.lerp(lit, Colors.white, specular.toDouble())!;
  }

  @override
  bool shouldRepaint(_PencilPainter oldDelegate) => oldDelegate.spin != spin || oldDelegate.drag != drag;
}
