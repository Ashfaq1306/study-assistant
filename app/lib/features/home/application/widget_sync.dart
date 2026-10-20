import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_lock/application/app_lock_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../../study/application/study_providers.dart';
import '../../study/domain/study_session.dart';

/// What the home-screen widget should show, from the app's current state.
typedef WidgetSnapshot = ({
  String mode,
  String title,
  String subtitle,
  DateTime? endsAt,
  int todayMinutes,
  int streakDays,
});

WidgetSnapshot widgetSnapshot({
  required AuthState auth,
  required StudySession? session,
  required int todayMinutes,
  required int streakDays,
  required List<({String kind, String title})> parentLocks,
}) {
  if (auth is! AuthSignedIn) {
    return (mode: 'signedOut', title: '', subtitle: '', endsAt: null, todayMinutes: 0, streakDays: 0);
  }
  if (auth.user.isParent) {
    return (
      mode: 'idle',
      title: '',
      subtitle: "See your children's progress",
      endsAt: null,
      todayMinutes: todayMinutes,
      streakDays: streakDays,
    );
  }
  if (session != null && session.status == SessionStatus.studying) {
    return (
      mode: 'studying',
      title: '${session.subject}: ${session.topics}',
      subtitle: '',
      endsAt: session.endsAt,
      todayMinutes: todayMinutes,
      streakDays: streakDays,
    );
  }
  if (session != null && session.status == SessionStatus.examPending) {
    return (
      mode: 'exam',
      title: '${session.subject} exam',
      subtitle: '',
      endsAt: null,
      todayMinutes: todayMinutes,
      streakDays: streakDays,
    );
  }
  if (parentLocks.isNotEmpty) {
    return (
      mode: 'locked',
      title: parentLocks.first.title,
      subtitle: 'Locked by your parent: pass the exam to unlock',
      endsAt: null,
      todayMinutes: todayMinutes,
      streakDays: streakDays,
    );
  }
  return (mode: 'idle', title: '', subtitle: '', endsAt: null, todayMinutes: todayMinutes, streakDays: streakDays);
}

/// Keeps the home-screen widget in step with the app. Watch it once from the root.
final widgetSyncProvider = Provider<void>((ref) {
  final platform = ref.watch(appLockPlatformProvider);
  WidgetSnapshot? last;

  void push() {
    final auth = ref.read(authControllerProvider);
    final student = auth is AuthSignedIn && !auth.user.isParent;
    final stats = student ? ref.read(studyStatsProvider).value : null;
    final reasons = ref.read(appLockProvider).value?.state.reasons ?? const [];
    final next = widgetSnapshot(
      auth: auth,
      session: student ? ref.read(activeSessionProvider).value : null,
      todayMinutes: stats?.todayMinutes ?? 0,
      streakDays: stats?.streakDays ?? 0,
      parentLocks: [
        for (final r in reasons)
          if (r.kind == 'PARENT') (kind: r.kind, title: r.title),
      ],
    );
    if (next == last) return;
    last = next;
    unawaited(
      platform
          .updateWidget(
            mode: next.mode,
            title: next.title,
            subtitle: next.subtitle,
            endsAt: next.endsAt,
            todayMinutes: next.todayMinutes,
            streakDays: next.streakDays,
          )
          .catchError((_) {}),
    );
  }

  ref.listen(authControllerProvider, (_, _) => push());
  ref.listen(activeSessionProvider, (_, _) => push());
  ref.listen(studyStatsProvider, (_, _) => push());
  ref.listen(appLockProvider, (_, _) => push());
  push();
});
