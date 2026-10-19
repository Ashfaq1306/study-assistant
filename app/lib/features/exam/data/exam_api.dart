import '../../../core/network/api_client.dart';
import '../domain/exam.dart';

/// Writing or grading an exam with AI can take a little while. The server gives up well before this.
const _aiTimeout = Duration(seconds: 150);

/// /v1/sessions/:id/exam, /v1/exams and /v1/tutor.
class ExamApi {
  const ExamApi(this._client);

  final ApiClient _client;

  Future<Exam> startForSession(String sessionId) async =>
      Exam.fromJson(await _client.post('/v1/sessions/$sessionId/exam', timeout: _aiTimeout));

  Future<Exam> submit(String examId, Map<String, String> answers) async =>
      Exam.fromJson(await _client.post('/v1/exams/$examId/submit', data: {'answers': answers}, timeout: _aiTimeout));

  Future<Exam> get(String examId) async => Exam.fromJson(await _client.get('/v1/exams/$examId'));

  Future<List<Exam>> history({int limit = 20}) async {
    final json = await _client.get('/v1/exams?limit=$limit');
    return [for (final e in json['exams']! as List<Object?>) Exam.fromJson(e! as Map<String, Object?>)];
  }

  Future<({String reply, int remainingToday})> askTutor(List<({String role, String content})> messages) async {
    final json = await _client.post(
      '/v1/tutor',
      data: {
        'messages': [
          for (final m in messages) {'role': m.role, 'content': m.content},
        ],
      },
      timeout: _aiTimeout,
    );
    return (reply: json['reply']! as String, remainingToday: (json['remainingToday']! as num).toInt());
  }
}
