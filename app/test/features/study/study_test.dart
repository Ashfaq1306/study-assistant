import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/core/theme/app_theme.dart';
import 'package:study_assistant/features/study/domain/study_session.dart';
import 'package:study_assistant/features/study/presentation/widgets/exam_settings_editor.dart';

void main() {
  test('pass mark floor rounds up', () {
    expect(ExamSettings.minPassMarks(50, 50), 25);
    expect(ExamSettings.minPassMarks(15, 50), 8);
    expect(ExamSettings.minPassMarks(15, 70), 11);
  });

  test('parses a session from the API', () {
    final s = StudySession.fromJson({
      'id': 's1',
      'subject': 'Mathematics',
      'topics': 'Fractions',
      'plannedMinutes': 30,
      'status': 'EXAM_PENDING',
      'lockedApps': ['com.facebook.katana'],
      'strict': true,
      'exam': {
        'questionCount': 10,
        'totalMarks': 50,
        'passMarks': 30,
        'questionTypes': ['MCQ', 'SHORT'],
        'difficulty': 'HARD',
      },
      'startedAt': '2026-06-01T08:00:00.000Z',
      'endsAt': '2026-06-01T08:30:00.000Z',
      'canFinishAt': '2026-06-01T08:15:00.000Z',
      'studyEndedAt': '2026-06-01T08:30:00.000Z',
      'completedAt': null,
      'studiedMinutes': 30,
    });
    expect(s.status, SessionStatus.examPending);
    expect(s.status.isActive, isTrue);
    expect(s.exam.questionTypes, [QuestionType.mcq, QuestionType.short]);
    expect(s.exam.difficulty, Difficulty.hard);
    expect(s.exam.passPercent, 60);
    expect(s.endsAt.difference(s.startedAt), const Duration(minutes: 30));
  });

  testWidgets('the exam editor never lets the pass mark drop under the floor', (tester) async {
    var value = const ExamSettings(questionCount: 10, totalMarks: 50, passMarks: 25, questionTypes: [QuestionType.mcq]);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => ExamSettingsEditor(
                value: value,
                minPassPercent: 50,
                maxQuestions: 30,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      ),
    );

    // Raising the total to 55 must raise the pass mark to at least 28.
    await tester.tap(find.byTooltip('More').at(1));
    await tester.pump();
    expect(value.totalMarks, 55);
    expect(value.passMarks, 28);

    // The last question type cannot be switched off.
    await tester.tap(find.text('Multiple choice'));
    await tester.pump();
    expect(value.questionTypes, [QuestionType.mcq]);

    // More questions than marks is impossible: total follows the count.
    for (var i = 0; i < 20; i++) {
      await tester.tap(find.byTooltip('Less').at(1));
      await tester.pump();
    }
    expect(value.totalMarks, value.questionCount);
    expect(value.passMarks, greaterThanOrEqualTo(ExamSettings.minPassMarks(value.totalMarks, 50)));
  });
}
