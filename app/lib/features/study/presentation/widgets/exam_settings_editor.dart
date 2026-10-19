import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/choice_controls.dart';
import '../../../../core/widgets/clay_card.dart';
import '../../../../core/widgets/wizard.dart';
import '../../domain/study_session.dart';

/// Question count, marks, pass mark (never under [minPassPercent]), question
/// types and difficulty. Keeps the settings valid as the user edits.
class ExamSettingsEditor extends StatelessWidget {
  const ExamSettingsEditor({
    super.key,
    required this.value,
    required this.onChanged,
    required this.minPassPercent,
    required this.maxQuestions,
  });

  final ExamSettings value;
  final ValueChanged<ExamSettings> onChanged;
  final int minPassPercent;
  final int maxQuestions;

  static const typeIcons = {
    QuestionType.mcq: Icons.checklist_rounded,
    QuestionType.trueFalse: Icons.rule_rounded,
    QuestionType.short: Icons.edit_note_rounded,
  };

  void _emit({int? count, int? total, int? pass, List<QuestionType>? types, Difficulty? difficulty}) {
    final questionCount = count ?? value.questionCount;
    // Every question is worth at least one mark.
    final totalMarks = (total ?? value.totalMarks).clamp(questionCount, 500);
    final minPass = ExamSettings.minPassMarks(totalMarks, minPassPercent);
    final passMarks = (pass ?? value.passMarks).clamp(minPass, totalMarks);
    onChanged(
      ExamSettings(
        questionCount: questionCount,
        totalMarks: totalMarks,
        passMarks: passMarks,
        questionTypes: types ?? value.questionTypes,
        difficulty: difficulty ?? value.difficulty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final minPass = ExamSettings.minPassMarks(value.totalMarks, minPassPercent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClayCard(
          child: Column(
            children: [
              NumberStepper(
                label: 'Questions',
                value: value.questionCount,
                min: 3,
                max: maxQuestions,
                onChanged: (v) => _emit(count: v),
              ),
              const Divider(height: 24, color: AppColors.line),
              NumberStepper(
                label: 'Total marks',
                value: value.totalMarks,
                min: value.questionCount,
                max: 500,
                step: 5,
                onChanged: (v) => _emit(total: v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ClayCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Pass mark', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  Text(
                    '${value.passMarks} / ${value.totalMarks}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.mintSoft, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      '${value.passPercent}%',
                      style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.mintDeep),
                    ),
                  ),
                ],
              ),
              Slider(
                value: value.passMarks.toDouble(),
                min: minPass.toDouble(),
                max: value.totalMarks.toDouble(),
                divisions: value.totalMarks > minPass ? value.totalMarks - minPass : null,
                label: '${value.passMarks}',
                onChanged: value.totalMarks > minPass ? (v) => _emit(pass: v.round()) : null,
              ),
              Text(
                'You need at least $minPassPercent% to pass. Aim higher if you like!',
                style: const TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const FieldLabel('Question types'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final type in QuestionType.values)
              ChoicePill(
                label: type.label,
                icon: typeIcons[type],
                selected: value.questionTypes.contains(type),
                onTap: () {
                  final types = [...value.questionTypes];
                  if (types.contains(type)) {
                    if (types.length > 1) types.remove(type); // keep at least one
                  } else {
                    types.add(type);
                  }
                  _emit(types: types);
                },
              ),
          ],
        ),
        const SizedBox(height: 22),
        const FieldLabel('Difficulty'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final d in Difficulty.values)
              ChoicePill(
                label: d.label,
                color: switch (d) {
                  Difficulty.easy => AppColors.mintDeep,
                  Difficulty.medium => AppColors.sunshineDeep,
                  Difficulty.hard => AppColors.coralDeep,
                },
                selected: value.difficulty == d,
                onTap: () => _emit(difficulty: d),
              ),
          ],
        ),
      ],
    );
  }
}
