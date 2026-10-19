import '../../../core/network/api_client.dart';

/// What this phone must block, as decided by the server.
class DeviceLockState {
  const DeviceLockState({
    required this.locked,
    required this.wholePhone,
    required this.packages,
    required this.strict,
    required this.reasons,
    required this.raw,
  });

  static const unlocked = DeviceLockState(
    locked: false,
    wholePhone: false,
    packages: [],
    strict: false,
    reasons: [],
    raw: {'locked': false, 'wholePhone': false, 'packages': <String>[], 'strict': false, 'reasons': <Object>[]},
  );

  final bool locked;
  final bool wholePhone;
  final List<String> packages;
  final bool strict;
  final List<({String kind, String id, String title, String status})> reasons;

  /// The server's JSON, passed to the native blocker unchanged.
  final Json raw;

  factory DeviceLockState.fromJson(Json json) => DeviceLockState(
    locked: json['locked']! as bool,
    wholePhone: json['wholePhone']! as bool,
    packages: [for (final p in json['packages']! as List<Object?>) p! as String],
    strict: json['strict']! as bool,
    reasons: [
      for (final r in json['reasons']! as List<Object?>)
        (
          kind: (r! as Map<String, Object?>)['kind']! as String,
          id: (r as Map<String, Object?>)['id']! as String,
          title: r['title']! as String,
          status: r['status']! as String,
        ),
    ],
    raw: json,
  );
}

/// /v1/devices (student session) and /v1/device (device token).
class DeviceApi {
  const DeviceApi(this._client);

  final ApiClient _client;

  Future<({String deviceId, String deviceToken})> register({required String name, required String appVersion}) async {
    final json = await _client.post(
      '/v1/devices',
      data: {'name': name, 'platform': 'android', 'appVersion': appVersion},
    );
    return (deviceId: json['deviceId']! as String, deviceToken: json['deviceToken']! as String);
  }

  Future<DeviceLockState> heartbeat(
    String deviceToken, {
    required bool protectionOn,
    required bool usageAccess,
    required String appVersion,
    List<({String packageName, String label})>? installedApps,
  }) async {
    final json = await _client.post(
      '/v1/device/heartbeat',
      authenticated: false,
      headers: {'X-Device-Token': deviceToken},
      data: {
        'protectionOn': protectionOn,
        'usageAccess': usageAccess,
        'appVersion': appVersion,
        if (installedApps != null)
          'installedApps': [
            for (final a in installedApps) {'package': a.packageName, 'label': a.label},
          ],
      },
    );
    return DeviceLockState.fromJson(json);
  }
}
