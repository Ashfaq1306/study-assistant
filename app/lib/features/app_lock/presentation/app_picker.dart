import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/app_lock_platform.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/choice_controls.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../application/app_lock_controller.dart';

/// Lock-the-whole-phone marker understood by the server and the blocker.
const wholePhone = '*';

/// Popular time-wasters, preselected by "Pick distractions" when installed.
const commonDistractions = {
  'com.google.android.youtube',
  'com.facebook.katana',
  'com.facebook.lite',
  'com.facebook.orca',
  'com.instagram.android',
  'com.zhiliaoapp.musically',
  'com.ss.android.ugc.trill',
  'com.whatsapp',
  'com.snapchat.android',
  'com.twitter.android',
  'com.netflix.mediaclient',
  'com.discord',
  'com.reddit.frontpage',
  'com.dts.freefireth',
  'com.dts.freefiremax',
  'com.tencent.ig',
  'com.pubg.imobile',
  'com.supercell.clashofclans',
  'com.mojang.minecraftpe',
  'com.roblox.client',
  'com.king.candycrushsaga',
};

/// Choose which apps to lock (or the whole phone).
class AppPicker extends ConsumerStatefulWidget {
  const AppPicker({super.key, required this.selected, required this.onChanged});

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  ConsumerState<AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends ConsumerState<AppPicker> {
  String _query = '';

  /// "Choose apps" was tapped (the list shows even before an app is ticked).
  late bool _choosing = widget.selected.isNotEmpty && !widget.selected.contains(wholePhone);

  bool get _whole => widget.selected.contains(wholePhone);

  void _toggle(String pkg) {
    _choosing = true;
    final next = {...widget.selected}..remove(wholePhone);
    next.contains(pkg) ? next.remove(pkg) : next.add(pkg);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final apps = ref.watch(installedAppsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ModeCard(
                icon: Icons.phonelink_lock_rounded,
                title: 'Whole phone',
                body: 'Everything locks. Calls and the camera still work.',
                color: AppColors.coralDeep,
                selected: _whole,
                onTap: () {
                  setState(() => _choosing = false);
                  widget.onChanged({wholePhone});
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ModeCard(
                icon: Icons.apps_rounded,
                title: 'Choose apps',
                body: 'Only the apps you tick lock.',
                color: AppColors.violet,
                selected: _choosing && !_whole,
                onTap: () {
                  setState(() => _choosing = true);
                  if (_whole) widget.onChanged({});
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Summary(selected: widget.selected, choosing: _choosing),
        if (_choosing && !_whole) ...[
          const SizedBox(height: 16),
          apps.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const MessageBanner.error('Could not list your apps.'),
            data: (list) => _list(list),
          ),
        ],
      ],
    );
  }

  Widget _list(List<InstalledApp> list) {
    if (list.isEmpty) {
      return const MessageBanner.info('App lock works on Android phones. You can still study and take the exam.');
    }
    final installedDistractions = list.where((a) => commonDistractions.contains(a.packageName)).toList();
    final q = _query.toLowerCase();
    final shown = q.isEmpty ? list : list.where((a) => a.label.toLowerCase().contains(q)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search apps',
                  prefixIcon: Icon(Icons.search_rounded),
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (installedDistractions.isNotEmpty)
              ChoicePill(
                label: 'Pick distractions (${installedDistractions.length})',
                icon: Icons.auto_fix_high_rounded,
                selected: installedDistractions.every((a) => widget.selected.contains(a.packageName)),
                onTap: () => widget.onChanged({
                  ...widget.selected.where((p) => p != wholePhone),
                  for (final a in installedDistractions) a.packageName,
                }),
              ),
            if (widget.selected.isNotEmpty)
              ChoicePill(
                label: 'Clear (${widget.selected.length})',
                icon: Icons.clear_all_rounded,
                color: AppColors.coralDeep,
                selected: false,
                onTap: () => widget.onChanged({}),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ClayCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (final app in shown)
                CheckboxListTile(
                  value: widget.selected.contains(app.packageName),
                  onChanged: (_) => _toggle(app.packageName),
                  secondary: app.icon == null
                      ? const Icon(Icons.apps_rounded)
                      : Image.memory(app.icon!, width: 40, height: 40, gaplessPlayback: true),
                  title: Text(app.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: ClayCard(
        selected: selected,
        glow: color,
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(icon, size: 40, color: color),
                const Spacer(),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? color : AppColors.line,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.ink),
            ),
            const SizedBox(height: 2),
            Text(
              body,
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkSoft, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// Says exactly what will be locked.
class _Summary extends StatelessWidget {
  const _Summary({required this.selected, required this.choosing});

  final Set<String> selected;
  final bool choosing;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = selected.contains(wholePhone)
        ? (Icons.lock_rounded, 'Locking: the whole phone', AppColors.coralDeep)
        : selected.isNotEmpty
        ? (Icons.lock_rounded, 'Locking: ${selected.length} ${selected.length == 1 ? 'app' : 'apps'}', AppColors.violet)
        : choosing
        ? (Icons.touch_app_rounded, 'Tick the apps to lock below', AppColors.inkSoft)
        : (Icons.lock_open_rounded, 'Nothing locked yet: pick one above', AppColors.inkSoft);
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
        ),
      ],
    );
  }
}
