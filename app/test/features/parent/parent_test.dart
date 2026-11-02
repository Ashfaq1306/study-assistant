import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/app/routes.dart';
import 'package:study_assistant/features/auth/application/auth_controller.dart';
import 'package:study_assistant/features/auth/domain/app_user.dart';
import 'package:study_assistant/features/parent/domain/parent_models.dart';
import 'package:study_assistant/features/study/domain/study_session.dart';

import '../../helpers.dart';

/// Shaped like GET /v1/parent/children/:id.
Map<String, Object?> childJson() => {
  'id': 'c1',
  'name': 'Tania Akter',
  'age': 12,
  'todayStudyMinutes': 45,
  'todayScreenMinutes': 130,
  'streakDays': 3,
  'activeSession': null,
  'activeLocks': [
    {
      'id': 'l1',
      'title': 'Homework first',
      'subject': 'Math',
      'topics': 'Fractions',
      'lockedApps': ['*'],
      'strict': true,
      'questionSetId': 'q1',
      'exam': {
        'questionCount': 4,
        'totalMarks': 8,
        'passMarks': 4,
        'questionTypes': ['MCQ', 'TRUE_FALSE'],
        'difficulty': 'EASY',
      },
      'status': 'ACTIVE',
      'createdAt': '2026-10-20T07:00:00.000Z',
      'endedAt': null,
    },
  ],
  'lastExam': {
    'id': 'e1',
    'subject': 'Science',
    'topics': 'Plants',
    'source': 'AI',
    'score': 7.5,
    'totalMarks': 10,
    'passMarks': 5,
    'passed': true,
    'status': 'GRADED',
    'createdAt': '2026-10-19T10:00:00.000Z',
  },
  'protection': {'status': 'SHORTCUT_ON', 'lastSeenAt': '2026-10-20T07:10:00.000Z'},
  'stats': {
    'todayMinutes': 45,
    'streakDays': 3,
    'totalMinutes': 600,
    'sessionsCompleted': 12,
    'week': [
      {'day': '2026-10-20', 'minutes': 45},
    ],
  },
  'screenTime': [
    {
      'day': '2026-10-20',
      'totalMinutes': 130,
      'apps': [
        {'package': 'com.google.android.youtube', 'label': 'YouTube', 'minutes': 90},
      ],
    },
  ],
  'recentExams': <Object?>[],
  'recentSessions': <Object?>[],
  'recentLocks': <Object?>[],
  'devices': <Object?>[],
  'installedApps': [
    {'package': 'com.google.android.youtube', 'label': 'YouTube'},
  ],
};

void main() {
  test('a child dashboard parses from the server shape', () {
    final d = ChildDetail.fromJson(childJson());
    final s = d.summary;
    expect(s.firstName, 'Tania');
    expect(s.protection, Protection.shortcutOn);
    expect(s.protection.ok, isFalse);
    expect(s.activeLocks.single.wholePhone, isTrue);
    expect(s.activeLocks.single.exam.passMarks, 4);
    expect(s.lastExam!.score, 7.5);
    expect(d.screenTime.single.apps.single.label, 'YouTube');
    expect(d.installedApps.single.package, 'com.google.android.youtube');
    expect(d.stats.todayMinutes, 45);
  });

  test('parent questions round-trip in the shape the server checks', () {
    const q = ParentQuestion(
      type: QuestionType.mcq,
      prompt: ' What is 1/2 + 1/4? ',
      options: ['3/4', '2/6', '1/8', '2/4'],
      answer: '0',
    );
    final json = q.toJson();
    expect(json['type'], 'MCQ');
    expect(json['prompt'], 'What is 1/2 + 1/4?');
    expect(ParentQuestion.fromJson(json).options, hasLength(4));

    // Only multiple choice sends choices.
    const tf = ParentQuestion(
      type: QuestionType.trueFalse,
      prompt: 'The sun is a star.',
      answer: 'true',
      options: ['x'],
    );
    expect(tf.toJson()['options'], isEmpty);
  });

  test('parents reach their child pages, students do not', () {
    final parent = AuthSignedIn(testUser(role: UserRole.parent, age: 40));
    final student = AuthSignedIn(testUser());
    expect(guardRoute(parent, Routes.child('c1')), isNull);
    expect(guardRoute(parent, '${Routes.child('c1')}/lock'), isNull);
    expect(guardRoute(parent, Routes.questionSets), isNull);
    expect(guardRoute(student, Routes.child('c1')), Routes.home);
    expect(guardRoute(student, Routes.exam), isNull);
  });

  test('a lock quiz link carries the lock id', () {
    expect(Uri.parse(Routes.lockExam('abc 1')).queryParameters['lock'], 'abc 1');
  });
}
