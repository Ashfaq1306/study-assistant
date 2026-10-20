import 'dart:convert';
import 'dart:typed_data';

import '../../../core/network/api_client.dart';
import '../domain/calendar_event.dart';

/// /v1/calendar.
class CalendarApi {
  const CalendarApi(this._client);

  final ApiClient _client;

  Future<List<CalendarEvent>> list() async {
    final json = await _client.get('/v1/calendar');
    return [for (final e in json['events']! as List<Object?>) CalendarEvent.fromJson(e! as Map<String, Object?>)];
  }

  Future<CalendarEvent> create(CalendarEvent event) async =>
      CalendarEvent.fromJson(await _client.post('/v1/calendar', data: event.toJson()));

  Future<CalendarEvent> update(CalendarEvent event) async =>
      CalendarEvent.fromJson(await _client.put('/v1/calendar/${event.id}', data: event.toJson()));

  Future<void> delete(String id) => _client.delete('/v1/calendar/$id');

  Future<List<CalendarEvent>> saveAll(List<CalendarEvent> events) async {
    final json = await _client.post(
      '/v1/calendar/bulk',
      data: {
        'events': [for (final e in events) e.toJson()],
      },
    );
    return [for (final e in json['events']! as List<Object?>) CalendarEvent.fromJson(e! as Map<String, Object?>)];
  }

  /// Asks the AI to read an academic calendar (a PDF or photo, or pasted text). Nothing is saved.
  Future<List<CalendarEvent>> read({String? text, Uint8List? file, String? mime}) async {
    final json = await _client.post(
      '/v1/calendar/import',
      data: {
        if (text != null && text.trim().isNotEmpty) 'text': text.trim(),
        if (file != null && mime != null) 'file': {'mime': mime, 'data': base64Encode(file)},
        'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      },
      timeout: const Duration(seconds: 150),
    );
    return [for (final e in json['events']! as List<Object?>) CalendarEvent.fromJson(e! as Map<String, Object?>)];
  }
}
