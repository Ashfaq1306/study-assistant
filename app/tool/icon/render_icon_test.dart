// Renders the launcher icons and README logo from LogoPainter, so the brand
// has a single source. Regenerate after changing the logo:
//
//   flutter test tool/icon/render_icon_test.dart
//   dart run flutter_launcher_icons
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/core/widgets/app_logo.dart';

Future<void> _render(String path, LogoPainter painter, {int size = 1024, Color? fill}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final area = Size.square(size.toDouble());
  if (fill != null) canvas.drawRect(Offset.zero & area, Paint()..color = fill);
  painter.paint(canvas, area);
  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  test('render icons', () async {
    // iOS and legacy Android: full square tile; the OS applies its own mask.
    await _render('assets/icon/app_icon.png', const LogoPainter(rounded: false));
    // Android adaptive icon layers. The mark must fit the central 66/108 safe zone.
    await _render('assets/icon/app_icon_background.png', const LogoPainter(rounded: false, contentScale: 0));
    await _render('assets/icon/app_icon_foreground.png', const LogoPainter(background: false, contentScale: 0.62));
    await _render(
      'assets/icon/app_icon_monochrome.png',
      const LogoPainter(background: false, monochrome: true, contentScale: 0.62),
    );
    // README / store listing.
    await _render('../docs/assets/logo.png', const LogoPainter(), size: 512);
  });
}
