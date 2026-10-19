import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Inline message box for errors and hints inside forms.
class MessageBanner extends StatelessWidget {
  const MessageBanner.error(this.message, {super.key})
    : color = AppColors.coralSoft,
      foreground = AppColors.coralDeep,
      icon = Icons.error_rounded;

  const MessageBanner.info(this.message, {super.key})
    : color = AppColors.skySoft,
      foreground = AppColors.skyDeep,
      icon = Icons.info_rounded;

  const MessageBanner.success(this.message, {super.key})
    : color = AppColors.mintSoft,
      foreground = AppColors.mintDeep,
      icon = Icons.check_circle_rounded;

  final String message;
  final Color color;
  final Color foreground;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
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

/// A raised, softly shaded circle holding an icon in [color]. The app's
/// friendly illustration style: icons everywhere, never emoji.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.color = AppColors.violet, this.size = 56});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
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
            colors: [Color.lerp(color, Colors.white, 0.86)!, Color.lerp(color, Colors.white, 0.72)!],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: size * 0.03),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.22), blurRadius: size * 0.22, offset: Offset(0, size * 0.1)),
          ],
        ),
        child: Icon(icon, size: size * 0.5, color: Color.lerp(color, AppColors.ink, 0.12)),
      ),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
