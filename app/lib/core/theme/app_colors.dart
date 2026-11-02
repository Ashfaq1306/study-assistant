import 'package:flutter/material.dart';

/// Accent themes the student can pick. The accent drives buttons, rings,
/// highlights and the background glow; the other colours keep their meaning
/// (mint = success, coral = warning, sunshine = rewards, sky = AI helper).
enum AppAccent {
  lavender('Lavender', Color(0xFF6C5CE7), Color(0xFF4B3BC4)),
  ocean('Ocean', Color(0xFF2F80ED), Color(0xFF1B5FC1)),
  emerald('Emerald', Color(0xFF10B981), Color(0xFF07885E)),
  sunset('Sunset', Color(0xFFF97316), Color(0xFFC9550A)),
  rose('Rose', Color(0xFFE8457C), Color(0xFFB92D5E)),
  gold('Royal gold', Color(0xFFC9A227), Color(0xFF977813));

  const AppAccent(this.label, this.color, this.deep);

  final String label;
  final Color color;
  final Color deep;

  static AppAccent byName(String? name) => values.firstWhere((a) => a.name == name, orElse: () => lavender);
}

/// Every colour the app uses, for one brightness and accent.
@immutable
class AppPalette {
  const AppPalette._({
    required this.brightness,
    required this.accent,
    required this.violet,
    required this.violetDeep,
    required this.violetSoft,
    required this.sunshine,
    required this.sunshineDeep,
    required this.sunshineSoft,
    required this.mint,
    required this.mintDeep,
    required this.mintSoft,
    required this.coral,
    required this.coralDeep,
    required this.coralSoft,
    required this.sky,
    required this.skyDeep,
    required this.skySoft,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.line,
    required this.cloud,
    required this.card,
    required this.glass,
    required this.glassEdge,
    required this.backdrop,
  });

  factory AppPalette.light(AppAccent accent) => AppPalette._(
    brightness: Brightness.light,
    accent: accent,
    violet: accent.color,
    violetDeep: accent.deep,
    violetSoft: Color.alphaBlend(accent.color.withValues(alpha: 0.12), Colors.white),
    sunshine: const Color(0xFFFFC93C),
    sunshineDeep: const Color(0xFFE5A300),
    sunshineSoft: const Color(0xFFFFF4D6),
    mint: const Color(0xFF2ED3A5),
    mintDeep: const Color(0xFF17A57F),
    mintSoft: const Color(0xFFDDF8EF),
    coral: const Color(0xFFFF7A85),
    coralDeep: const Color(0xFFD9505D),
    coralSoft: const Color(0xFFFFE6E8),
    sky: const Color(0xFF4FC3F7),
    skyDeep: const Color(0xFF2196D3),
    skySoft: const Color(0xFFE0F4FD),
    ink: const Color(0xFF2D2A4A),
    inkSoft: const Color(0xFF6E6A8F),
    inkFaint: const Color(0xFFA9A5C4),
    line: const Color(0xFFE4E0F5),
    cloud: const Color(0xFFF6F4FF),
    card: Colors.white,
    glass: Colors.white.withValues(alpha: 0.72),
    glassEdge: Colors.white.withValues(alpha: 0.9),
    backdrop: const [Color(0xFFF7F5FF), Color(0xFFFFF9EE)],
  );

  /// Deep night with glowing accents. "Deep" colours are lighter here, because
  /// they are mostly used for text and icons on dark tints.
  factory AppPalette.dark(AppAccent accent) {
    final hsl = HSLColor.fromColor(accent.color);
    final bright = hsl.withLightness((hsl.lightness + 0.12).clamp(0, 0.78)).toColor();
    return AppPalette._(
      brightness: Brightness.dark,
      accent: accent,
      violet: bright,
      violetDeep: Color.lerp(bright, Colors.white, 0.25)!,
      violetSoft: Color.alphaBlend(accent.color.withValues(alpha: 0.22), const Color(0xFF15122A)),
      sunshine: const Color(0xFFFFD25E),
      sunshineDeep: const Color(0xFFFFD873),
      sunshineSoft: const Color(0xFF3A3017),
      mint: const Color(0xFF3FE0B3),
      mintDeep: const Color(0xFF6BEBC6),
      mintSoft: const Color(0xFF13362D),
      coral: const Color(0xFFFF8B95),
      coralDeep: const Color(0xFFFFA3AB),
      coralSoft: const Color(0xFF3E1E26),
      sky: const Color(0xFF6CCFFA),
      skyDeep: const Color(0xFF9ADDFB),
      skySoft: const Color(0xFF13324A),
      ink: const Color(0xFFF2F0FF),
      inkSoft: const Color(0xFFB9B4DA),
      inkFaint: const Color(0xFF7F7AA6),
      line: const Color(0xFF332F55),
      cloud: const Color(0xFF0D0B1C),
      card: const Color(0xFF231E40),
      glass: Colors.white.withValues(alpha: 0.07),
      glassEdge: Colors.white.withValues(alpha: 0.14),
      backdrop: const [Color(0xFF0D0B1C), Color(0xFF151033)],
    );
  }

  final Brightness brightness;
  final AppAccent accent;
  final Color violet, violetDeep, violetSoft;
  final Color sunshine, sunshineDeep, sunshineSoft;
  final Color mint, mintDeep, mintSoft;
  final Color coral, coralDeep, coralSoft;
  final Color sky, skyDeep, skySoft;
  final Color ink, inkSoft, inkFaint, line, cloud, card;

  /// Frosted surfaces: fill and hairline edge.
  final Color glass, glassEdge;

  /// Top and bottom of the page background.
  final List<Color> backdrop;

  bool get isDark => brightness == Brightness.dark;
}

/// The active palette. `violet` is the accent the student chose (lavender by
/// default). The app sets the palette before each build of the widget tree.
abstract final class AppColors {
  static AppPalette _palette = AppPalette.light(AppAccent.lavender);

  static AppPalette get palette => _palette;

  /// Called by the app root when the theme mode, system brightness or accent changes.
  static void use(AppPalette palette) => _palette = palette;

  static bool get isDark => _palette.isDark;

  static Color get violet => _palette.violet;
  static Color get violetDeep => _palette.violetDeep;
  static Color get violetSoft => _palette.violetSoft;
  static Color get sunshine => _palette.sunshine;
  static Color get sunshineDeep => _palette.sunshineDeep;
  static Color get sunshineSoft => _palette.sunshineSoft;
  static Color get mint => _palette.mint;
  static Color get mintDeep => _palette.mintDeep;
  static Color get mintSoft => _palette.mintSoft;
  static Color get coral => _palette.coral;
  static Color get coralDeep => _palette.coralDeep;
  static Color get coralSoft => _palette.coralSoft;
  static Color get sky => _palette.sky;
  static Color get skyDeep => _palette.skyDeep;
  static Color get skySoft => _palette.skySoft;
  static Color get ink => _palette.ink;
  static Color get inkSoft => _palette.inkSoft;
  static Color get inkFaint => _palette.inkFaint;
  static Color get line => _palette.line;
  static Color get cloud => _palette.cloud;
  static Color get card => _palette.card;
  static Color get glass => _palette.glass;

  /// Text and icons on bright faces (sunshine buttons): dark in both modes.
  static const onBright = Color(0xFF2D2A4A);

  /// Big accent surfaces (hero cards): the true accent, never the brightened night tone.
  static Color get hero => _palette.accent.color;
  static Color get glassEdge => _palette.glassEdge;
}
