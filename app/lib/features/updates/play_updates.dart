import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';

import 'app_updates.dart';

/// Updates for the Google Play build, through Google Play's in-app update API.
///
/// Play keeps installed apps up to date by itself; this makes it faster: when a new version
/// is out, home shows "Update from Google Play" (one tap downloads it in the background and
/// restarts into it). A release marked urgent in the Play Console (in-app update priority 4
/// or 5) asks to update before the app is used.
///
/// Test builds (sideloaded, updated from GitHub) never use this; outside Play it reports nothing.
class PlayUpdates {
  /// The pending Play update, or null (none, not installed from Play, or not Android).
  Future<AppUpdateInfo?> check() async {
    if (!Platform.isAndroid) return null;
    try {
      final info = await InAppUpdate.checkForUpdate();
      final ready =
          info.updateAvailability == UpdateAvailability.updateAvailable ||
          info.updateAvailability == UpdateAvailability.developerTriggeredUpdateInProgress ||
          info.installStatus == InstallStatus.downloaded;
      return ready ? info : null;
    } on Object {
      // Not installed from Google Play (debug, test builds) or Play is unavailable.
      return null;
    }
  }

  /// Urgent releases update before the app is used; Play shows its own full-screen flow.
  Future<bool> updateNowIfUrgent(AppUpdateInfo info) async {
    if (info.updatePriority < 4 || !info.immediateUpdateAllowed) return false;
    try {
      return await InAppUpdate.performImmediateUpdate() == AppUpdateResult.success;
    } on Object {
      return false;
    }
  }

  /// Downloads in the background (Play asks the user once), then installs and restarts the app.
  Future<bool> downloadAndInstall() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.installStatus != InstallStatus.downloaded) {
        if (info.immediateUpdateAllowed && !info.flexibleUpdateAllowed) {
          return await InAppUpdate.performImmediateUpdate() == AppUpdateResult.success;
        }
        if (await InAppUpdate.startFlexibleUpdate() != AppUpdateResult.success) return false;
      }
      await InAppUpdate.completeFlexibleUpdate();
      return true;
    } on Object {
      return false;
    }
  }
}

final playUpdatesProvider = Provider<PlayUpdates>((ref) => PlayUpdates());

/// Checked once per app start, only for builds that cannot update themselves from GitHub.
/// An urgent update starts right away.
final playUpdateProvider = FutureProvider<AppUpdateInfo?>((ref) async {
  if (await ref.watch(appUpdatesProvider).canSelfUpdate()) return null;
  final play = ref.watch(playUpdatesProvider);
  final info = await play.check();
  if (info != null && await play.updateNowIfUrgent(info)) return null;
  return info;
});
