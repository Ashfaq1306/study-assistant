import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/appearance.dart';
import '../features/app_lock/application/app_lock_controller.dart';
import '../features/study/application/study_providers.dart';
import 'router.dart';
import 'routes.dart';

class StudyAssistantApp extends ConsumerStatefulWidget {
  const StudyAssistantApp({super.key});

  @override
  ConsumerState<StudyAssistantApp> createState() => _StudyAssistantAppState();
}

class _StudyAssistantAppState extends ConsumerState<StudyAssistantApp> with WidgetsBindingObserver {
  StreamSubscription<({String packageName, String label})>? _lockedApps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockedApps = ref.read(appLockPlatformProvider).lockedAppOpened.listen((app) => _showLocked(app.label));
    // A blocked app may have been opened before the UI was running.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPendingLock());
  }

  @override
  void dispose() {
    _lockedApps?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The phone switched between light and dark.
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_checkPendingLock());
    unawaited(ref.read(appLockProvider.notifier).refresh().catchError((_) {}));
    ref.invalidate(activeSessionProvider);
  }

  Future<void> _checkPendingLock() async {
    final platform = ref.read(appLockPlatformProvider);
    final pkg = await platform.takePendingLockedPackage();
    if (pkg != null) _showLocked(await platform.appLabel(pkg));
  }

  void _showLocked(String label) {
    final router = ref.read(routerProvider);
    final target = Uri(path: Routes.locked, queryParameters: {'app': label}).toString();
    if (router.state.matchedLocation == Routes.locked) {
      router.replace(target);
    } else {
      router.push(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(appearanceProvider);
    final palette = appearance.palette(View.of(context).platformDispatcher.platformBrightness);
    AppColors.use(palette);
    // Colours are read while widgets build, so a new palette rebuilds the whole
    // tree (the router keeps the open screens).
    return MaterialApp.router(
      key: ValueKey((palette.brightness, palette.accent)),
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
