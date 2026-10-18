import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredSession {
  const StoredSession({required this.accessToken, required this.refreshToken, this.userJson});

  final String accessToken;
  final String refreshToken;

  /// Last known profile, so the app can open offline.
  final String? userJson;
}

/// Persists the signed-in session. Abstract so tests can use memory.
abstract interface class TokenStore {
  Future<StoredSession?> read();
  Future<void> save({required String accessToken, required String refreshToken});
  Future<void> saveUser(String userJson);
  Future<void> clear();
}

/// Keystore/Keychain-backed storage.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _access = 'auth.access_token';
  static const _refresh = 'auth.refresh_token';
  static const _user = 'auth.user';

  @override
  Future<StoredSession?> read() async {
    final values = await _storage.readAll();
    final access = values[_access];
    final refresh = values[_refresh];
    if (access == null || refresh == null) return null;
    return StoredSession(accessToken: access, refreshToken: refresh, userJson: values[_user]);
  }

  @override
  Future<void> save({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _access, value: accessToken);
    await _storage.write(key: _refresh, value: refreshToken);
  }

  @override
  Future<void> saveUser(String userJson) => _storage.write(key: _user, value: userJson);

  @override
  Future<void> clear() async {
    await Future.wait([_storage.delete(key: _access), _storage.delete(key: _refresh), _storage.delete(key: _user)]);
  }
}

class MemoryTokenStore implements TokenStore {
  StoredSession? _session;

  @override
  Future<StoredSession?> read() async => _session;

  @override
  Future<void> save({required String accessToken, required String refreshToken}) async {
    _session = StoredSession(accessToken: accessToken, refreshToken: refreshToken, userJson: _session?.userJson);
  }

  @override
  Future<void> saveUser(String userJson) async {
    final s = _session;
    if (s != null) {
      _session = StoredSession(accessToken: s.accessToken, refreshToken: s.refreshToken, userJson: userJson);
    }
  }

  @override
  Future<void> clear() async => _session = null;
}
