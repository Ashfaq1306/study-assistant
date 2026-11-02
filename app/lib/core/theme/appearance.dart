import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

@immutable
class Appearance {
  const Appearance({this.mode = ThemeMode.system, this.accent = AppAccent.lavender});

  final ThemeMode mode;
  final AppAccent accent;

  Appearance copyWith({ThemeMode? mode, AppAccent? accent}) =>
      Appearance(mode: mode ?? this.mode, accent: accent ?? this.accent);

  /// The palette for this choice, given the phone's light or dark setting.
  AppPalette palette(Brightness system) {
    final dark = mode == ThemeMode.dark || (mode == ThemeMode.system && system == Brightness.dark);
    return dark ? AppPalette.dark(accent) : AppPalette.light(accent);
  }

  @override
  bool operator ==(Object other) => other is Appearance && other.mode == mode && other.accent == accent;

  @override
  int get hashCode => Object.hash(mode, accent);
}

final appearanceProvider = NotifierProvider<AppearanceController, Appearance>(AppearanceController.new);

/// Light, dark or system, plus the accent colour. Saved on the phone.
class AppearanceController extends Notifier<Appearance> {
  static const _modeKey = 'appearance.mode';
  static const _accentKey = 'appearance.accent';

  @override
  Appearance build() {
    _load();
    return const Appearance();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = ThemeMode.values.firstWhere(
        (m) => m.name == prefs.getString(_modeKey),
        orElse: () => ThemeMode.system,
      );
      if (ref.mounted) state = Appearance(mode: mode, accent: AppAccent.byName(prefs.getString(_accentKey)));
    } on Object {
      // Preferences unavailable: keep the defaults.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    await _save();
  }

  Future<void> setAccent(AppAccent accent) async {
    state = state.copyWith(accent: accent);
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, state.mode.name);
      await prefs.setString(_accentKey, state.accent.name);
    } on Object {
      // Not saved; the choice still applies until the app restarts.
    }
  }
}
