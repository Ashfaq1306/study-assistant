import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/core/theme/app_colors.dart';
import 'package:study_assistant/core/theme/appearance.dart';

void main() {
  test('follows the phone unless the student picks light or dark', () {
    const phone = Appearance();
    expect(phone.palette(Brightness.dark).isDark, isTrue);
    expect(phone.palette(Brightness.light).isDark, isFalse);
    expect(const Appearance(mode: ThemeMode.light).palette(Brightness.dark).isDark, isFalse);
    expect(const Appearance(mode: ThemeMode.dark).palette(Brightness.light).isDark, isTrue);
  });

  test('the accent drives the main colour; meanings stay fixed', () {
    final ocean = AppPalette.light(AppAccent.ocean);
    expect(ocean.violet, AppAccent.ocean.color);
    expect(ocean.mint, AppPalette.light(AppAccent.rose).mint);
  });

  test('night text is light and readable on the dark backdrop', () {
    final night = AppPalette.dark(AppAccent.gold);
    expect(night.ink.computeLuminance(), greaterThan(0.8));
    expect(night.backdrop.first.computeLuminance(), lessThan(0.02));
    // Bright faces always get dark text.
    expect(AppColors.onBright.computeLuminance(), lessThan(0.05));
  });

  test('unknown saved accents fall back to lavender', () {
    expect(AppAccent.byName('neon'), AppAccent.lavender);
    expect(AppAccent.byName('gold'), AppAccent.gold);
  });
}
