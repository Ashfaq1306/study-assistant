enum QuestionType {
  mcq('MCQ', 'Multiple choice'),
  trueFalse('TRUE_FALSE', 'True / false'),
  short('SHORT', 'Short answer');

  const QuestionType(this.api, this.label);

  final String api;
  final String label;

  static QuestionType fromApi(String value) => values.firstWhere((t) => t.api == value, orElse: () => mcq);
}

enum Difficulty {
  easy('EASY', 'Easy'),
  medium('MEDIUM', 'Medium'),
  hard('HARD', 'Hard');

  const Difficulty(this.api, this.label);

  final String api;
  final String label;

  static Difficulty fromApi(String value) => values.firstWhere((d) => d.api == value, orElse: () => easy);
}

enum SessionStatus {
  studying,
  examPending,
  passed,
  cancelled;

  static SessionStatus fromApi(String value) => switch (value) {
    'STUDYING' => studying,
    'EXAM_PENDING' => examPending,
    'PASSED' => passed,
    _ => cancelled,
  };

  bool get isActive => this == studying || this == examPending;
}

/// How the unlock exam is built and marked.
class ExamSettings {
  const ExamSettings({
    required this.questionCount,
    required this.totalMarks,
    required this.passMarks,
    required this.questionTypes,
    this.difficulty = Difficulty.easy,
  });

  final int questionCount;
  final int totalMarks;
  final int passMarks;
  final List<QuestionType> questionTypes;
  final Difficulty difficulty;

  int get passPercent => totalMarks == 0 ? 0 : (passMarks * 100 / totalMarks).round();

  /// Smallest pass mark allowed for [totalMarks] at [minPercent].
  static int minPassMarks(int totalMarks, int minPercent) => (totalMarks * minPercent / 100).ceil();

  ExamSettings copyWith({
    int? questionCount,
    int? totalMarks,
    int? passMarks,
    List<QuestionType>? questionTypes,
    Difficulty? difficulty,
  }) => ExamSettings(
    questionCount: questionCount ?? this.questionCount,
    totalMarks: totalMarks ?? this.totalMarks,
    passMarks: passMarks ?? this.passMarks,
    questionTypes: questionTypes ?? this.questionTypes,
    difficulty: difficulty ?? this.difficulty,
  );

  factory ExamSettings.fromJson(Map<String, Object?> json) => ExamSettings(
    questionCount: (json['questionCount']! as num).toInt(),
    totalMarks: (json['totalMarks']! as num).toInt(),
    passMarks: (json['passMarks']! as num).toInt(),
    questionTypes: [for (final t in json['questionTypes']! as List<Object?>) QuestionType.fromApi(t! as String)],
    difficulty: Difficulty.fromApi(json['difficulty'] as String? ?? 'EASY'),
  );

  Map<String, Object?> toJson() => {
    'questionCount': questionCount,
    'totalMarks': totalMarks,
    'passMarks': passMarks,
    'questionTypes': [for (final t in questionTypes) t.api],
    'difficulty': difficulty.api,
  };
}

class StudySession {
  const StudySession({
    required this.id,
    required this.subject,
    required this.topics,
    required this.plannedMinutes,
    required this.status,
    required this.lockedApps,
    required this.strict,
    required this.exam,
    required this.startedAt,
    required this.endsAt,
    required this.canFinishAt,
    required this.studiedMinutes,
    this.notes = '',
    this.photoIds = const [],
    this.studyEndedAt,
    this.completedAt,
  });

  final String id;
  final String subject;
  final String topics;
  final int plannedMinutes;
  final SessionStatus status;
  final List<String> lockedApps;
  final bool strict;
  final ExamSettings exam;
  final DateTime startedAt;
  final DateTime endsAt;
  final DateTime canFinishAt;
  final DateTime? studyEndedAt;
  final DateTime? completedAt;
  final int studiedMinutes;

  /// The student's plan, in their own words.
  final String notes;

  /// Photos of what they are studying (load with [StudyPhoto]).
  final List<String> photoIds;

  factory StudySession.fromJson(Map<String, Object?> json) => StudySession(
    id: json['id']! as String,
    subject: json['subject']! as String,
    topics: json['topics']! as String,
    plannedMinutes: (json['plannedMinutes']! as num).toInt(),
    status: SessionStatus.fromApi(json['status']! as String),
    lockedApps: [for (final p in json['lockedApps']! as List<Object?>) p! as String],
    strict: json['strict'] as bool? ?? true,
    exam: ExamSettings.fromJson(json['exam']! as Map<String, Object?>),
    startedAt: DateTime.parse(json['startedAt']! as String),
    endsAt: DateTime.parse(json['endsAt']! as String),
    canFinishAt: DateTime.parse(json['canFinishAt']! as String),
    studyEndedAt: json['studyEndedAt'] == null ? null : DateTime.parse(json['studyEndedAt']! as String),
    completedAt: json['completedAt'] == null ? null : DateTime.parse(json['completedAt']! as String),
    studiedMinutes: (json['studiedMinutes'] as num?)?.toInt() ?? 0,
    notes: json['notes'] as String? ?? '',
    photoIds: [for (final p in json['photoIds'] as List<Object?>? ?? const []) p! as String],
  );
}

class StudyStats {
  const StudyStats({
    required this.todayMinutes,
    required this.streakDays,
    required this.week,
    required this.totalMinutes,
    required this.sessionsCompleted,
  });

  final int todayMinutes;
  final int streakDays;
  final List<({DateTime day, int minutes})> week;
  final int totalMinutes;
  final int sessionsCompleted;

  factory StudyStats.fromJson(Map<String, Object?> json) => StudyStats(
    todayMinutes: (json['todayMinutes']! as num).toInt(),
    streakDays: (json['streakDays']! as num).toInt(),
    week: [
      for (final d in json['week']! as List<Object?>)
        (
          day: DateTime.parse((d! as Map<String, Object?>)['day']! as String),
          minutes: ((d as Map<String, Object?>)['minutes']! as num).toInt(),
        ),
    ],
    totalMinutes: (json['totalMinutes']! as num).toInt(),
    sessionsCompleted: (json['sessionsCompleted']! as num).toInt(),
  );
}
