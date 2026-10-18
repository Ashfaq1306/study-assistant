import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_store.dart';
import '../data/auth_api.dart';
import '../domain/app_user.dart';
import '../domain/otp.dart';

sealed class AuthState {
  const AuthState();
}

/// Still reading the saved session at startup.
class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut();
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.user);

  final AppUser user;
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Owns the session. Screens call these methods and show any [ApiException].
class AuthController extends Notifier<AuthState> {
  AuthApi get _api => ref.read(authApiProvider);
  TokenStore get _store => ref.read(tokenStoreProvider);

  @override
  AuthState build() {
    ref.read(apiClientProvider).onSessionExpired = () {
      if (ref.mounted) state = const AuthSignedOut();
    };
    unawaited(_restore());
    return const AuthUnknown();
  }

  /// Never throws and always leaves [AuthUnknown], so the splash cannot hang.
  Future<void> _restore() async {
    try {
      final saved = await _store.read();
      if (saved == null) return _set(const AuthSignedOut());
      try {
        await _setUser(await _api.me());
      } on ApiException {
        // The interceptor clears the store only when the server rejects the
        // refresh token. If tokens remain, we are offline or the server had a
        // hiccup: open with the last known profile and catch up later.
        final stillSaved = await _store.read();
        final cached = stillSaved == null ? null : _decodeUser(stillSaved.userJson);
        _set(cached != null ? AuthSignedIn(cached) : const AuthSignedOut());
      }
    } on Object {
      // Keystore or storage failure: the user can still sign in again.
      _set(const AuthSignedOut());
    }
  }

  static AppUser? _decodeUser(String? json) {
    if (json == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(json) as Map<String, Object?>);
    } on Object {
      return null; // Saved by an older app version with a different shape.
    }
  }

  /// Returns null when signed in, or the pending verification when the
  /// account still needs its code.
  Future<PendingVerification?> login(String identifier, String password) async {
    try {
      await _signIn(await _api.login(identifier, password));
      return null;
    } on ApiException catch (e) {
      if (e.code != 'ACCOUNT_NOT_VERIFIED') rethrow;
      final verification = e.details['verification'];
      return PendingVerification(
        userId: e.details['userId']! as String,
        channel: OtpChannel.fromApi(e.details['channel'] as String? ?? 'EMAIL'),
        delivery: verification is Map ? OtpDelivery.fromJson(Map<String, Object?>.from(verification)) : null,
      );
    }
  }

  Future<PendingVerification> register(RegisterRequest request) => _api.register(request);

  Future<void> verify(String userId, String code) async => _signIn(await _api.verify(userId, code));

  Future<OtpDelivery> resendCode(String userId, {OtpChannel? channel}) => _api.resend(userId, channel: channel);

  Future<void> forgotPassword(String identifier) => _api.forgotPassword(identifier);

  Future<void> resetPassword(String identifier, String code, String newPassword) async =>
      _signIn(await _api.resetPassword(identifier, code, newPassword));

  /// Re-reads the profile, e.g. after a parent links.
  Future<AppUser> refreshUser() async {
    final user = await _api.me();
    await _setUser(user);
    return user;
  }

  Future<void> logout() async {
    final saved = await _store.read();
    if (saved != null) {
      try {
        await _api.logout(saved.refreshToken);
      } on ApiException {
        // Signing out locally still works offline; the server session expires.
      }
    }
    await _store.clear();
    _set(const AuthSignedOut());
  }

  Future<void> _signIn(SignedInSession session) async {
    await _store.save(accessToken: session.tokens.accessToken, refreshToken: session.tokens.refreshToken);
    await _setUser(session.user);
  }

  Future<void> _setUser(AppUser user) async {
    await _store.saveUser(jsonEncode(user.toJson()));
    _set(AuthSignedIn(user));
  }

  void _set(AuthState next) {
    if (ref.mounted) state = next;
  }
}
