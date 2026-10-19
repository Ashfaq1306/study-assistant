import '../../study/domain/study_session.dart';

enum ExamStatus {
  active,
  submitted,
  expired;

  static ExamStatus fromApi(String v) => switch (v) {
    'SUBMITTED' => submitted,
    'EXPIRED' => expired,
    _ => active,
  };
}

class ExamQuestion {
  const ExamQuestion({
    required this.id,
    required this.type,
    required this.prompt,
    required this.options,
    required this.marks,
  });

  final String id;
  final QuestionType type;
  final String prompt;

  /// MCQ: four choices. True/false: ["True", "False"]. Short: empty.
  final List<String> options;
  final int marks;

  /// What the server expects for option [index]: the MCQ index, or "true"/"false".
  String answerForOption(int index) => type == QuestionType.trueFalse ? (index == 0 ? 'true' : 'false') : '$index';

  factory ExamQuestion.fromJson(Map<String, Object?> json) => ExamQuestion(
    id: json['id']! as String,
    type: QuestionType.fromApi(json['type']! as String),
    prompt: json['prompt']! as String,
    options: [for (final o in json['options']! as List<Object?>) o! as String],
    marks: (json['marks']! as num).toInt(),
  );
}

class QuestionResult {
  const QuestionResult({
    required this.id,
    required this.given,
    required this.correct,
    required this.awarded,
    required this.marks,
    required this.correctAnswer,
    required this.explanation,
    required this.feedback,
  });

  final String id;
  final String? given;
  final bool correct;
  final double awarded;
  final int marks;
  final String correctAnswer;
  final String explanation;
  final String feedback;

  factory QuestionResult.fromJson(Map<String, Object?> json) => QuestionResult(
    id: json['id']! as String,
    given: json['given'] as String?,
    correct: json['correct']! as bool,
    awarded: (json['awarded']! as num).toDouble(),
    marks: (json['marks']! as num).toInt(),
    correctAnswer: json['correctAnswer']! as String,
    explanation: json['explanation'] as String? ?? '',
    feedback: json['feedback'] as String? ?? '',
  );
}

class ExamResult {
  const ExamResult({required this.score, required this.passed, required this.questions});

  final double score;
  final bool passed;
  final List<QuestionResult> questions;

  factory ExamResult.fromJson(Map<String, Object?> json) => ExamResult(
    score: (json['score']! as num).toDouble(),
    passed: json['passed']! as bool,
    questions: [
      for (final q in json['questions']! as List<Object?>) QuestionResult.fromJson(q! as Map<String, Object?>),
    ],
  );
}

class Exam {
  const Exam({
    required this.id,
    required this.subject,
    required this.topics,
    required this.source,
    required this.status,
    required this.totalMarks,
    required this.passMarks,
    required this.expiresAt,
    required this.questions,
    this.sessionId,
    this.result,
  });

  final String id;
  final String? sessionId;
  final String subject;
  final String topics;

  /// "AI", "PRACTICE" (built-in questions) or "PARENT".
  final String source;
  final ExamStatus status;
  final int totalMarks;
  final int passMarks;
  final DateTime expiresAt;
  final List<ExamQuestion> questions;
  final ExamResult? result;

  bool get isPractice => source == 'PRACTICE';

  factory Exam.fromJson(Map<String, Object?> json) => Exam(
    id: json['id']! as String,
    sessionId: json['sessionId'] as String?,
    subject: json['subject']! as String,
    topics: json['topics']! as String,
    source: json['source']! as String,
    status: ExamStatus.fromApi(json['status']! as String),
    totalMarks: (json['totalMarks']! as num).toInt(),
    passMarks: (json['passMarks']! as num).toInt(),
    expiresAt: DateTime.parse(json['expiresAt']! as String),
    questions: [for (final q in json['questions']! as List<Object?>) ExamQuestion.fromJson(q! as Map<String, Object?>)],
    result: json['result'] is Map ? ExamResult.fromJson(Map<String, Object?>.from(json['result']! as Map)) : null,
  );
}
