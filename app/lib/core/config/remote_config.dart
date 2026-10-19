import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Settings the admin controls (GET /v1/config). Defaults mirror the server
/// so the app still works if the first fetch fails.
class RemoteConfig {
  const RemoteConfig({
    this.subjects = const ['Mathematics', 'Science', 'English', 'Bangla', 'Physics', 'Chemistry', 'Biology', 'ICT'],
    this.minPassPercent = 50,
    this.minStudyMinutes = 5,
    this.maxStudyMinutes = 240,
    this.earlyFinishPercent = 50,
    this.maxQuestions = 30,
    this.examRetryCooldownSeconds = 120,
    this.aiEnabled = true,
    this.announcement,
  });

  final List<String> subjects;
  final int minPassPercent;
  final int minStudyMinutes;
  final int maxStudyMinutes;
  final int earlyFinishPercent;
  final int maxQuestions;
  final int examRetryCooldownSeconds;
  final bool aiEnabled;
  final String? announcement;

  factory RemoteConfig.fromJson(Map<String, Object?> json) => RemoteConfig(
    subjects: [for (final s in json['subjects']! as List<Object?>) s! as String],
    minPassPercent: (json['minPassPercent']! as num).toInt(),
    minStudyMinutes: (json['minStudyMinutes']! as num).toInt(),
    maxStudyMinutes: (json['maxStudyMinutes']! as num).toInt(),
    earlyFinishPercent: (json['earlyFinishPercent']! as num).toInt(),
    maxQuestions: (json['maxQuestions']! as num).toInt(),
    examRetryCooldownSeconds: (json['examRetryCooldownSeconds']! as num).toInt(),
    aiEnabled: json['aiEnabled'] as bool? ?? true,
    announcement: json['announcement'] as String?,
  );
}

/// Falls back to the defaults when offline, and tries again shortly so admin
/// changes (e.g. a higher pass mark floor) reach the app.
final remoteConfigProvider = FutureProvider<RemoteConfig>((ref) async {
  try {
    return RemoteConfig.fromJson(await ref.watch(apiClientProvider).get('/v1/config'));
  } on Object {
    final retry = Timer(const Duration(seconds: 30), ref.invalidateSelf);
    ref.onDispose(retry.cancel);
    return const RemoteConfig();
  }
});
