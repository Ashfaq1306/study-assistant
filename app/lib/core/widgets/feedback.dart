import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Inline message box for errors and hints inside forms.
class MessageBanner extends StatelessWidget {
  const MessageBanner.error(this.message, {super.key}) : _kind = _BannerKind.error;

  const MessageBanner.info(this.message, {super.key}) : _kind = _BannerKind.info;

  const MessageBanner.success(this.message, {super.key}) : _kind = _BannerKind.success;

  final String message;
  final _BannerKind _kind;

  @override
  Widget build(BuildContext context) {
    final (color, foreground, icon) = switch (_kind) {
      _BannerKind.error => (AppColors.coralSoft, AppColors.coralDeep, Icons.error_rounded),
      _BannerKind.info => (AppColors.skySoft, AppColors.skyDeep, Icons.info_rounded),
      _BannerKind.success => (AppColors.mintSoft, AppColors.mintDeep, Icons.check_circle_rounded),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _BannerKind { error, info, success }

/// A 3D coin holding an [Icon3D]: a domed face lit from the top left, a solid
/// rim underneath and a soft coloured shadow. The app's illustration style:
/// icons everywhere, never emoji.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.color, this.size = 56});

  final IconData icon;

  /// The theme accent when null.
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppColors.violet;
    final dark = AppColors.isDark;
    final rim = size * 0.07;
    final faceTop = dark
        ? Color.lerp(color, Colors.white, 0.18)!.withValues(alpha: 0.42)
        : Color.lerp(color, Colors.white, 0.93)!;
    final faceBottom = dark ? color.withValues(alpha: 0.24) : Color.lerp(color, Colors.white, 0.72)!;
    final rimColor = dark
        ? Color.lerp(color, Colors.black, 0.35)!.withValues(alpha: 0.75)
        : Color.lerp(color, Colors.white, 0.45)!;

    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size + rim,
        child: Stack(
          children: [
            // Rim and shadow: the coin's thickness.
            Positioned(
              left: 0,
              right: 0,
              top: rim,
              height: size,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: rimColor,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: dark ? 0.35 : 0.28),
                      blurRadius: size * 0.3,
                      offset: Offset(0, size * 0.12),
                    ),
                  ],
                ),
              ),
            ),
            // Domed face, lit from the top left.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: size,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.35, -0.45),
                    radius: 1.05,
                    colors: [faceTop, faceBottom],
                  ),
                  border: Border.all(
                    color: dark ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.95),
                    width: size * 0.035,
                  ),
                ),
                child: Center(
                  child: Icon3D(icon, size: size * 0.5, color: color),
                ),
              ),
            ),
            // Specular shine.
            Positioned(
              left: size * 0.2,
              top: size * 0.1,
              width: size * 0.34,
              height: size * 0.18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.elliptical(size * 0.17, size * 0.09)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: dark ? 0.22 : 0.75),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An icon with depth: a deeper-coloured extrusion below a gradient-lit face.
class Icon3D extends StatelessWidget {
  const Icon3D(this.icon, {super.key, this.size = 28, this.color});

  final IconData icon;
  final double size;

  /// The theme accent when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppColors.violet;
    final dark = AppColors.isDark;
    final light = Color.lerp(color, Colors.white, dark ? 0.45 : 0.25)!;
    final shade = dark ? Color.lerp(color, Colors.black, 0.25)! : Color.lerp(color, AppColors.onBright, 0.35)!;
    final depth = size * 0.07;
    return SizedBox(
      width: size,
      height: size + depth,
      child: Stack(
        children: [
          Positioned(
            top: depth,
            child: Icon(icon, size: size, color: shade.withValues(alpha: 0.85)),
          ),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [light, dark ? color : Color.lerp(color, AppColors.onBright, 0.1)!],
            ).createShader(bounds),
            child: Icon(icon, size: size, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
