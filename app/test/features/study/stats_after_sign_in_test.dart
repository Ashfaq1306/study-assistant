import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:study_assistant/app/providers.dart';
import 'package:study_assistant/core/storage/token_store.dart';
import 'package:study_assistant/features/auth/application/auth_controller.dart';
import 'package:study_assistant/features/auth/data/auth_api.dart';
import 'package:study_assistant/features/study/application/study_providers.dart';
import 'package:study_assistant/features/study/data/study_api.dart';
import 'package:study_assistant/features/study/domain/study_session.dart';

import '../../helpers.dart';

class MockAuthApi extends Mock implements AuthApi {}

class MockStudyApi extends Mock implements StudyApi {}

const _serverStats = StudyStats(todayMinutes: 30, streakDays: 7, week: [], totalMinutes: 255, sessionsCompleted: 7);

/// The stats once they have loaded.
Future<StudyStats> _stats(ProviderContainer c) async {
  for (var i = 0; i < 200; i++) {
    final v = c.read(studyStatsProvider);
    if (v.hasValue && !v.isLoading) return v.requireValue;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return c.read(studyStatsProvider).requireValue;
}

void main() {
  test('a student who signs in sees their own study numbers at once (regression)', () async {
    final auth = MockAuthApi();
    final study = MockStudyApi();
    final store = MemoryTokenStore();
    when(() => study.stats()).thenAnswer((_) async => _serverStats);

    final container = ProviderContainer.test(
      overrides: [
        authApiProvider.overrideWithValue(auth),
        studyApiProvider.overrideWithValue(study),
        tokenStoreProvider.overrideWithValue(store),
      ],
    );
    // Like the home-screen widget: keeps the stats alive while signed out.
    container.listen(studyStatsProvider, (_, _) {});

    // Signed out: nothing is asked of the server, and the numbers are zero.
    while (container.read(authControllerProvider) is AuthUnknown) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect((await _stats(container)).todayMinutes, 0);
    verifyNever(() => study.stats());

    // Signing in re-reads them straight away.
    when(() => auth.login(any(), any())).thenAnswer(
      (_) async => SignedInSession(
        user: testUser(),
        tokens: const AuthTokens(accessToken: 'a', refreshToken: 'r'),
      ),
    );
    await container.read(authControllerProvider.notifier).login('nadia@example.com', 'secret123');
    expect((await _stats(container)).todayMinutes, 30);
  });
}
