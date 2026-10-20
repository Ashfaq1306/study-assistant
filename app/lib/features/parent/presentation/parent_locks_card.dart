import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../app_lock/application/app_lock_controller.dart';

/// On a student's home: locks a parent set, each lifted by passing its quiz.
class ParentLocksCard extends ConsumerWidget {
  const ParentLocksCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reasons = ref.watch(appLockProvider).value?.state.reasons ?? const [];
    final locks = [
      for (final r in reasons)
        if (r.kind == 'PARENT') r,
    ];
    if (locks.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ClayCard(
        glow: AppColors.mintDeep,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(Icons.family_restroom_rounded, size: 46, color: AppColors.mintDeep),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        locks.length == 1 ? 'Locked by your parent' : 'Locks from your parent',
                        style: text.titleMedium,
                      ),
                      Text('Pass the quiz to unlock. You can do it!', style: text.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            for (final lock in locks) ...[
              const SizedBox(height: 12),
              Button3D(
                label: lock.title,
                icon: Icons.quiz_rounded,
                color: AppColors.mint,
                edgeColor: AppColors.mintDeep,
                onPressed: () => context.push(Routes.lockExam(lock.id)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
