import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';

/// The unlock exam. Questions arrive with the AI exam feature.
class ExamScreen extends StatelessWidget {
  const ExamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Exam',
      child: Column(
        children: [
          const IconBadge(Icons.quiz_rounded, size: 80, color: AppColors.sunshineDeep),
          const SizedBox(height: 16),
          Text(
            'AI exams arrive in the next update',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ],
      ),
    );
  }
}
