import '../../../core/network/api_client.dart';
import '../../study/domain/study_session.dart';
import '../domain/parent_models.dart';

/// /v1/parent (a parent's view of their children) and /v1/notifications.
class ParentApi {
  const ParentApi(this._client);

  final ApiClient _client;

  int get _offset => DateTime.now().timeZoneOffset.inMinutes;

  Future<List<ChildSummary>> children() async {
    final json = await _client.get('/v1/parent/children?utcOffsetMinutes=$_offset');
    return [for (final c in json['children']! as List<Object?>) ChildSummary.fromJson(c! as Json)];
  }

  Future<ChildDetail> child(String id) async =>
      ChildDetail.fromJson(await _client.get('/v1/parent/children/$id?utcOffsetMinutes=$_offset'));

  Future<ParentLock> lock({
    required String childId,
    required String title,
    required String subject,
    required String topics,
    required List<String> lockedApps,
    required bool strict,
    required ExamSettings exam,
    String? questionSetId,
  }) async => ParentLock.fromJson(
    await _client.post(
      '/v1/parent/children/$childId/locks',
      data: {
        'title': title.trim(),
        'subject': subject.trim(),
        'topics': topics.trim(),
        'lockedApps': lockedApps,
        'strict': strict,
        'exam': exam.toJson(),
        'questionSetId': ?questionSetId,
      },
    ),
  );

  Future<ParentLock> cancelLock(String lockId) async =>
      ParentLock.fromJson(await _client.post('/v1/parent/locks/$lockId/cancel'));

  Future<List<QuestionSet>> questionSets() async {
    final json = await _client.get('/v1/parent/question-sets');
    return [for (final s in json['questionSets']! as List<Object?>) QuestionSet.fromJson(s! as Json)];
  }

  Future<QuestionSet> saveQuestionSet(QuestionSet set) async => QuestionSet.fromJson(
    set.id == null
        ? await _client.post('/v1/parent/question-sets', data: set.toJson())
        : await _client.put('/v1/parent/question-sets/${set.id}', data: set.toJson()),
  );

  Future<void> deleteQuestionSet(String id) => _client.delete('/v1/parent/question-sets/$id');

  Future<({List<AppNotification> items, int unread})> notifications() async {
    final json = await _client.get('/v1/notifications?limit=50');
    return (
      items: [for (final n in json['notifications']! as List<Object?>) AppNotification.fromJson(n! as Json)],
      unread: (json['unread']! as num).toInt(),
    );
  }

  Future<void> markAllRead() => _client.post('/v1/notifications/read');
}
