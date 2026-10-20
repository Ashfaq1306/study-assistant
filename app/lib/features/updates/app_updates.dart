import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';

/// A newer test build on GitHub Releases.
class AppUpdate {
  const AppUpdate({required this.build, required this.version, required this.downloadUrl, required this.notes});

  final int build;
  final String version;
  final String downloadUrl;
  final String notes;
}

/// Reads "v0.4.0-b5" style tags: version 0.4.0, build 5.
({String version, int build})? parseReleaseTag(String tag) {
  final match = RegExp(r'^v?(\d+\.\d+\.\d+)-b(\d+)$').firstMatch(tag.trim());
  return match == null ? null : (version: match.group(1)!, build: int.parse(match.group(2)!));
}

/// APKs built for one kind of phone chip end like "-arm64-v8a.apk".
final _abiApk = RegExp(r'-(arm64-v8a|armeabi-v7a|x86_64)\.apk$');

/// The newest release with an APK, newer than [currentBuild]; null if up to date.
/// Prefers the APK built for this phone's [abi]; never picks another chip's.
AppUpdate? newestUpdate(List<Object?> releases, int currentBuild, {String abi = ''}) {
  AppUpdate? best;
  for (final r in releases.whereType<Map<String, Object?>>()) {
    if (r['draft'] == true) continue;
    final tag = parseReleaseTag(r['tag_name'] as String? ?? '');
    if (tag == null || tag.build <= currentBuild || (best != null && tag.build <= best.build)) continue;
    final apks = [
      for (final a in (r['assets'] as List<Object?>? ?? const []).whereType<Map<String, Object?>>())
        if ((a['name'] as String? ?? '').endsWith('.apk')) a,
    ];
    final apk =
        apks.where((a) => abi.isNotEmpty && (a['name']! as String).endsWith('-$abi.apk')).firstOrNull ??
        apks.where((a) => !_abiApk.hasMatch(a['name']! as String)).firstOrNull;
    if (apk == null) continue;
    best = AppUpdate(
      build: tag.build,
      version: tag.version,
      downloadUrl: apk['browser_download_url']! as String,
      notes: (r['body'] as String? ?? '').trim(),
    );
  }
  return best;
}

/// Test builds update themselves from GitHub Releases (the user confirms each
/// install). Play Store builds never do: they cannot install packages.
class AppUpdates {
  AppUpdates({Dio? dio, MethodChannel? channel})
    : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10))),
      _channel = channel ?? const MethodChannel('study_assistant/app_lock');

  final Dio _dio;
  final MethodChannel _channel;

  bool get _android => Platform.isAndroid;

  Future<bool> canSelfUpdate() async => _android && (await _channel.invokeMethod<bool>('canSelfUpdate') ?? false);

  /// The pubspec build number. Per-chip APKs add the chip as thousands
  /// (arm64-v8a build 5 has version code 2005), so only the last three digits count.
  Future<int> currentBuild() async => ((await _channel.invokeMethod<int>('versionCode')) ?? 0) % 1000;

  /// Null when this build is the newest (or updates are not possible here).
  Future<AppUpdate?> check() async {
    if (!await canSelfUpdate()) return null;
    final res = await _dio.get<List<Object?>>(
      'https://api.github.com/repos/${AppConfig.updateRepo}/releases',
      queryParameters: {'per_page': 10},
      options: Options(headers: {'Accept': 'application/vnd.github+json'}),
    );
    final abi = await _channel.invokeMethod<String>('abi') ?? '';
    return newestUpdate(res.data ?? const [], await currentBuild(), abi: abi);
  }

  /// Downloads the build, then opens Android's install screen.
  Future<void> install(AppUpdate update, {void Function(double progress)? onProgress}) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    await dir.create(recursive: true);
    final file = File('${dir.path}/study-assistant-${update.build}.apk');
    if (!await file.exists()) {
      final partial = File('${file.path}.part');
      await _dio.download(
        update.downloadUrl,
        partial.path,
        onReceiveProgress: (got, total) => onProgress?.call(total > 0 ? got / total : 0),
      );
      await partial.rename(file.path);
    }
    await _channel.invokeMethod<bool>('installApk', {'path': file.path});
  }
}

final appUpdatesProvider = Provider<AppUpdates>((ref) => AppUpdates());

/// Checked once per app start; errors (offline, rate limit) just mean "no update".
final availableUpdateProvider = FutureProvider<AppUpdate?>((ref) async {
  try {
    return await ref.watch(appUpdatesProvider).check();
  } on Object {
    return null;
  }
});
