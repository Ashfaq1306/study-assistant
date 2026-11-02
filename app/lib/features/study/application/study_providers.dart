import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/study_api.dart';
import '../domain/study_session.dart';

final activeSessionProvider = AsyncNotifierProvider<ActiveSessionController, StudySession?>(
  ActiveSessionController.new,
);

/// The student's running session (studying or waiting for the exam), if any.
class ActiveSessionController extends AsyncNotifier<StudySession?> {
  StudyApi get _api => ref.read(studyApiProvider);

  @override
  Future<StudySession?> build() async {
    // Start over whenever a different student signs in, or nobody is.
    final userId = ref.watch(
      authControllerProvider.select((s) => s is AuthSignedIn && s.user.isStudent ? s.user.id : null),
    );
    if (userId == null) return null;
    return _api.active();
  }

  Future<StudySession> start(StartSessionRequest request) async {
    final session = await _api.start(request);
    state = AsyncData(session);
    _invalidateStats();
    return session;
  }

  Future<StudySession> finishEarly() async {
    final current = state.value;
    if (current == null) throw StateError('No session');
    final session = await _api.finish(current.id);
    state = AsyncData(session);
    _invalidateStats();
    return session;
  }

  /// Re-reads the session, e.g. when the timer hits zero.
  Future<void> refresh() async {
    state = AsyncData(await _api.active());
    _invalidateStats();
  }

  void _invalidateStats() {
    ref
      ..invalidate(studyStatsProvider)
      ..invalidate(studyHistoryProvider);
  }
}

/// The signed-in student's id, or null. Study data is re-read whenever it changes, so a
/// student who signs in sees their own numbers at once (the home-screen widget keeps these
/// providers alive while signed out, which used to leave the empty signed-out result showing).
final _studentIdProvider = Provider<String?>(
  (ref) => ref.watch(authControllerProvider.select((s) => s is AuthSignedIn && s.user.isStudent ? s.user.id : null)),
);

const _noStats = StudyStats(todayMinutes: 0, streakDays: 0, week: [], totalMinutes: 0, sessionsCompleted: 0);

final studyStatsProvider = FutureProvider.autoDispose<StudyStats>((ref) async {
  if (ref.watch(_studentIdProvider) == null) return _noStats;
  return ref.watch(studyApiProvider).stats();
});

final studyHistoryProvider = FutureProvider.autoDispose<List<StudySession>>((ref) async {
  if (ref.watch(_studentIdProvider) == null) return const [];
  return ref.watch(studyApiProvider).history(limit: 30);
});
