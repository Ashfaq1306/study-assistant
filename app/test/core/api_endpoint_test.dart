import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/core/network/api_client.dart';
import 'package:study_assistant/core/network/api_endpoint.dart';
import 'package:study_assistant/core/storage/token_store.dart';

/// Answers requests from a handler instead of the network; a thrown DioException simulates no connection.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final requests = <RequestOptions>[];

  /// Base URLs as sent (a retry reuses and changes the same RequestOptions).
  final baseUrls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    baseUrls.add(options.baseUrl);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody text(int status, String body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(body, status, headers: headers);

ResponseBody okJson() => text(
  200,
  '{"ok":true}',
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody discovery(String url) => text(200, jsonEncode({'apiBaseUrl': url}));

Never offline(RequestOptions o) => throw DioException.connectionError(requestOptions: o, reason: 'Failed host lookup');

const discoveryUrl = 'https://gist.example/raw/endpoint.json';

void main() {
  late DateTime now;

  setUp(() => now = DateTime(2026, 11, 1, 12));

  ApiEndpoint endpoint(FakeAdapter file, {String fallback = 'https://old.example'}) =>
      ApiEndpoint(fallback: fallback, discoveryUrl: discoveryUrl, dio: Dio()..httpClientAdapter = file, now: () => now);

  group('ApiEndpoint', () {
    test('takes a new HTTPS address from the file', () async {
      final e = endpoint(FakeAdapter((_) => discovery('https://new.example/')));
      expect(await e.refresh(), isTrue);
      expect(e.value, 'https://new.example');
    });

    test('never takes a plain HTTP address', () async {
      final e = endpoint(FakeAdapter((_) => discovery('http://evil.example')));
      expect(await e.refresh(), isFalse);
      expect(e.value, 'https://old.example');
    });

    test('keeps the address when the file is broken or unreachable', () async {
      expect(await endpoint(FakeAdapter((_) => text(200, 'not json'))).refresh(), isFalse);
      expect(await endpoint(FakeAdapter((_) => text(404, ''))).refresh(), isFalse);
      expect(await endpoint(FakeAdapter(offline)).refresh(), isFalse);
    });

    test('shares one request and waits between reads', () async {
      final file = FakeAdapter((_) => discovery('https://new.example'));
      final e = endpoint(file);
      await Future.wait([e.refresh(), e.refresh(), e.refresh()]);
      expect(file.requests, hasLength(1));

      await e.refresh();
      expect(file.requests, hasLength(1), reason: 'too soon after the last read');

      now = now.add(ApiEndpoint.minRefreshGap);
      await e.refresh();
      expect(file.requests, hasLength(2));
    });

    test('does nothing without a discovery file', () async {
      final e = ApiEndpoint(fallback: 'http://127.0.0.1:8080');
      expect(await e.refresh(force: true), isFalse);
      expect(e.value, 'http://127.0.0.1:8080');
    });
  });

  group('ApiClient with an endpoint', () {
    late MemoryTokenStore store;

    setUp(() async {
      store = MemoryTokenStore();
      await store.save(accessToken: 'a', refreshToken: 'r');
    });

    test('finds the server at its new address and retries once', () async {
      final api = FakeAdapter((o) => o.baseUrl == 'https://new.example' ? okJson() : offline(o));
      final e = endpoint(FakeAdapter((_) => discovery('https://new.example')));
      final client = ApiClient(
        baseUrl: 'unused',
        store: store,
        endpoint: e,
        dio: Dio(BaseOptions(baseUrl: e.value, responseType: ResponseType.json))..httpClientAdapter = api,
        refreshDio: Dio(BaseOptions(baseUrl: e.value)),
      );

      final result = await client.get('/v1/me');

      expect(result['ok'], isTrue);
      expect(api.baseUrls, ['https://old.example', 'https://new.example']);
      expect(client.baseUrl, 'https://new.example', reason: 'later requests go straight to the new address');
    });

    test('a Cloudflare 530 (tunnel gone) also looks the address up again', () async {
      final api = FakeAdapter(
        (o) => o.baseUrl == 'https://new.example'
            ? okJson()
            : text(
                530,
                'error code: 1033',
                headers: {
                  'server': ['cloudflare'],
                },
              ),
      );
      final e = endpoint(FakeAdapter((_) => discovery('https://new.example')));
      final client = ApiClient(
        baseUrl: 'unused',
        store: store,
        endpoint: e,
        dio: Dio(BaseOptions(baseUrl: e.value))..httpClientAdapter = api,
        refreshDio: Dio(BaseOptions(baseUrl: e.value)),
      );

      expect((await client.get('/v1/me'))['ok'], isTrue);
    });

    test('an unreachable server at an unchanged address still fails', () async {
      final api = FakeAdapter(offline);
      final e = endpoint(FakeAdapter((_) => discovery('https://old.example')));
      final client = ApiClient(
        baseUrl: 'unused',
        store: store,
        endpoint: e,
        dio: Dio(BaseOptions(baseUrl: e.value))..httpClientAdapter = api,
        refreshDio: Dio(BaseOptions(baseUrl: e.value)),
      );

      await expectLater(client.get('/v1/me'), throwsA(anything));
      expect(api.requests, hasLength(1));
    });
  });
}
