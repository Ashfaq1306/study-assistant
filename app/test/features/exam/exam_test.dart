import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:study_assistant/app/providers.dart';
import 'package:study_assistant/core/network/api_exception.dart';
import 'package:study_assistant/features/auth/application/auth_controller.dart';
import 'package:study_assistant/features/exam/data/exam_api.dart';
import 'package:study_assistant/features/exam/domain/exam.dart';
import 'package:study_assistant/features/study/domain/study_session.dart';
import 'package:study_assistant/features/tutor/tutor_screen.dart';

import '../../helpers.dart';

class _MockExamApi extends Mock implements ExamApi {}

/// Signed in as [testUser] until [switchTo] is called.
class _FakeAuth extends AuthController {
  @override
  AuthState build() => AuthSignedIn(testUser());

  void switchTo(String name) => state = AuthSignedIn(testUser(id: 'u2', name: name));
}

Map<String, Object?> _examJson({Map<String, Object?>? result}) => {
  'id': 'e1',
  'sessionId': 's1',
  'subject': 'ICT',
  'topics': 'Networks',
  'source': 'AI',
  'status': result == null ? 'ACTIVE' : 'SUBMITTED',
  'totalMarks': 10,
  'passMarks': 5,
  'createdAt': '2026-06-01T08:00:00.000Z',
  'expiresAt': '2026-06-01T08:10:00.000Z',
  'questions': [
    {
      'id': 'q1',
      'type': 'MCQ',
      'prompt': 'What is a LAN?',
      'options': ['A', 'B', 'C', 'D'],
      'marks': 4,
    },
    {
      'id': 'q2',
      'type': 'TRUE_FALSE',
      'prompt': 'Wi-Fi is wireless.',
      'options': ['True', 'False'],
      'marks': 3,
    },
    {'id': 'q3', 'type': 'SHORT', 'prompt': 'Name a router job.', 'options': <String>[], 'marks': 3},
  ],
  'result': result,
};

void main() {
  group('Exam', () {
    test('parses an active exam without answers', () {
      final exam = Exam.fromJson(_examJson());
      expect(exam.status, ExamStatus.active);
      expect(exam.isPractice, isFalse);
      expect(exam.questions.map((q) => q.type), [QuestionType.mcq, QuestionType.trueFalse, QuestionType.short]);
      expect(exam.result, isNull);
      expect(exam.expiresAt, DateTime.utc(2026, 6, 1, 8, 10));
    });

    test('answers are sent the way the server grades them', () {
      final exam = Exam.fromJson(_examJson());
      expect(exam.questions[0].answerForOption(2), '2');
      expect(exam.questions[1].answerForOption(0), 'true');
      expect(exam.questions[1].answerForOption(1), 'false');
    });

    test('parses a graded result with partial marks', () {
      final exam = Exam.fromJson(
        _examJson(
          result: {
            'score': 5.5,
            'passed': true,
            'submittedAt': '2026-06-01T08:05:00.000Z',
            'questions': [
              {
                'id': 'q3',
                'given': 'forwards packets',
                'correct': false,
                'awarded': 1.5,
                'marks': 3,
                'correctAnswer': 'It forwards data between networks',
                'explanation': 'Routers connect networks.',
                'feedback': 'Nearly: mention networks.',
              },
            ],
          },
        ),
      );
      expect(exam.status, ExamStatus.submitted);
      expect(exam.result!.score, 5.5);
      expect(exam.result!.passed, isTrue);
      expect(exam.result!.questions.single.awarded, 1.5);
      expect(exam.result!.questions.single.feedback, startsWith('Nearly'));
    });
  });

  group('TutorController', () {
    late _MockExamApi api;
    late ProviderContainer container;

    setUp(() {
      api = _MockExamApi();
      container = ProviderContainer(
        overrides: [examApiProvider.overrideWithValue(api), authControllerProvider.overrideWith(_FakeAuth.new)],
      );
      container.listen(tutorProvider, (_, _) {});
    });
    tearDown(() => container.dispose());

    test('adds the question and the reply', () async {
      when(() => api.askTutor(any())).thenAnswer((_) async => (reply: 'A LAN is a local network.', remainingToday: 59));
      await container.read(tutorProvider.notifier).ask('  What is a LAN? ');
      final state = container.read(tutorProvider);
      expect(state.messages.map((m) => m.text), ['What is a LAN?', 'A LAN is a local network.']);
      expect(state.messages.first.fromStudent, isTrue);
      expect(state.remainingToday, 59);
      expect(state.thinking, isFalse);
    });

    test('takes an unanswered question back out so it can be asked again', () async {
      when(() => api.askTutor(any()))
          .thenThrow(const ApiException(code: 'AI_OFF', message: 'The AI study helper is not switched on yet.'));
      await container.read(tutorProvider.notifier).ask('Hello');
      final state = container.read(tutorProvider);
      expect(state.messages, isEmpty);
      expect(state.error?.code, 'AI_OFF');
    });

    test('sends at most the latest 20 messages, starting with the student', () async {
      var call = 0;
      List<({String role, String content})>? sent;
      when(() => api.askTutor(any())).thenAnswer((invocation) async {
        sent = invocation.positionalArguments.first as List<({String role, String content})>;
        return (reply: 'reply ${call++}', remainingToday: 10);
      });
      final tutor = container.read(tutorProvider.notifier);
      for (var i = 0; i < 12; i++) {
        await tutor.ask('question $i');
      }
      expect(sent!.length, lessThanOrEqualTo(20));
      expect(sent!.first.role, 'user');
      expect(sent!.last.content, 'question 11');
    });

    test('a different account gets a fresh chat (no sharing on a family phone)', () async {
      when(() => api.askTutor(any())).thenAnswer((_) async => (reply: 'Hi Nadia', remainingToday: 59));
      await container.read(tutorProvider.notifier).ask('Hello');
      expect(container.read(tutorProvider).messages, hasLength(2));

      (container.read(authControllerProvider.notifier) as _FakeAuth).switchTo('Rafi');
      expect(container.read(tutorProvider).messages, isEmpty);
    });

    test('a reply to a chat that was cleared is dropped', () async {
      final reply = Completer<({String reply, int remainingToday})>();
      when(() => api.askTutor(any())).thenAnswer((_) => reply.future);
      final pending = container.read(tutorProvider.notifier).ask('Hello');
      container.read(tutorProvider.notifier).clear(); // ignored while thinking
      expect(container.read(tutorProvider).messages, hasLength(1));

      (container.read(authControllerProvider.notifier) as _FakeAuth).switchTo('Rafi');
      reply.complete((reply: 'Old reply', remainingToday: 1));
      await pending;
      expect(container.read(tutorProvider).messages, isEmpty);
    });

    test('ignores blank questions', () async {
      await container.read(tutorProvider.notifier).ask('   ');
      verifyNever(() => api.askTutor(any()));
    });
  });
}
