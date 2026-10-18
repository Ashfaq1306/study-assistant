import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:study_assistant/app/providers.dart';
import 'package:study_assistant/core/network/api_exception.dart';
import 'package:study_assistant/core/storage/token_store.dart';
import 'package:study_assistant/features/auth/application/auth_controller.dart';
import 'package:study_assistant/features/auth/data/auth_api.dart';
import 'package:study_assistant/features/auth/domain/otp.dart';

import '../../helpers.dart';

class MockAuthApi extends Mock implements AuthApi {}

void main() {
  late MockAuthApi api;
  late MemoryTokenStore store;

  setUp(() {
    api = MockAuthApi();
    store = MemoryTokenStore();
  });

  ProviderContainer makeContainer() => ProviderContainer.test(
    overrides: [authApiProvider.overrideWithValue(api), tokenStoreProvider.overrideWithValue(store)],
  );

  /// Waits for the startup restore to finish.
  Future<AuthState> settle(ProviderContainer c) async {
    c.listen(authControllerProvider, (_, _) {});
    for (var i = 0; i < 100 && c.read(authControllerProvider) is AuthUnknown; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return c.read(authControllerProvider);
  }

  final session = SignedInSession(
    user: testUser(),
    tokens: const AuthTokens(accessToken: 'a', refreshToken: 'r'),
  );

  group('restoring at startup', () {
    test('signed out when nothing is saved', () async {
      expect(await settle(makeContainer()), isA<AuthSignedOut>());
    });

    test('signed in with a fresh profile', () async {
      await store.save(accessToken: 'a', refreshToken: 'r');
      when(() => api.me()).thenAnswer((_) async => testUser(name: 'Fresh Name'));

      final state = await settle(makeContainer());

      expect((state as AuthSignedIn).user.name, 'Fresh Name');
      expect((await store.read())?.userJson, contains('Fresh Name'));
    });

    test('uses the cached profile when offline', () async {
      await store.save(accessToken: 'a', refreshToken: 'r');
      await store.saveUser(jsonEncode(testUser(name: 'Cached').toJson()));
      when(() => api.me()).thenThrow(const ApiException(code: ApiException.network, message: 'offline'));

      final state = await settle(makeContainer());

      expect((state as AuthSignedIn).user.name, 'Cached');
      expect(await store.read(), isNotNull, reason: 'tokens are kept for later');
    });

    test('clears a session the server rejects', () async {
      await store.save(accessToken: 'a', refreshToken: 'r');
      // As ApiClient does when the refresh token is rejected: clear, then fail.
      when(() => api.me()).thenAnswer((_) async {
        await store.clear();
        throw const ApiException(code: 'UNAUTHORIZED', message: 'no', statusCode: 401);
      });

      expect(await settle(makeContainer()), isA<AuthSignedOut>());
      expect(await store.read(), isNull);
    });
  });

  test('login saves tokens and signs in', () async {
    when(() => api.login('nadia@example.com', 'study1234')).thenAnswer((_) async => session);
    final c = makeContainer();
    await settle(c);

    final pending = await c.read(authControllerProvider.notifier).login('nadia@example.com', 'study1234');

    expect(pending, isNull);
    expect(c.read(authControllerProvider), isA<AuthSignedIn>());
    expect((await store.read())?.refreshToken, 'r');
  });

  test('login of an unverified account returns what is needed to verify', () async {
    when(() => api.login(any(), any())).thenThrow(
      const ApiException(
        code: 'ACCOUNT_NOT_VERIFIED',
        message: 'Enter the code',
        statusCode: 403,
        details: {
          'userId': 'u9',
          'channel': 'SMS',
          'verification': {
            'channel': 'SMS',
            'destination': '+880•••••••678',
            'expiresAt': '2026-06-01T08:10:00.000Z',
            'resendAvailableAt': '2026-06-01T08:01:00.000Z',
          },
        },
      ),
    );
    final c = makeContainer();
    await settle(c);

    final pending = await c.read(authControllerProvider.notifier).login('01712345678', 'study1234');

    expect(pending?.userId, 'u9');
    expect(pending?.channel, OtpChannel.sms);
    expect(pending?.delivery?.destination, '+880•••••••678');
    expect(c.read(authControllerProvider), isA<AuthSignedOut>());
  });

  test('other login failures reach the screen', () async {
    when(() => api.login(any(), any()))
        .thenThrow(const ApiException(code: 'INVALID_CREDENTIALS', message: 'Wrong password', statusCode: 401));
    final c = makeContainer();
    await settle(c);

    expect(
      () => c.read(authControllerProvider.notifier).login('x@y.com', 'nope1234'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_CREDENTIALS')),
    );
  });

  test('logout clears the session even if the server is unreachable', () async {
    await store.save(accessToken: 'a', refreshToken: 'r');
    when(() => api.me()).thenAnswer((_) async => testUser());
    when(() => api.logout('r')).thenThrow(const ApiException(code: ApiException.network, message: 'offline'));
    final c = makeContainer();
    await settle(c);

    await c.read(authControllerProvider.notifier).logout();

    expect(c.read(authControllerProvider), isA<AuthSignedOut>());
    expect(await store.read(), isNull);
  });
}
