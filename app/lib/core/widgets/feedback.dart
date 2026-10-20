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

/// A raised, softly shaded circle holding an icon in [color]. The app's
/// friendly illustration style: icons everywhere, never emoji.
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
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? [color.withValues(alpha: 0.3), color.withValues(alpha: 0.16)]
                : [Color.lerp(color, Colors.white, 0.86)!, Color.lerp(color, Colors.white, 0.72)!],
          ),
          border: Border.all(
            color: dark ? color.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.9),
            width: size * 0.03,
          ),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.22), blurRadius: size * 0.22, offset: Offset(0, size * 0.1)),
          ],
        ),
        child: Icon(
          icon,
          size: size * 0.5,
          color: dark ? Color.lerp(color, Colors.white, 0.25) : Color.lerp(color, AppColors.ink, 0.12),
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
