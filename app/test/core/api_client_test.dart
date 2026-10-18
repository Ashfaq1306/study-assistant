import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/core/network/api_client.dart';
import 'package:study_assistant/core/network/api_exception.dart';
import 'package:study_assistant/core/storage/token_store.dart';

/// Answers requests from a handler instead of the network.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody unauthorized() => json(401, {
  'error': {'code': 'UNAUTHORIZED', 'message': 'Please sign in again.'},
});

void main() {
  late MemoryTokenStore store;

  setUp(() async {
    store = MemoryTokenStore();
    await store.save(accessToken: 'old-access', refreshToken: 'old-refresh');
  });

  ApiClient client(FakeAdapter api, FakeAdapter refresh) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = api;
    final refreshDio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = refresh;
    return ApiClient(baseUrl: 'http://test', store: store, dio: dio, refreshDio: refreshDio);
  }

  test('sends the access token', () async {
    final api = FakeAdapter((_) => json(200, {'ok': true}));
    await client(api, FakeAdapter((_) => unauthorized())).get('/v1/me');
    expect(api.requests.single.headers['Authorization'], 'Bearer old-access');
  });

  test('refreshes once on 401 and retries with the new token', () async {
    final api = FakeAdapter(
      (o) => o.headers['Authorization'] == 'Bearer new-access' ? json(200, {'name': 'Nadia'}) : unauthorized(),
    );
    final refresh = FakeAdapter(
      (_) => json(200, {
        'tokens': {'accessToken': 'new-access', 'refreshToken': 'new-refresh'},
      }),
    );

    final result = await client(api, refresh).get('/v1/me');

    expect(result['name'], 'Nadia');
    expect(refresh.requests, hasLength(1));
    final saved = await store.read();
    expect(saved?.accessToken, 'new-access');
    expect(saved?.refreshToken, 'new-refresh');
  });

  test('signs out when the refresh token is rejected', () async {
    var expired = false;
    final c = client(FakeAdapter((_) => unauthorized()), FakeAdapter((_) => unauthorized()))
      ..onSessionExpired = () => expired = true;

    await expectLater(c.get('/v1/me'), throwsA(isA<ApiException>()));
    expect(expired, isTrue);
    expect(await store.read(), isNull);
  });

  test('keeps the session when refresh fails because the server is unreachable', () async {
    final refresh = FakeAdapter((o) => throw DioException.connectionError(requestOptions: o, reason: 'offline'));
    var expired = false;
    final c = client(FakeAdapter((_) => unauthorized()), refresh)..onSessionExpired = () => expired = true;

    await expectLater(c.get('/v1/me'), throwsA(isA<ApiException>()));
    expect(expired, isFalse);
    expect(await store.read(), isNotNull);
  });

  test('does not attach tokens or refresh for sign-in calls', () async {
    final api = FakeAdapter((_) => unauthorized());
    final refresh = FakeAdapter((_) => json(200, {}));
    await expectLater(
      client(api, refresh).post('/v1/auth/login', data: {}, authenticated: false),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
    expect(api.requests.single.headers.containsKey('Authorization'), isFalse);
    expect(refresh.requests, isEmpty);
  });

  test('turns server errors into ApiException with field messages', () async {
    final api = FakeAdapter(
      (_) => json(400, {
        'error': {
          'code': 'VALIDATION_FAILED',
          'message': 'Please check the highlighted fields.',
          'details': {
            'fields': {
              'email': ['Enter a valid email address.'],
            },
          },
        },
      }),
    );
    await expectLater(
      client(api, FakeAdapter((_) => unauthorized())).post('/v1/auth/register', authenticated: false),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'VALIDATION_FAILED')
            .having((e) => e.fieldErrors['email'], 'email', 'Enter a valid email address.'),
      ),
    );
  });

  ResponseBody refreshed() => json(200, {
    'tokens': {'accessToken': 'new-access', 'refreshToken': 'new-refresh'},
  });

  test('a retry that fails after a good refresh reports its error instead of hanging', () async {
    final api = FakeAdapter(
      (o) => o.headers['Authorization'] == 'Bearer new-access'
          ? json(500, {
              'error': {'code': 'INTERNAL', 'message': 'boom'},
            })
          : unauthorized(),
    );
    final c = client(api, FakeAdapter((_) => refreshed()));

    await expectLater(
      c.get('/v1/me').timeout(const Duration(seconds: 2)),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 500)),
    );
    // And the client still works for the next request.
    await expectLater(c.get('/v1/me').timeout(const Duration(seconds: 2)), throwsA(isA<ApiException>()));
  });

  test('parallel 401s share one refresh', () async {
    final api = FakeAdapter(
      (o) => o.headers['Authorization'] == 'Bearer new-access' ? json(200, {'ok': true}) : unauthorized(),
    );
    final refresh = FakeAdapter((_) => refreshed());
    final c = client(api, refresh);

    await Future.wait([c.get('/v1/me'), c.get('/v1/family/links'), c.get('/v1/me')]);
    expect(refresh.requests, hasLength(1));
  });
}
