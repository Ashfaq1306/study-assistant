import '../../../core/network/api_client.dart';
import '../domain/app_user.dart';
import '../domain/otp.dart';

class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

class SignedInSession {
  const SignedInSession({required this.user, required this.tokens});

  final AppUser user;
  final AuthTokens tokens;

  factory SignedInSession.fromJson(Json json) {
    final tokens = json['tokens']! as Map<String, Object?>;
    return SignedInSession(
      user: AppUser.fromJson(json['user']! as Map<String, Object?>),
      tokens: AuthTokens(
        accessToken: tokens['accessToken']! as String,
        refreshToken: tokens['refreshToken']! as String,
      ),
    );
  }
}

class RegisterRequest {
  const RegisterRequest({
    required this.role,
    required this.name,
    required this.dateOfBirth,
    required this.password,
    required this.otpChannel,
    this.email,
    this.phone,
  });

  final UserRole role;
  final String name;
  final DateTime dateOfBirth;
  final String password;
  final OtpChannel otpChannel;
  final String? email;
  final String? phone;

  Json toJson() => {
    'role': role.api,
    'name': name.trim(),
    'dateOfBirth': _isoDate(dateOfBirth),
    'password': password,
    'otpChannel': otpChannel.api,
    if (email != null && email!.trim().isNotEmpty) 'email': email!.trim(),
    if (phone != null && phone!.trim().isNotEmpty) 'phone': phone!.trim(),
  };

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Server endpoints under /v1/auth and /v1/me.
class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  Future<PendingVerification> register(RegisterRequest request) async {
    final json = await _client.post('/v1/auth/register', data: request.toJson(), authenticated: false);
    final delivery = OtpDelivery.fromJson(json['verification']! as Map<String, Object?>);
    final hasEmail = request.email?.trim().isNotEmpty ?? false;
    final hasPhone = request.phone?.trim().isNotEmpty ?? false;
    return PendingVerification(
      userId: json['userId']! as String,
      channel: delivery.channel,
      delivery: delivery,
      otherChannelAvailable: hasEmail && hasPhone,
    );
  }

  Future<SignedInSession> verify(String userId, String code) async => SignedInSession.fromJson(
    await _client.post('/v1/auth/verify', data: {'userId': userId, 'code': code}, authenticated: false),
  );

  Future<OtpDelivery> resend(String userId, {OtpChannel? channel}) async => OtpDelivery.fromJson(
    await _client.post(
      '/v1/auth/verify/resend',
      data: {'userId': userId, if (channel != null) 'channel': channel.api},
      authenticated: false,
    ),
  );

  Future<SignedInSession> login(String identifier, String password) async => SignedInSession.fromJson(
    await _client.post(
      '/v1/auth/login',
      data: {'identifier': identifier.trim(), 'password': password},
      authenticated: false,
    ),
  );

  Future<void> forgotPassword(String identifier) =>
      _client.post('/v1/auth/password/forgot', data: {'identifier': identifier.trim()}, authenticated: false);

  Future<SignedInSession> resetPassword(String identifier, String code, String newPassword) async =>
      SignedInSession.fromJson(
        await _client.post(
          '/v1/auth/password/reset',
          data: {'identifier': identifier.trim(), 'code': code, 'newPassword': newPassword},
          authenticated: false,
        ),
      );

  Future<AppUser> me() async => AppUser.fromJson(await _client.get('/v1/me'));

  Future<void> logout(String refreshToken) =>
      _client.post('/v1/auth/logout', data: {'refreshToken': refreshToken}, authenticated: false);
}
