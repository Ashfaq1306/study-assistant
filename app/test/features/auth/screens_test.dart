import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:study_assistant/app/providers.dart';
import 'package:study_assistant/core/network/api_exception.dart';
import 'package:study_assistant/core/storage/token_store.dart';
import 'package:study_assistant/core/theme/app_theme.dart';
import 'package:study_assistant/core/widgets/button_3d.dart';
import 'package:study_assistant/features/auth/data/auth_api.dart';
import 'package:study_assistant/features/auth/presentation/login_screen.dart';
import 'package:study_assistant/features/auth/presentation/register_screen.dart';
import 'package:study_assistant/features/auth/presentation/welcome_screen.dart';

class MockAuthApi extends Mock implements AuthApi {}

void main() {
  late MockAuthApi api;

  setUp(() => api = MockAuthApi());

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authApiProvider.overrideWithValue(api), tokenStoreProvider.overrideWithValue(MemoryTokenStore())],
        child: MaterialApp(theme: AppTheme.light(), home: screen),
      ),
    );
    // Background and mascot animate forever, so pump frames instead of settling.
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.widgetWithText(Button3D, label);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('welcome offers sign up and sign in', (tester) async {
    await pumpScreen(tester, const WelcomeScreen());
    expect(find.text('Create my account'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
  });

  group('login', () {
    testWidgets('validates before calling the server', (tester) async {
      await pumpScreen(tester, const LoginScreen());
      await tapButton(tester, 'Sign in');

      expect(find.text('Enter your email or mobile number.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      verifyNever(() => api.login(any(), any()));
    });

    testWidgets('shows the server message on wrong credentials', (tester) async {
      when(() => api.login(any(), any())).thenThrow(
        const ApiException(
          code: 'INVALID_CREDENTIALS',
          message: 'Wrong email/mobile number or password.',
          statusCode: 401,
        ),
      );
      await pumpScreen(tester, const LoginScreen());

      await tester.enterText(find.byType(TextFormField).at(0), 'nadia@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'wrong1234');
      await tapButton(tester, 'Sign in');

      expect(find.text('Wrong email/mobile number or password.'), findsOneWidget);
      verify(() => api.login('nadia@example.com', 'wrong1234')).called(1);
    });
  });

  group('register', () {
    testWidgets('needs a role before continuing', (tester) async {
      await pumpScreen(tester, const RegisterScreen());
      final continueButton = find.widgetWithText(Button3D, 'Continue').first;

      expect(tester.widget<Button3D>(continueButton).onPressed, isNull);
      await tester.tap(find.text("I'm a student"));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<Button3D>(continueButton).onPressed, isNotNull);
    });

    testWidgets('asks for name and date of birth on step two', (tester) async {
      await pumpScreen(tester, const RegisterScreen());
      await tester.tap(find.text("I'm a parent"));
      await tester.pump(const Duration(milliseconds: 100));
      await tapButton(tester, 'Continue');
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Tell us about you'), findsOneWidget);
      await tester.tap(find.widgetWithText(Button3D, 'Continue').last);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Enter your name.'), findsOneWidget);
      expect(find.text('Pick your date of birth.'), findsOneWidget);
    });
  });
}
