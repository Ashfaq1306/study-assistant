import '../../study/domain/study_session.dart';

List<T> _list<T>(Object? value, T Function(Map<String, Object?>) parse) => [
  for (final item in value as List<Object?>? ?? const []) parse(item! as Map<String, Object?>),
];

DateTime? _date(Object? value) => value == null ? null : DateTime.parse(value as String).toLocal();

/// How well a child's phone is protected right now.
enum Protection {
  on,
  off,
  shortcutOn,
  stale,
  noPhone;

  static Protection fromApi(String value) => switch (value) {
    'ON' => on,
    'OFF' => off,
    'SHORTCUT_ON' => shortcutOn,
    'STALE' => stale,
    _ => noPhone,
  };

  String get label => switch (this) {
    Protection.on => 'App lock on',
    Protection.off => 'App lock is off',
    Protection.shortcutOn => 'Shortcut could turn the lock off',
    Protection.stale => 'Phone not seen recently',
    Protection.noPhone => 'No phone set up yet',
  };

  bool get ok => this == Protection.on;
}

/// A lock a parent put on a child's apps.
class ParentLock {
  const ParentLock({
    required this.id,
    required this.title,
    required this.subject,
    required this.topics,
    required this.lockedApps,
    required this.strict,
    required this.exam,
    required this.status,
    required this.createdAt,
    this.questionSetId,
    this.endedAt,
  });

  final String id;
  final String title;
  final String subject;
  final String topics;

  /// Package names, or ["*"] for the whole phone.
  final List<String> lockedApps;
  final bool strict;
  final ExamSettings exam;

  /// ACTIVE, PASSED or CANCELLED.
  final String status;
  final String? questionSetId;
  final DateTime createdAt;
  final DateTime? endedAt;

  bool get active => status == 'ACTIVE';
  bool get wholePhone => lockedApps.contains('*');

  factory ParentLock.fromJson(Map<String, Object?> json) => ParentLock(
    id: json['id']! as String,
    title: json['title']! as String,
    subject: json['subject']! as String,
    topics: json['topics']! as String,
    lockedApps: [for (final a in json['lockedApps']! as List<Object?>) a! as String],
    strict: json['strict'] as bool? ?? false,
    exam: ExamSettings.fromJson(json['exam']! as Map<String, Object?>),
    status: json['status']! as String,
    questionSetId: json['questionSetId'] as String?,
    createdAt: _date(json['createdAt'])!,
    endedAt: _date(json['endedAt']),
  );
}

/// One finished exam, as a parent sees it.
class ExamSummary {
  const ExamSummary({
    required this.id,
    required this.subject,
    required this.score,
    required this.totalMarks,
    required this.passMarks,
    required this.passed,
    required this.createdAt,
  });

  final String id;
  final String subject;
  final double? score;
  final int totalMarks;
  final int passMarks;
  final bool passed;
  final DateTime createdAt;

  factory ExamSummary.fromJson(Map<String, Object?> json) => ExamSummary(
    id: json['id']! as String,
    subject: json['subject']! as String,
    score: (json['score'] as num?)?.toDouble(),
    totalMarks: (json['totalMarks']! as num).toInt(),
    passMarks: (json['passMarks']! as num).toInt(),
    passed: json['passed'] as bool? ?? false,
    createdAt: _date(json['createdAt'])!,
  );
}

class ChildSummary {
  const ChildSummary({
    required this.id,
    required this.name,
    required this.age,
    required this.todayStudyMinutes,
    required this.todayScreenMinutes,
    required this.streakDays,
    required this.activeLocks,
    required this.protection,
    this.activeSession,
    this.lastExam,
    this.lastSeenAt,
  });

  final String id;
  final String name;
  final int age;
  final int todayStudyMinutes;
  final int todayScreenMinutes;
  final int streakDays;
  final StudySession? activeSession;
  final List<ParentLock> activeLocks;
  final ExamSummary? lastExam;
  final Protection protection;
  final DateTime? lastSeenAt;

  String get firstName => name.split(RegExp(r'\s+')).first;

  factory ChildSummary.fromJson(Map<String, Object?> json) {
    final protection = json['protection']! as Map<String, Object?>;
    return ChildSummary(
      id: json['id']! as String,
      name: json['name']! as String,
      age: (json['age']! as num).toInt(),
      todayStudyMinutes: (json['todayStudyMinutes']! as num).toInt(),
      todayScreenMinutes: (json['todayScreenMinutes']! as num).toInt(),
      streakDays: (json['streakDays']! as num).toInt(),
      activeSession: json['activeSession'] == null
          ? null
          : StudySession.fromJson(json['activeSession']! as Map<String, Object?>),
      activeLocks: _list(json['activeLocks'], ParentLock.fromJson),
      lastExam: json['lastExam'] == null ? null : ExamSummary.fromJson(json['lastExam']! as Map<String, Object?>),
      protection: Protection.fromApi(protection['status']! as String),
      lastSeenAt: _date(protection['lastSeenAt']),
    );
  }
}

