import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/widgets/dreamy_background.dart';
import '../../../core/widgets/pencil_3d.dart';

/// Shown for a moment while the saved session is checked.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DreamyBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Pencil3D(size: 200, interactive: false),
              const SizedBox(height: 12),
              Text(AppConfig.appName, style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
        ),
      ),
    );
  }
}
