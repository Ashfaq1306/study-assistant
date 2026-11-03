import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/core/theme/app_colors.dart';
import 'package:study_assistant/core/theme/app_theme.dart';
import 'package:study_assistant/core/widgets/choice_controls.dart';
import 'package:study_assistant/core/widgets/clay_card.dart';
import 'package:study_assistant/core/widgets/feedback.dart';
import 'package:study_assistant/core/widgets/liquid_glass.dart';

double _contrast(Color a, Color b) {
  final (hi, lo) = a.computeLuminance() > b.computeLuminance()
      ? (a.computeLuminance(), b.computeLuminance())
      : (b.computeLuminance(), a.computeLuminance());
  return (hi + 0.05) / (lo + 0.05);
}

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
  theme: AppTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(size: const Size(400, 900), textScaler: TextScaler.linear(textScale)),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  test('coloured labels are readable on light glass (WCAG AA)', () {
    AppColors.use(AppPalette.light(AppAccent.lavender));
    for (final accent in [
      AppColors.sunshine,
      AppColors.sunshineDeep,
      AppColors.mint,
      AppColors.mintDeep,
      AppColors.sky,
      AppColors.skyDeep,
      AppColors.coralDeep,
      AppColors.violet,
    ]) {
      expect(_contrast(AppColors.legible(accent), Colors.white), greaterThanOrEqualTo(4.5), reason: '$accent');
    }
  });

  test('dark mode keeps accents as they are (they are already bright on the night backdrop)', () {
    AppColors.use(AppPalette.dark(AppAccent.lavender));
    expect(AppColors.legible(AppColors.sunshineDeep), AppColors.sunshineDeep);
    AppColors.use(AppPalette.light(AppAccent.lavender));
  });

  testWidgets('cards, badges and banners render as glass', (tester) async {
    await tester.pumpWidget(
      _app(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClayCard(child: Text('Clear glass')),
            ClayCard(color: Colors.indigo, child: Text('Solid glass')),
            IconBadge(Icons.lock_rounded),
            MessageBanner.info('Heads up'),
          ],
        ),
      ),
    );
    expect(find.byType(LiquidGlass), findsNWidgets(2)); // the clear card and the banner
    expect(find.byType(GlassIconTile), findsNWidgets(2)); // the badge and the banner's icon
    expect(find.text('Solid glass'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the week chart never overflows, even with very large text', (tester) async {
    final today = DateTime(2026, 11, 3);
    final days = [
      for (var i = 6; i >= 0; i--)
        (day: today.subtract(Duration(days: i)), minutes: [30, 45, 25, 35, 50, 55, 0][6 - i]),
    ];
    for (final scale in [1.0, 1.3, 2.0]) {
      await tester.pumpWidget(
        _app(
          SizedBox(width: 360, child: WeekBars(days: days)),
          textScale: scale,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'text scale $scale');
    }
  });
}
