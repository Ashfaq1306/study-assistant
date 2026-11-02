import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the API is right now.
///
/// A server on a home computer is published through a tunnel whose address can
/// change when it restarts. The address is kept in a small JSON file at
/// [discoveryUrl] (`{"apiBaseUrl": "https://…"}`), read at start-up and again
/// whenever the server stops answering. The last address that worked is cached
/// on the phone, so the app starts on it even before the file is read.
///
/// Without a [discoveryUrl] (local development) the [fallback] is used as is.
class ApiEndpoint extends ValueNotifier<String> {
  ApiEndpoint({required String fallback, this.discoveryUrl, this._prefs, Dio? dio, DateTime Function()? now})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              responseType: ResponseType.plain,
            ),
          ),
      _now = now ?? DateTime.now,
      super(fallback);

  static const _cacheKey = 'api_base_url';

  /// Don't ask the discovery file more often than this when the server is down.
  static const minRefreshGap = Duration(seconds: 15);

  final String? discoveryUrl;
  final SharedPreferencesAsync? _prefs;
  final Dio _dio;
  final DateTime Function() _now;

  Future<bool>? _inFlight;
  DateTime? _lastRefresh;

  bool get discoverable => discoveryUrl != null && discoveryUrl!.isNotEmpty;

  /// Starts from the last address that worked, if there is one.
  Future<void> loadCached() async {
    if (!discoverable) return;
    try {
      final cached = await _prefs?.getString(_cacheKey);
      if (cached != null && isAcceptable(cached)) value = cached;
    } on Object {
      // A broken cache only means starting from the built-in address.
    }
  }

  /// Reads the discovery file. True when the address changed.
  ///
  /// Concurrent callers share one request, and calls closer together than
  /// [minRefreshGap] return false straight away (unless [force] is set), so a
  /// burst of failing requests cannot hammer the file.
  Future<bool> refresh({bool force = false}) {
    if (!discoverable) return Future.value(false);
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final last = _lastRefresh;
    if (!force && last != null && _now().difference(last) < minRefreshGap) return Future.value(false);
    _lastRefresh = _now();
    return _inFlight = _fetch().whenComplete(() => _inFlight = null);
  }

  Future<bool> _fetch() async {
    try {
      // The query string skips stale CDN copies of the file.
      final res = await _dio.get<String>(discoveryUrl!, queryParameters: {'t': _now().millisecondsSinceEpoch});
      final json = jsonDecode(res.data ?? '');
      final url = json is Map ? json['apiBaseUrl'] : null;
      if (url is! String || !isAcceptable(url)) return false;
      final normalized = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
      if (normalized == value) return false;
      value = normalized;
      unawaited(_save(normalized));
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _save(String url) async {
    try {
      await _prefs?.setString(_cacheKey, url);
    } on Object {
      // Not fatal: the next start reads the file again.
    }
  }

  /// Only HTTPS addresses are taken from the file, so it can never downgrade the app to plain HTTP.
  @visibleForTesting
  static bool isAcceptable(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty && !uri.hasQuery && !uri.hasFragment;
  }
}
