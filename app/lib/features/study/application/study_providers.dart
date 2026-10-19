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
      authControllerProvider.select((s) => s is AuthSignedIn && !s.user.isParent ? s.user.id : null),
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

final studyStatsProvider = FutureProvider.autoDispose<StudyStats>((ref) => ref.watch(studyApiProvider).stats());

final studyHistoryProvider = FutureProvider.autoDispose<List<StudySession>>(
  (ref) => ref.watch(studyApiProvider).history(limit: 30),
);
