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
    this.shortcutOn = false,
    this.usageAccess = false,
    this.registered = false,
    this.lockedForAnotherUser = false,
    this.state = DeviceLockState.unlocked,
  });

  /// App locking needs Android.
  final bool supported;

  /// The accessibility service that enforces locks is on.
  final bool protectionOn;

  /// An accessibility shortcut could switch the lock off; the student must turn it off.
  final bool shortcutOn;
  final bool usageAccess;
  final bool registered;

  /// Another student's lock is still running on this phone.
  final bool lockedForAnotherUser;
  final DeviceLockState state;

  bool get ready => supported && protectionOn && !shortcutOn && registered;
}

final appLockPlatformProvider = Provider<AppLockPlatform>((ref) => AppLockPlatform());

final deviceApiProvider = Provider<DeviceApi>((ref) => DeviceApi(ref.watch(apiClientProvider)));

/// Launchable apps on this phone, with icons, for the app picker (loaded once).
final installedAppsProvider = FutureProvider<List<InstalledApp>>(
  (ref) => ref.watch(appLockPlatformProvider).installedApps(),
);

final appLockProvider = AsyncNotifierProvider<AppLockController, AppLockStatus>(AppLockController.new);

/// Registers this phone for the signed-in student and keeps the native
/// blocker in step with the server's lock state.
class AppLockController extends AsyncNotifier<AppLockStatus> {
  AppLockPlatform get _platform => ref.read(appLockPlatformProvider);
  DeviceApi get _api => ref.read(deviceApiProvider);

  String? _studentId;
  Future<AppLockStatus>? _inFlight;
  String? _inFlightFor;

  @override
  Future<AppLockStatus> build() async {
    _studentId = ref.watch(
      authControllerProvider.select((s) => s is AuthSignedIn && !s.user.isParent ? s.user.id : null),
    );
    return _syncOnce();
  }

  /// Re-reads permissions and the lock state, e.g. when the app comes back to the front.
  Future<void> refresh() async {
    try {
      state = AsyncData(await _syncOnce());
    } on Object catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Overlapping callers (resume, screens, build) share one sync, so a first
  /// sign-in registers the phone exactly once. A different account waits for
  /// the running sync, then gets its own.
  Future<AppLockStatus> _syncOnce() {
    final id = _studentId;
    final running = _inFlight;
    if (running != null && _inFlightFor == id) return running;
    _inFlightFor = id;
    final next = (running ?? Future<void>.value()).then((_) {}, onError: (_) {}).then((_) => _sync());
    _inFlight = next;
    next.whenComplete(() {
      if (identical(_inFlight, next)) _inFlight = null;
    }).ignore();
    return next;
  }

  Future<AppLockStatus> _sync() async {
    if (!_platform.isSupported) return const AppLockStatus(supported: false);

    var native = await _platform.status();
    var token = native.deviceToken;
    final studentId = _studentId;
    var lockedForAnotherUser = false;

    if (studentId != null && (token == null || native.ownerUserId != studentId)) {
      if (token != null && await _stillLocked(token, cachedLocked: native.locked)) {
        // Signing in as someone else must not end a running lock.
        lockedForAnotherUser = true;
      } else {
        try {
          final device = await _api.register(name: native.deviceModel, appVersion: AppConfig.appVersion);
          await _platform.configure(baseUrl: AppConfig.apiBaseUrl, deviceToken: device.deviceToken, userId: studentId);
          token = device.deviceToken;
          native = await _platform.status();
        } on ApiException {
          // Offline: try again on the next refresh.
        }
      }
    }

    // The app now talks to a different server (e.g. a new address): keep the native sync in step.
    if (token != null && studentId != null && !lockedForAnotherUser && native.apiBaseUrl != AppConfig.apiBaseUrl) {
      await _platform.configure(baseUrl: AppConfig.apiBaseUrl, deviceToken: token, userId: studentId);
    }

    var lockState = DeviceLockState.unlocked;
    if (token != null && !lockedForAnotherUser) {
      try {
        final apps = await _platform.installedApps(withIcons: false);
        lockState = await _api.heartbeat(
          token,
          protectionOn: native.protectionOn,
          usageAccess: native.usageAccess,
          shortcutOn: native.shortcutOn,
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
      shortcutOn: native.shortcutOn,
      usageAccess: native.usageAccess,
      registered: token != null && !lockedForAnotherUser,
      lockedForAnotherUser: lockedForAnotherUser,
      state: lockState,
    );
  }

  /// Asks the server whether the previous owner's lock is still running.
  Future<bool> _stillLocked(String token, {required bool cachedLocked}) async {
    try {
      return (await _api.state(token)).locked;
    } on ApiException catch (e) {
      if (e.code == 'DEVICE_UNAUTHORIZED') return false;
      return cachedLocked; // Offline: trust the last known state (the safe side).
    }
  }
}
