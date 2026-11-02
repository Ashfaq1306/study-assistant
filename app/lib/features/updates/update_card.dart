import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/clay_card.dart';
import '../../core/widgets/feedback.dart';
import 'app_updates.dart';
import 'play_updates.dart';

/// "A new version is ready": shown on home when a newer version exists, as a test build on
/// GitHub (installed by the app) or on Google Play (installed through Play's in-app update).
class UpdateCard extends ConsumerStatefulWidget {
  const UpdateCard({super.key});

  @override
  ConsumerState<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends ConsumerState<UpdateCard> {
  double? _progress;

  Future<void> _install(AppUpdate update) async {
    setState(() => _progress = 0);
    try {
      await ref
          .read(appUpdatesProvider)
          .install(update, onProgress: (p) => mounted ? setState(() => _progress = p) : null);
    } on Object {
      if (mounted) showSnack(context, "Couldn't download the update. Check your internet and try again.");
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _installFromPlay() async {
    setState(() => _progress = 0);
    final ok = await ref.read(playUpdatesProvider).downloadAndInstall();
    // On success Play restarts the app into the new version.
    if (!ok && mounted) showSnack(context, "Couldn't update right now. Try again, or update from Google Play.");
    if (mounted) setState(() => _progress = null);
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(availableUpdateProvider).value;
    if (update == null) {
      final play = ref.watch(playUpdateProvider).value;
      if (play == null) return const SizedBox.shrink();
      return _card(
        title: _progress != null ? 'Updating from Google Play…' : 'A new version is ready',
        subtitle: _progress != null
            ? 'This takes a moment. The app restarts by itself.'
            : 'Tap to update from Google Play.',
        onTap: _progress != null ? null : _installFromPlay,
      );
    }
    final busy = _progress != null;
    return _card(
      title: busy ? 'Downloading the update…' : 'A new version is ready',
      subtitle: busy ? '${(_progress! * 100).round()}%' : 'Version ${update.version}. Tap to update.',
      onTap: busy ? null : () => _install(update),
      progress: _progress,
    );
  }

  Widget _card({required String title, required String subtitle, required VoidCallback? onTap, double? progress}) {
    final busy = _progress != null;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ClayCard(
        glow: AppColors.mint,
        padding: const EdgeInsets.all(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(Icons.system_update_rounded, size: 46, color: AppColors.mint),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                if (!busy) Icon(Icons.download_rounded, color: AppColors.mintDeep),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                // Play reports no percentage: an indeterminate bar then.
                child: LinearProgressIndicator(value: progress, minHeight: 8, color: AppColors.mint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
