import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeLockStatus {
  const NativeLockStatus({
    required this.protectionOn,
    required this.usageAccess,
    required this.deviceModel,
    required this.locked,
    this.shortcutOn = false,
    this.ownerUserId,
    this.deviceToken,
    this.apiBaseUrl,
  });

  /// The accessibility service is switched on.
  final bool protectionOn;
  final bool usageAccess;
  final String deviceModel;

  /// A lock is being enforced right now (from the last known server state).
  final bool locked;

  /// An accessibility shortcut could switch the lock off without opening Settings.
  final bool shortcutOn;
  final String? ownerUserId;
  final String? deviceToken;

  /// Where the native blocker syncs; updated when the app's server changes.
  final String? apiBaseUrl;
}

class InstalledApp {
  const InstalledApp({required this.packageName, required this.label, this.icon});

  final String packageName;
  final String label;
  final Uint8List? icon;
}

/// Bridge to the Android app blocker (AppLockService). Everything is a no-op
/// elsewhere: app locking needs Android.
class AppLockPlatform {
  AppLockPlatform([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('study_assistant/app_lock') {
    if (isSupported) _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final _lockedApps = StreamController<({String packageName, String label})>.broadcast();

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Fires when the blocker brings the app over a locked app.
  Stream<({String packageName, String label})> get lockedAppOpened => _lockedApps.stream;

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'onLockedApp') {
      final args = Map<String, Object?>.from(call.arguments as Map);
      _lockedApps.add((packageName: args['package']! as String, label: args['label']! as String));
    }
    return null;
  }

  Future<NativeLockStatus> status() async {
    if (!isSupported) {
      return const NativeLockStatus(protectionOn: false, usageAccess: false, deviceModel: 'Unsupported', locked: false);
    }
    final map = Map<String, Object?>.from((await _channel.invokeMethod<Map<Object?, Object?>>('getStatus'))!);
    return NativeLockStatus(
      protectionOn: map['protectionOn']! as bool,
      usageAccess: map['usageAccess']! as bool,
      deviceModel: map['deviceModel']! as String,
      locked: map['locked'] as bool? ?? false,
      shortcutOn: map['shortcutOn'] as bool? ?? false,
      ownerUserId: map['ownerUserId'] as String?,
      deviceToken: map['deviceToken'] as String?,
      apiBaseUrl: map['apiBaseUrl'] as String?,
    );
  }

  Future<void> configure({required String baseUrl, required String deviceToken, required String userId}) =>
      _invoke('configure', {'baseUrl': baseUrl, 'deviceToken': deviceToken, 'userId': userId});

  /// Hands the lock state fetched by the app to the blocker right away.
  Future<void> applyState(Map<String, Object?> state) => _invoke('applyState', {'state': jsonEncode(state)});

  Future<void> syncNow() => _invoke('syncNow');

  /// Asks the launcher to add the home-screen widget. False when the launcher can't.
  Future<bool> pinWidget() async => isSupported && (await _channel.invokeMethod<bool>('pinWidget') ?? false);

  /// Redraws the home-screen widget. [mode] is idle, studying, exam, locked or signedOut.
  Future<void> updateWidget({
    required String mode,
    String title = '',
    String subtitle = '',
    DateTime? endsAt,
    int todayMinutes = 0,
    int streakDays = 0,
  }) => _invoke('updateWidget', {
    'mode': mode,
    'title': title,
    'subtitle': subtitle,
    'endsAt': endsAt?.millisecondsSinceEpoch ?? 0,
    'todayMinutes': todayMinutes,
    'streakDays': streakDays,
  });

  /// Launchable apps; icons are only loaded when [withIcons] (for the picker).
  Future<List<InstalledApp>> installedApps({bool withIcons = true}) async {
    if (!isSupported) return const [];
    final list =
        await _channel.invokeListMethod<Map<Object?, Object?>>('getInstalledApps', {'withIcons': withIcons}) ??
        const [];
    return [
      for (final raw in list)
        InstalledApp(
          packageName: raw['package']! as String,
          label: raw['label']! as String,
          icon: raw['icon'] as Uint8List?,
        ),
    ];
  }

  Future<String?> takePendingLockedPackage() async =>
      isSupported ? _channel.invokeMethod<String>('takePendingLockedPackage') : null;

  Future<String> appLabel(String packageName) async => isSupported
      ? (await _channel.invokeMethod<String>('appLabel', {'package': packageName})) ?? packageName
      : packageName;

  Future<void> openAccessibilitySettings() => _invoke('openAccessibilitySettings');
  Future<void> openUsageAccessSettings() => _invoke('openUsageAccessSettings');
  Future<void> openAppDetails() => _invoke('openAppDetails');
  Future<void> openBatterySettings() => _invoke('openBatterySettings');
  Future<void> goHome() => _invoke('goHome');

  Future<void> _invoke(String method, [Map<String, Object?>? args]) async {
    if (isSupported) await _channel.invokeMethod<Object?>(method, args);
  }
}
