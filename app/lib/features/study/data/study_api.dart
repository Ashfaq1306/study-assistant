import '../../../core/network/api_client.dart';
import '../domain/study_session.dart';

class StartSessionRequest {
  const StartSessionRequest({
    required this.subject,
    required this.topics,
    required this.plannedMinutes,
    required this.exam,
    this.lockedApps = const [],
    this.strict = true,
  });

  final String subject;
  final String topics;
  final int plannedMinutes;
  final ExamSettings exam;
  final List<String> lockedApps;
  final bool strict;

  Json toJson() => {
    'subject': subject.trim(),
    'topics': topics.trim(),
    'plannedMinutes': plannedMinutes,
    'lockedApps': lockedApps,
    'strict': strict,
    'exam': exam.toJson(),
  };
}

/// Server endpoints under /v1/sessions.
class StudyApi {
  const StudyApi(this._client);

  final ApiClient _client;

  Future<StudySession> start(StartSessionRequest request) async =>
      StudySession.fromJson(await _client.post('/v1/sessions', data: request.toJson()));

  Future<StudySession?> active() async {
    final json = await _client.get('/v1/sessions/active');
    final session = json['session'];
    return session is Map ? StudySession.fromJson(Map<String, Object?>.from(session)) : null;
  }

  Future<StudySession> finish(String id) async => StudySession.fromJson(await _client.post('/v1/sessions/$id/finish'));

  Future<List<StudySession>> history({int limit = 20}) async {
    final json = await _client.get('/v1/sessions?limit=$limit');
    return [for (final s in json['sessions']! as List<Object?>) StudySession.fromJson(s! as Map<String, Object?>)];
  }

  Future<StudyStats> stats() async {
    final offset = DateTime.now().timeZoneOffset.inMinutes;
    return StudyStats.fromJson(await _client.get('/v1/sessions/stats?utcOffsetMinutes=$offset'));
  }
}
