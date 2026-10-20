import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../../auth/application/auth_controller.dart';
import '../../study/application/study_providers.dart';
import '../../study/domain/study_session.dart';
import '../../../core/platform/app_lock_platform.dart';
import '../application/app_lock_controller.dart';

/// Shown on top of an app the student tried to open while it is locked.
/// Back goes to the phone's home screen, never back into the locked app.
class LockedScreen extends ConsumerWidget {
  const LockedScreen({super.key, this.appLabel});

  final String? appLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final auth = ref.watch(authControllerProvider);
    final signedInStudent = auth is AuthSignedIn && !auth.user.isParent;
    final session = signedInStudent ? ref.watch(activeSessionProvider).value : null;
    final lock = ref.watch(appLockProvider).value?.state;
    final reasons = lock?.reasons ?? const [];
    final wholePhone = lock?.wholePhone ?? false;
    // Names of the locked apps, from the phone's own app list.
    final labels = {
      for (final a in ref.watch(installedAppsProvider).value ?? const <InstalledApp>[]) a.packageName: a.label,
    };
    final lockedNames = [for (final p in lock?.packages ?? const <String>[]) labels[p] ?? p.split('.').last]..sort();
    final platform = ref.read(appLockPlatformProvider);
    final pending = session?.status == SessionStatus.examPending;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) platform.goHome();
      },
      child: PageShell(
        showBack: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Center(
              child: IconBadge(
                wholePhone ? Icons.phonelink_lock_rounded : Icons.lock_rounded,
                size: 96,
                color: AppColors.violet,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              wholePhone ? 'Your phone is locked' : '${appLabel ?? 'This app'} is locked',
              textAlign: TextAlign.center,
              style: text.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              switch ((wholePhone, pending)) {
                (true, true) =>
                  'Pass your exam to unlock your phone. Calls and the camera still work. You can do this!',
                (true, false) =>
                  'It unlocks when you finish studying and pass your exam. Calls and the camera still work.',
                (false, true) => 'Pass your exam to unlock it. You can do this!',
                (false, false) => 'It unlocks when you finish studying and pass your exam.',
              },
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
            ),
            if (!wholePhone && lockedNames.length > 1) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in lockedNames)
                    Chip(
                      avatar: Icon(Icons.lock_rounded, size: 16, color: AppColors.violet),
                      label: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ],
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 22),
              for (final r in reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ClayCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        IconBadge(
                          r.kind == 'PARENT' ? Icons.family_restroom_rounded : Icons.menu_book_rounded,
                          size: 44,
                          color: r.kind == 'PARENT' ? AppColors.mintDeep : AppColors.violet,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.kind == 'PARENT' ? 'Locked by your parent' : 'Study session',
                                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft),
                              ),
                              Text(r.title, style: text.titleMedium),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 24),
            if (signedInStudent)
              Button3D(
                label: pending ? 'Take my exam' : 'Go to my study session',
                icon: pending ? Icons.quiz_rounded : Icons.timer_rounded,
                onPressed: () => context.go(pending ? Routes.exam : Routes.studySession),
              )
            else
              Button3D(
                label: 'Sign in to take your exam',
                icon: Icons.login_rounded,
                onPressed: () => context.go(Routes.login),
              ),
            const SizedBox(height: 14),
            Button3D.secondary(label: 'Back to home screen', icon: Icons.home_rounded, onPressed: platform.goHome),
          ],
        ),
      ),
    );
  }
}
