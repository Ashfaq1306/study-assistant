import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../application/app_lock_controller.dart';

/// Turn the app lock on: a short checklist of the Android permissions it needs,
/// each explained before the system settings open.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Permissions may have changed since the status was last read.
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(appLockProvider.notifier).refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Settings: show the new permission state.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.read(appLockProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(appLockProvider);
    final platform = ref.read(appLockPlatformProvider);
    final text = Theme.of(context).textTheme;

    return PageShell(
      title: 'App lock',
      child: status.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => const MessageBanner.error('Could not check the app lock. Please try again.'),
        data: (s) {
          if (!s.supported) {
            return const MessageBanner.info(
              'App lock works on Android phones. Study sessions and exams still work here.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: IconBadge(
                  s.protectionOn ? Icons.verified_user_rounded : Icons.shield_outlined,
                  size: 88,
                  color: s.protectionOn ? AppColors.mintDeep : AppColors.coralDeep,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                s.protectionOn ? 'App lock is on' : 'Turn on app lock',
                textAlign: TextAlign.center,
                style: text.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                s.protectionOn
                    ? 'Locked apps open your study session instead, until you pass your exam.'
                    : 'Two quick switches let Study Assistant lock the apps you pick while you study.',
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
              ),
              if (s.lockedForAnotherUser) ...[
                const SizedBox(height: 16),
                const MessageBanner.error(
                  'Another account has a lock running on this phone. Sign in to that account to take its exam first.',
                ),
              ],
              if (s.state.locked) ...[
                const SizedBox(height: 16),
                MessageBanner.info(
                  s.state.wholePhone
                      ? 'Your phone is locked right now (calls still work).'
                      : '${s.state.packages.length} apps are locked right now.',
                ),
              ],
              const SizedBox(height: 24),
              _Step(
                number: 1,
                icon: Icons.accessibility_new_rounded,
                title: 'Allow app lock',
                body:
                    'Opens Accessibility settings. Choose "Installed apps" (or "Downloaded apps"), then '
                    '"Study Assistant app lock", and switch it on. '
                    'It only checks which app is open on screen, never what you type or what is inside apps. '
                    'Your list of installed apps is shared with your linked parent so they can choose apps to lock.',
                done: s.protectionOn,
                action: 'Open settings',
                onAction: platform.openAccessibilitySettings,
              ),
              if (s.protectionOn && s.shortcutOn) ...[
                const SizedBox(height: 12),
                _Step(
                  number: 1,
                  icon: Icons.keyboard_double_arrow_up_rounded,
                  title: 'Turn off the shortcut',
                  body:
                      'The app lock has a shortcut switched on (volume keys, accessibility button or a quick setting). '
                      'Open Accessibility settings, choose "Study Assistant app lock" and turn its shortcut off, '
                      'so the lock cannot be switched off by accident.',
                  done: false,
                  action: 'Open settings',
                  onAction: platform.openAccessibilitySettings,
                ),
              ],
              if (!s.protectionOn) ...[
                const SizedBox(height: 12),
                ClayCard(
                  color: AppColors.sunshineSoft,
                  glow: AppColors.sunshineDeep,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.help_rounded, color: AppColors.sunshineDeep),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Switch greyed out ("Restricted setting")?',
                              style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Android protects this switch for apps not installed from the Play Store. '
                        'Tap "Open App info" below, tap the three dots (top right), choose "Allow restricted settings" '
                        'and confirm with your PIN or fingerprint. Then come back and do step 1 again.',
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                      ),
                      const SizedBox(height: 10),
                      Button3D.secondary(label: 'Open App info', height: 48, onPressed: platform.openAppDetails),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _Step(
                number: 2,
                icon: Icons.insights_rounded,
                title: 'Share screen time',
                body: 'Lets your parent see how long apps were used. Choose Study Assistant and allow usage access.',
                done: s.usageAccess,
                action: 'Open settings',
                onAction: platform.openUsageAccessSettings,
              ),
              const SizedBox(height: 12),
              _Step(
                number: 3,
                icon: Icons.battery_charging_full_rounded,
                title: 'Keep it running',
                body: 'Some phones close background apps. Set Study Assistant to "Unrestricted" or "Not optimised".',
                done: false,
                optional: true,
                action: 'Battery settings',
                onAction: platform.openBatterySettings,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
    required this.done,
    required this.action,
    required this.onAction,
    this.optional = false,
  });

  final int number;
  final IconData icon;
  final String title;
  final String body;
  final bool done;
  final bool optional;
  final String action;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.mintDeep : AppColors.violet;
    return ClayCard(
      glow: color,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(done ? Icons.check_rounded : icon, size: 46, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  '$number. $title${optional ? ' (optional)' : ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (done) Icon(Icons.check_circle_rounded, color: AppColors.mintDeep),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
          if (!done) ...[
            const SizedBox(height: 12),
            Button3D(label: action, height: 48, icon: Icons.open_in_new_rounded, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}
