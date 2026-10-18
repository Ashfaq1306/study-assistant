import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static const radius = 20.0;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.violet,
      primary: AppColors.violet,
      secondary: AppColors.sunshine,
      tertiary: AppColors.mint,
      error: AppColors.coralDeep,
      surface: AppColors.card,
      onSurface: AppColors.ink,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Nunito',
      scaffoldBackgroundColor: AppColors.cloud,
      splashFactory: InkSparkle.splashFactory,
    );

    final text = base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);

    OutlineInputBorder border(Color color, [double width = 1.6]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: color, width: width),
    );

    return base.copyWith(
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
        headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        bodyLarge: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500, height: 1.4),
        bodyMedium: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500, height: 1.4, color: AppColors.inkSoft),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: AppColors.ink,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: const TextStyle(color: AppColors.inkFaint, fontWeight: FontWeight.w500),
        prefixIconColor: AppColors.inkSoft,
        suffixIconColor: AppColors.inkSoft,
        border: border(AppColors.line),
        enabledBorder: border(AppColors.line),
        focusedBorder: border(AppColors.violet, 2.2),
        errorBorder: border(AppColors.coral),
        focusedErrorBorder: border(AppColors.coralDeep, 2.2),
        errorStyle: const TextStyle(color: AppColors.coralDeep, fontWeight: FontWeight.w700),
        errorMaxLines: 3,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.violet,
          textStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      datePickerTheme: DatePickerThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
    );
  }
}
