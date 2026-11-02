// Renders the Google Play feature graphic (1024 x 500) from the app's own logo and font, so the
// store artwork matches the app. Regenerate after changing the logo or the tagline:
//
//   flutter test tool/store/feature_graphic_test.dart
//
// Output: ../docs/store/feature-graphic.png and ../docs/store/icon-512.png (the Play listing icon).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/core/widgets/app_logo.dart';

const _width = 1024.0;
const _height = 500.0;

Future<void> _loadNunito() async {
  final loader = FontLoader('Nunito');
  for (final weight in ['700', '800', '900']) {
    loader.addFont(rootBundle.load('assets/fonts/Nunito-$weight.ttf'));
  }
  await loader.load();
}

void _text(
  Canvas canvas,
  String text,
  Offset at, {
  required double size,
  required FontWeight weight,
  required Color color,
  double maxWidth = 600,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: 'Nunito', fontSize: size, fontWeight: weight, color: color, height: 1.1),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);
  painter.paint(canvas, at);
}

void main() {
  testWidgets('feature graphic', (tester) async {
    await tester.runAsync(() async {
      await _loadNunito();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const area = Rect.fromLTWH(0, 0, _width, _height);

      // Brand violet, a little deeper at the bottom right.
      canvas.drawRect(
        area,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, const Offset(_width, _height), const [
            Color(0xFF8E7CF6),
            Color(0xFF5B45E0),
          ]),
      );
      // Soft glow behind the logo.
      canvas.drawCircle(
        const Offset(250, 250),
        230,
        Paint()
          ..shader = ui.Gradient.radial(const Offset(250, 250), 230, [
            Colors.white.withValues(alpha: 0.28),
            Colors.white.withValues(alpha: 0),
          ]),
      );

      canvas.save();
      canvas.translate(110, 110);
      const LogoPainter().paint(canvas, const Size.square(280));
      canvas.restore();

      _text(canvas, 'Study Mate', const Offset(450, 128), size: 68, weight: FontWeight.w900, color: Colors.white);
      _text(
        canvas,
        'Study smart.\nUnlock by learning.',
        const Offset(452, 222),
        size: 40,
        weight: FontWeight.w800,
        color: const Color(0xFFFFE07A),
      );
      _text(
        canvas,
        'Lock distractions · AI quizzes · Parent links',
        const Offset(454, 350),
        size: 25,
        weight: FontWeight.w700,
        color: Colors.white.withValues(alpha: 0.92),
        maxWidth: 560,
      );

      final image = await recorder.endRecording().toImage(_width.toInt(), _height.toInt());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('../docs/store/feature-graphic.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });

  testWidgets('play listing icon', (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      // Square tile: Google Play rounds the corners itself.
      const LogoPainter(rounded: false).paint(Canvas(recorder), const Size.square(512));
      final image = await recorder.endRecording().toImage(512, 512);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('../docs/store/icon-512.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
