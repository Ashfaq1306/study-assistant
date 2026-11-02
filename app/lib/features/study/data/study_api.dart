import 'dart:convert';
import 'dart:typed_data';

import '../../../core/network/api_client.dart';
import '../domain/study_session.dart';

class StartSessionRequest {
  const StartSessionRequest({
    required this.subject,
    required this.topics,
    required this.plannedMinutes,
    required this.exam,
    this.notes = '',
    this.lockedApps = const [],
    this.strict = true,
  });

  final String subject;
  final String topics;
  final int plannedMinutes;
  final ExamSettings exam;
  final String notes;
  final List<String> lockedApps;
  final bool strict;

  Json toJson() => {
    'subject': subject.trim(),
    'topics': topics.trim(),
    'notes': notes.trim(),
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

  /// Adds a photo of the study material; returns the session's photo ids.
  Future<List<String>> addPhoto(String sessionId, Uint8List bytes, {String mime = 'image/jpeg'}) async {
    final json = await _client.post(
      '/v1/sessions/$sessionId/photos',
      data: {'mime': mime, 'data': base64Encode(bytes)},
      timeout: const Duration(seconds: 60),
    );
    return [for (final p in json['photoIds']! as List<Object?>) p! as String];
  }

  Future<List<String>> removePhoto(String sessionId, String photoId) async {
    final json = await _client.delete('/v1/sessions/$sessionId/photos/$photoId');
    return [for (final p in json['photoIds']! as List<Object?>) p! as String];
  }

  Future<Uint8List> photo(String photoId) => _client.getBytes('/v1/photos/$photoId');

  Future<StudyStats> stats() async {
    final offset = DateTime.now().timeZoneOffset.inMinutes;
    return StudyStats.fromJson(await _client.get('/v1/sessions/stats?utcOffsetMinutes=$offset'));
  }
}
