import 'dart:typed_data';

import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/token_store.dart';
import 'api_exception.dart';
import 'server_clock.dart';

typedef Json = Map<String, Object?>;

/// Thin HTTP layer: JSON in and out, server errors become [ApiException],
/// and an expired access token is refreshed once, transparently.
class ApiClient {
  ApiClient({required String baseUrl, required this._store, Dio? dio, Dio? refreshDio})
    : _dio = dio ?? Dio(_options(baseUrl)),
      _refreshDio = refreshDio ?? Dio(_options(baseUrl)) {
    _dio.interceptors
      ..add(_AuthInterceptor(this))
      ..add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            clock.observe(response.headers.value('x-server-time'));
            handler.next(response);
          },
        ),
      );
  }

  static BaseOptions _options(String baseUrl) => BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    contentType: Headers.jsonContentType,
    responseType: ResponseType.json,
  );

  final TokenStore _store;
  final Dio _dio;

  /// Separate instance without interceptors, so refreshing cannot recurse.
  final Dio _refreshDio;

  /// Server time, kept in sync from every response.
  final ServerClock clock = ServerClock();

  /// Called when the refresh token is rejected: the user must sign in again.
  void Function()? onSessionExpired;

  Future<Json> get(String path, {bool authenticated = true, Map<String, String>? headers}) =>
      _send(() => _dio.get<Object?>(path, options: _auth(authenticated, headers)));

  /// [timeout] overrides the default wait, e.g. for AI calls that take a while.
  Future<Json> post(
    String path, {
    Object? data,
    bool authenticated = true,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _send(() => _dio.post<Object?>(path, data: data ?? const {}, options: _auth(authenticated, headers, timeout)));

  Future<Json> patch(String path, {Object? data}) => _send(() => _dio.patch<Object?>(path, data: data));

  Future<Json> put(String path, {Object? data}) => _send(() => _dio.put<Object?>(path, data: data));

  Future<Json> delete(String path) => _send(() => _dio.delete<Object?>(path));

  /// Raw bytes, e.g. a photo. Signed in like any other request.
  Future<Uint8List> getBytes(String path) async {
    try {
      final res = await _dio.get<List<int>>(path, options: _auth(true).copyWith(responseType: ResponseType.bytes));
      return Uint8List.fromList(res.data ?? const []);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  static Options _auth(bool authenticated, [Map<String, String>? headers, Duration? timeout]) =>
      Options(extra: {_AuthInterceptor.authKey: authenticated}, headers: headers, receiveTimeout: timeout);

  Future<Json> _send(Future<Response<Object?>> Function() request) async {
    try {
      final data = (await request()).data;
      return data is Map ? Map<String, Object?>.from(data) : const {};
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<_RefreshResult> _refresh(String refreshToken) async {
    try {
      final res = await _refreshDio.post<Object?>('/v1/auth/refresh', data: {'refreshToken': refreshToken});
      final tokens = (res.data! as Map)['tokens'] as Map;
      final access = tokens['accessToken'] as String;
      await _store.save(accessToken: access, refreshToken: tokens['refreshToken'] as String);
      return _RefreshResult.refreshed(access);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Offline is not the same as signed out: keep the session for later.
      return status == 401 || status == 400 ? const _RefreshResult.rejected() : const _RefreshResult.failed();
    }
  }
}

class _RefreshResult {
  const _RefreshResult.refreshed(String this.accessToken) : rejected = false;
  const _RefreshResult.rejected() : accessToken = null, rejected = true;
  const _RefreshResult.failed() : accessToken = null, rejected = false;

  final String? accessToken;
  final bool rejected;
}

/// Attaches the access token and recovers from an expired one.
///
/// Deliberately a plain [Interceptor], not a QueuedInterceptor: retrying from
/// inside a queued `onError` deadlocks dio when the retry itself fails.
/// Concurrent 401s still cause a single refresh because they share [_refreshing].
class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._client);

  static const authKey = 'authenticated';
  static const _retriedKey = 'retried';

  final ApiClient _client;
  Future<_RefreshResult>? _refreshing;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra[authKey] != false) {
      final session = await _client._store.read();
      if (session != null) options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    if (err.response?.statusCode != 401 || request.extra[authKey] == false || request.extra[_retriedKey] == true) {
      return handler.next(err);
    }

    final sentToken = (request.headers['Authorization'] as String?)?.replaceFirst('Bearer ', '');
    final result = await (_refreshing ??= _refreshUnlessDone(sentToken).whenComplete(() => _refreshing = null));
    if (result.accessToken == null) {
      if (result.rejected) {
        await _client._store.clear();
        _client.onSessionExpired?.call();
      }
      return handler.next(err);
    }

    request
      ..headers['Authorization'] = 'Bearer ${result.accessToken}'
      ..extra[_retriedKey] = true;
    try {
      handler.resolve(await _client._dio.fetch<Object?>(request));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// Reads the store *inside* the shared refresh, so a request that failed with
  /// an old token never spends an already-rotated refresh token (the server
  /// would treat that as theft and sign every device out).
  Future<_RefreshResult> _refreshUnlessDone(String? sentToken) async {
    final session = await _client._store.read();
    if (session == null) return const _RefreshResult.rejected();
    if (session.accessToken != sentToken) return _RefreshResult.refreshed(session.accessToken);
    return _client._refresh(session.refreshToken);
  }
}
