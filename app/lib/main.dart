import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/config/app_config.dart';
import 'core/network/api_endpoint.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

  // Start on the last server address that worked, then check for a newer one in the background.
  final endpoint = ApiEndpoint(
    fallback: AppConfig.apiBaseUrl,
    discoveryUrl: AppConfig.apiDiscoveryUrl,
    prefs: SharedPreferencesAsync(),
  );
  await endpoint.loadCached();
  unawaited(endpoint.refresh(force: true));

  // Failed requests surface as errors in the UI; don't silently retry them.
  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [apiEndpointProvider.overrideWithValue(endpoint)],
      child: const StudyAssistantApp(),
    ),
  );
}
