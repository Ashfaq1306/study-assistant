import 'package:flutter/animation.dart';

/// Study Mate's design tokens. Everything on screen is built from these, so the app feels
/// like one calm, friendly place.
///
/// Why these values (see docs/design-system.md):
/// - **Soft, rounded shapes** (superellipse corners) read as safe and approachable; sharp
///   corners read as alert. Students should feel invited to study, not pressured.
/// - **An 8-point spacing scale** gives a steady rhythm the eye can rest on.
/// - **Gentle, quick motion** (200–320 ms, ease-out) confirms every tap without distracting.
abstract final class Space {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;
}

abstract final class Radii {
  /// Chips and small controls.
  static const double sm = 14;

  /// Buttons and inputs.
  static const double md = 22;

  /// Cards.
  static const double lg = 28;

  /// Sheets and hero panels.
  static const double xl = 34;

  /// Icon tiles: a share of their size, like app icons (iOS uses ~22.5%; a little rounder is friendlier).
  static const double iconRatio = 0.3;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 140);
  static const normal = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 320);
  static const ease = Curves.easeOutCubic;

  /// Pressed things shrink this much: a small, physical "give".
  static const double pressScale = 0.965;
}

/// Liquid glass: frosted, slightly tinted, with a bright rim where light catches the edge.
abstract final class Glass {
  /// Backdrop blur (sigma). Grouped blurs share one pass (see DreamyBackground's BackdropGroup).
  static const double blur = 22;

  /// Light mode: milky glass over the pastel backdrop.
  static const double lightFillTop = 0.78;
  static const double lightFillBottom = 0.56;

  /// Dark mode: smoked glass over the night backdrop.
  static const double darkFillTop = 0.11;
  static const double darkFillBottom = 0.05;

  static const double rimWidth = 1.2;
}
