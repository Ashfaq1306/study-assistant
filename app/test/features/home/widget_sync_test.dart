import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/features/auth/application/auth_controller.dart';
import 'package:study_assistant/features/auth/domain/app_user.dart';
import 'package:study_assistant/features/home/application/widget_sync.dart';
import 'package:study_assistant/features/study/domain/study_session.dart';

import '../../helpers.dart';

StudySession _session(SessionStatus status) => StudySession(
  id: 's1',
  subject: 'Science',
  topics: 'Water cycle',
  plannedMinutes: 25,
  status: status,
  lockedApps: const [],
  strict: true,
  exam: const ExamSettings(questionCount: 5, totalMarks: 10, passMarks: 5, questionTypes: [QuestionType.mcq]),
  startedAt: DateTime.utc(2026, 6, 1, 8),
  endsAt: DateTime.utc(2026, 6, 1, 8, 25),
  canFinishAt: DateTime.utc(2026, 6, 1, 8, 12),
  studiedMinutes: 0,
);

WidgetSnapshot _snap({AuthState? auth, StudySession? session, List<({String kind, String title})> locks = const []}) =>
    widgetSnapshot(
      auth: auth ?? AuthSignedIn(testUser()),
      session: session,
      todayMinutes: 42,
      streakDays: 3,
      parentLocks: locks,
    );

void main() {
  test('studying shows the subject and counts down to the end', () {
    final s = _snap(session: _session(SessionStatus.studying));
    expect(s.mode, 'studying');
    expect(s.title, 'Science: Water cycle');
    expect(s.endsAt, DateTime.utc(2026, 6, 1, 8, 25));
    expect((s.todayMinutes, s.streakDays), (42, 3));
  });

  test('exam waiting, then a parent lock, then idle', () {
    expect(_snap(session: _session(SessionStatus.examPending)).mode, 'exam');
    expect(_snap(locks: [(kind: 'PARENT', title: 'Homework first')]).title, 'Homework first');
    expect(_snap().mode, 'idle');
  });

  test('signed out shows nothing personal; parents get a short hint', () {
    final out = _snap(auth: const AuthSignedOut());
    expect((out.mode, out.todayMinutes), ('signedOut', 0));
    final parent = _snap(auth: AuthSignedIn(testUser(role: UserRole.parent)));
    expect(parent.subtitle, contains('children'));
  });
}