/// Screen time on one day: total and the most used apps.
class ScreenTimeDay {
  const ScreenTimeDay({required this.day, required this.totalMinutes, required this.apps});

  final DateTime day;
  final int totalMinutes;
  final List<({String package, String label, int minutes})> apps;

  factory ScreenTimeDay.fromJson(Map<String, Object?> json) => ScreenTimeDay(
    day: DateTime.parse(json['day']! as String),
    totalMinutes: (json['totalMinutes']! as num).toInt(),
    apps: [
      for (final a in json['apps']! as List<Object?>)
        (
          package: (a! as Map<String, Object?>)['package']! as String,
          label: (a as Map<String, Object?>)['label']! as String,
          minutes: (a['minutes']! as num).toInt(),
        ),
    ],
  );
}

class ChildDetail {
  const ChildDetail({
    required this.summary,
    required this.stats,
    required this.screenTime,
    required this.recentExams,
    required this.recentSessions,
    required this.recentLocks,
    required this.installedApps,
  });

  final ChildSummary summary;
  final StudyStats stats;

  /// Newest day first.
  final List<ScreenTimeDay> screenTime;
  final List<ExamSummary> recentExams;
  final List<StudySession> recentSessions;
  final List<ParentLock> recentLocks;
  final List<({String package, String label})> installedApps;

  factory ChildDetail.fromJson(Map<String, Object?> json) => ChildDetail(
    summary: ChildSummary.fromJson(json),
    stats: StudyStats.fromJson(json['stats']! as Map<String, Object?>),
    screenTime: _list(json['screenTime'], ScreenTimeDay.fromJson),
    recentExams: _list(json['recentExams'], ExamSummary.fromJson),
    recentSessions: _list(json['recentSessions'], StudySession.fromJson),
    recentLocks: _list(json['recentLocks'], ParentLock.fromJson),
    installedApps: [
      for (final a in json['installedApps'] as List<Object?>? ?? const [])
        (
          package: (a! as Map<String, Object?>)['package']! as String,
          label: (a as Map<String, Object?>)['label']! as String,
        ),
    ],
  );
}

/// A parent's own exam questions.
class ParentQuestion {
  const ParentQuestion({
    required this.type,
    required this.prompt,
    required this.answer,
    this.options = const [],
    this.keyPoints = const [],
    this.explanation = '',
  });

  final QuestionType type;
  final String prompt;

  /// MCQ: four choices. Others: empty.
  final List<String> options;

  /// MCQ: the right option's index ("0"–"3"); true/false: "true"/"false"; short: the model answer.
  final String answer;
  final List<String> keyPoints;
  final String explanation;

  factory ParentQuestion.fromJson(Map<String, Object?> json) => ParentQuestion(
    type: QuestionType.fromApi(json['type']! as String),
    prompt: json['prompt']! as String,
    answer: json['answer']! as String,
    options: [for (final o in json['options'] as List<Object?>? ?? const []) o! as String],
    keyPoints: [for (final k in json['keyPoints'] as List<Object?>? ?? const []) k! as String],
    explanation: json['explanation'] as String? ?? '',
  );

  Map<String, Object?> toJson() => {
    'type': type.api,
    'prompt': prompt.trim(),
    'options': type == QuestionType.mcq ? [for (final o in options) o.trim()] : const <String>[],
    'answer': answer.trim(),
    'keyPoints': keyPoints,
    'explanation': explanation.trim(),
  };
}

class QuestionSet {
  const QuestionSet({
    this.id,
    required this.title,
    required this.subject,
    required this.questions,
    this.usedByActiveLocks = 0,
  });

  final String? id;
  final String title;
  final String subject;
  final List<ParentQuestion> questions;
  final int usedByActiveLocks;

  factory QuestionSet.fromJson(Map<String, Object?> json) => QuestionSet(
    id: json['id'] as String?,
    title: json['title']! as String,
    subject: json['subject']! as String,
    questions: _list(json['questions'], ParentQuestion.fromJson),
    usedByActiveLocks: (json['usedByActiveLocks'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toJson() => {
    'title': title.trim(),
    'subject': subject.trim(),
    'questions': [for (final q in questions) q.toJson()],
  };
}

/// An in-app alert (exam results, protection switched off, …).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
  });

  final String id;
  final String kind;
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, Object?> json) => AppNotification(
    id: json['id']! as String,
    kind: json['kind']! as String,
    title: json['title']! as String,
    body: json['body']! as String,
    read: json['read'] as bool? ?? false,
    createdAt: _date(json['createdAt'])!,
  );
}
