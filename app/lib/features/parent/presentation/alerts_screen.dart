import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../application/parent_providers.dart';
import '../domain/parent_models.dart';

/// Exam results, locks and app-lock warnings. Opening it marks them read.
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  @override
  void initState() {
    super.initState();
    // Show what is new first, then mark it read for next time.
    Future.microtask(() async {
      try {
        await ref.read(notificationsProvider.future);
        await ref.read(parentApiProvider).markAllRead();
      } on Exception {
        // Unread dots stay; nothing else depends on this.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(notificationsProvider);
    return PopScope(
      // The home screen's unread count catches up on the way back.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.invalidate(notificationsProvider);
      },
      child: PageShell(
        title: 'Alerts',
        child: alerts.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => MessageBanner.error(e is ApiException ? e.message : 'Could not load alerts.'),
          data: (data) => data.items.isEmpty
              ? ClayCard(
                  child: Column(
                    children: [
                      IconBadge(Icons.notifications_none_rounded, size: 64, color: AppColors.coral),
                      const SizedBox(height: 8),
                      Text('All quiet', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      const Text('Exam results and app-lock warnings show up here.', textAlign: TextAlign.center),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final n in data.items)
                      Padding(padding: const EdgeInsets.only(bottom: 10), child: _AlertTile(n)),
                  ],
                ),
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile(this.n);

  final AppNotification n;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (n.kind) {
      'EXAM_PASSED' || 'LOCK_PASSED' => (Icons.emoji_events_rounded, AppColors.sunshineDeep),
      'EXAM_FAILED' => (Icons.replay_rounded, AppColors.inkSoft),
      'SESSION_STARTED' => (Icons.timer_rounded, AppColors.violet),
      'PROTECTION_OFF' => (Icons.gpp_maybe_rounded, AppColors.coralDeep),
      'PARENT_LOCK' => (Icons.lock_rounded, AppColors.sunshineDeep),
      _ => (Icons.notifications_rounded, AppColors.sky),
    };
    final l = MaterialLocalizations.of(context);
    final when = '${l.formatMediumDate(n.createdAt)}, ${l.formatTimeOfDay(TimeOfDay.fromDateTime(n.createdAt))}';
    return ClayCard(
      glow: n.read ? null : color,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon, size: 42, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.title, style: Theme.of(context).textTheme.titleMedium),
                if (n.body.isNotEmpty) Text(n.body, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  when,
                  style: TextStyle(color: AppColors.inkFaint, fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (!n.read)
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}
