import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/platform/app_lock_platform.dart';
import '../../auth/application/auth_controller.dart';
import '../data/device_api.dart';

class AppLockStatus {
  const AppLockStatus({
    required this.supported,
    this.protectionOn = false,
    this.usageAccess = false,
    this.registered = false,
    this.lockedForAnotherUser = false,
    this.state = DeviceLockState.unlocked,
  });

  /// App locking needs Android.
  final bool supported;

  /// The accessibility service that enforces locks is on.
  final bool protectionOn;
  final bool usageAccess;
  final bool registered;

  /// Another student's lock is still running on this phone.
  final bool lockedForAnotherUser;
  final DeviceLockState state;

  bool get ready => supported && protectionOn && registered;
}

final appLockPlatformProvider = Provider<AppLockPlatform>((ref) => AppLockPlatform());

final deviceApiProvider = Provider<DeviceApi>((ref) => DeviceApi(ref.watch(apiClientProvider)));

/// Launchable apps on this phone, with icons (loaded once).
final installedAppsProvider = FutureProvider<List<InstalledApp>>(
  (ref) => ref.watch(appLockPlatformProvider).installedApps(),
);

final appLockProvider = AsyncNotifierProvider<AppLockController, AppLockStatus>(AppLockController.new);

/// Registers this phone for the signed-in student and keeps the native
/// blocker in step with the server's lock state.
class AppLockController extends AsyncNotifier<AppLockStatus> {
  AppLockPlatform get _platform => ref.read(appLockPlatformProvider);

  String? _studentId;

  @override
  Future<AppLockStatus> build() async {
    _studentId = ref.watch(
      authControllerProvider.select((s) => s is AuthSignedIn && !s.user.isParent ? s.user.id : null),
    );
    return _sync();
  }

  /// Re-reads permissions and the lock state, e.g. when the app comes back to the front.
  Future<void> refresh() async {
    state = AsyncData(await _sync());
  }

  Future<AppLockStatus> _sync() async {
    if (!_platform.isSupported) return const AppLockStatus(supported: false);

    var native = await _platform.status();
    var token = native.deviceToken;
    final studentId = _studentId;
    var lockedForAnotherUser = false;

    if (studentId != null && (token == null || native.ownerUserId != studentId)) {
      if (native.locked && native.ownerUserId != null && native.ownerUserId != studentId) {
        // Signing in as someone else must not end a running lock.
        lockedForAnotherUser = true;
      } else {
        try {
          final device = await ref
              .read(deviceApiProvider)
              .register(name: native.deviceModel, appVersion: AppConfig.appVersion);
          await _platform.configure(baseUrl: AppConfig.apiBaseUrl, deviceToken: device.deviceToken, userId: studentId);
          token = device.deviceToken;
          native = await _platform.status();
        } on ApiException {
          // Offline: try again on the next refresh.
        }
      }
    }

    var lockState = DeviceLockState.unlocked;
    if (token != null) {
      try {
        final apps = await ref.read(installedAppsProvider.future);
        lockState = await ref
            .read(deviceApiProvider)
            .heartbeat(
              token,
              protectionOn: native.protectionOn,
              usageAccess: native.usageAccess,
              appVersion: AppConfig.appVersion,
              installedApps: [for (final a in apps) (packageName: a.packageName, label: a.label)],
            );
        await _platform.applyState(lockState.raw);
      } on ApiException {
        // Offline: the blocker keeps enforcing its last known state.
      }
    }

    return AppLockStatus(
      supported: true,
      protectionOn: native.protectionOn,
      usageAccess: native.usageAccess,
      registered: token != null,
      lockedForAnotherUser: lockedForAnotherUser,
      state: lockState,
    );
  }
}
