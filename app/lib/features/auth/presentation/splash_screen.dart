import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/dreamy_background.dart';
import '../../../core/widgets/float_in.dart';
import '../../../core/widgets/mascot_stage.dart';

/// Shown for a moment while the saved session is checked: the 3D pencil on its
/// stage, the name floating in, and a bouncing loader.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: DreamyBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FloatIn(offset: 40, child: MascotStage(size: 300, interactive: false)),
              FloatIn(
                delay: const Duration(milliseconds: 250),
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) =>
                      LinearGradient(colors: [AppColors.violet, AppColors.coralDeep]).createShader(bounds),
                  child: Text(AppConfig.appName, style: text.displaySmall?.copyWith(fontSize: 34)),
                ),
              ),
              const SizedBox(height: 6),
              FloatIn(
                delay: const Duration(milliseconds: 450),
                child: Text(
                  'Study smart. Unlock by learning.',
                  style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
                ),
              ),
              const SizedBox(height: 28),
              const _BouncingDots(),
            ],
          ),
        ),
      ),
    );
  }
}

class _BouncingDots extends StatefulWidget {
  const _BouncingDots();

  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = [AppColors.violet, AppColors.sunshine, AppColors.mint];
    return Semantics(
      label: 'Loading',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, color) in colors.indexed)
              () {
                final phase = ((_controller.value - i * 0.18) % 1.0);
                final lift = phase < 0.5 ? Curves.easeOut.transform(phase * 2) : Curves.easeIn.transform(2 - phase * 2);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Transform.translate(
                    offset: Offset(0, -lift * 10),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        boxShadow: [
                          BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 4)),
                        ],
                      ),
                    ),
                  ),
                );
              }(),
          ],
        ),
      ),
    );
  }
}
