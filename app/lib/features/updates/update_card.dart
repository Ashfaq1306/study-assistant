import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/clay_card.dart';
import '../../core/widgets/feedback.dart';
import 'app_updates.dart';

/// "A new version is ready": shown on home only when a newer test build exists.
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

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(availableUpdateProvider).value;
    if (update == null) return const SizedBox.shrink();
    final busy = _progress != null;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ClayCard(
        glow: AppColors.mint,
        padding: const EdgeInsets.all(16),
        onTap: busy ? null : () => _install(update),
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
                      Text(
                        busy ? 'Downloading the update…' : 'A new version is ready',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        busy ? '${(_progress! * 100).round()}%' : 'Version ${update.version}. Tap to update.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
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
                child: LinearProgressIndicator(value: _progress, minHeight: 8, color: AppColors.mint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
