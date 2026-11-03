import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import 'liquid_glass.dart';

/// Inline message box for errors and hints inside forms.
class MessageBanner extends StatelessWidget {
  const MessageBanner.error(this.message, {super.key}) : _kind = _BannerKind.error;

  const MessageBanner.info(this.message, {super.key}) : _kind = _BannerKind.info;

  const MessageBanner.success(this.message, {super.key}) : _kind = _BannerKind.success;

  final String message;
  final _BannerKind _kind;

  @override
  Widget build(BuildContext context) {
    final (foreground, icon) = switch (_kind) {
      _BannerKind.error => (AppColors.coralDeep, Icons.priority_high_rounded),
      _BannerKind.info => (AppColors.skyDeep, Icons.info_outline_rounded),
      _BannerKind.success => (AppColors.mintDeep, Icons.check_rounded),
    };
    return Semantics(
      liveRegion: true,
      child: LiquidGlass(
        radius: Radii.md,
        tint: foreground,
        shadow: foreground,
        blur: false,
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassIconTile(icon: icon, color: foreground, size: 26),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: AppColors.legible(foreground),
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _BannerKind { error, info, success }

/// An icon on a glossy glass tile (see [GlassIconTile]): the app's illustration style.
/// Icons everywhere, never emoji or flat stickers.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.color, this.size = 56});

  final IconData icon;

  /// The theme accent when null.
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => GlassIconTile(icon: icon, color: color ?? AppColors.violet, size: size);
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
