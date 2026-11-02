import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../application/parent_providers.dart';

/// A parent's own question sets, used instead of AI questions for a lock.
class QuestionSetsScreen extends ConsumerWidget {
  const QuestionSetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sets = ref.watch(questionSetsProvider);
    final text = Theme.of(context).textTheme;

    Future<void> open([Object? set]) async {
      await context.push(Routes.questionSetEdit, extra: set);
      ref.invalidate(questionSetsProvider);
    }

    return PageShell(
      title: 'Your questions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Write a quiz yourself. When you lock apps, choose it instead of AI questions.', style: text.bodyMedium),
          const SizedBox(height: 16),
          sets.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => MessageBanner.error(e is ApiException ? e.message : 'Could not load your questions.'),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (list.isEmpty)
                  ClayCard(
                    child: Column(
                      children: [
                        IconBadge(Icons.quiz_rounded, size: 64, color: AppColors.sunshineDeep),
                        const SizedBox(height: 8),
                        Text('No questions yet', style: text.titleMedium),
                        const SizedBox(height: 4),
                        const Text('Three questions is enough to start.', textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                for (final set in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ClayCard(
                      glow: AppColors.sunshineDeep,
                      padding: const EdgeInsets.all(16),
                      onTap: () => open(set),
                      child: Row(
                        children: [
                          IconBadge(Icons.quiz_rounded, size: 46, color: AppColors.sunshineDeep),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(set.title, style: text.titleMedium),
                                Text(
                                  '${set.subject} · ${set.questions.length} questions'
                                  '${set.usedByActiveLocks > 0 ? ' · in use' : ''}',
                                  style: text.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Button3D(label: 'Write questions', icon: Icons.add_rounded, onPressed: open),
        ],
      ),
    );
  }
}
