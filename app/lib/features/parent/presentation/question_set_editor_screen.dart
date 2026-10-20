import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/remote_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/choice_controls.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../../study/domain/study_session.dart';
import '../application/parent_providers.dart';
import '../domain/parent_models.dart';

/// Write or change a question set: multiple choice, true/false or short answers.
class QuestionSetEditorScreen extends ConsumerStatefulWidget {
  const QuestionSetEditorScreen({super.key, this.set});

  /// Null for a new set.
  final QuestionSet? set;

  @override
  ConsumerState<QuestionSetEditorScreen> createState() => _QuestionSetEditorScreenState();
}

class _QuestionSetEditorScreenState extends ConsumerState<QuestionSetEditorScreen> {
  late final _title = TextEditingController(text: widget.set?.title ?? '');
  late String? _subject = widget.set?.subject;
  late final List<_Draft> _questions = [
    for (final q in widget.set?.questions ?? const <ParentQuestion>[]) _Draft.from(q),
    if (widget.set == null) ...[_Draft(), _Draft(), _Draft()],
  ];
  bool _saving = false;
  String? _error;

  bool get _inUse => (widget.set?.usedByActiveLocks ?? 0) > 0;

  @override
  void dispose() {
    _title.dispose();
    for (final q in _questions) {
      q.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final subject = _subject;
    setState(() => _error = null);
    if (_title.text.trim().isEmpty) return setState(() => _error = 'Name the question set.');
    if (subject == null) return setState(() => _error = 'Pick a subject.');
    if (_questions.length < 3) return setState(() => _error = 'Add at least 3 questions.');
    for (final (i, q) in _questions.indexed) {
      final problem = q.problem;
      if (problem != null) return setState(() => _error = 'Question ${i + 1}: $problem');
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(parentApiProvider)
          .saveQuestionSet(
            QuestionSet(
              id: widget.set?.id,
              title: _title.text,
              subject: subject,
              questions: [for (final q in _questions) q.toQuestion()],
            ),
          );
      if (!mounted) return;
      showSnack(context, 'Questions saved.');
      context.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete these questions?'),
        content: Text('"${widget.set!.title}" will be gone for good.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (!(ok ?? false) || !mounted) return;
    try {
      await ref.read(parentApiProvider).deleteQuestionSet(widget.set!.id!);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final config = ref.watch(remoteConfigProvider).value ?? const RemoteConfig();
    return PageShell(
      title: widget.set == null ? 'New questions' : 'Edit questions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_inUse) ...[
            const MessageBanner.info('A lock is using these questions. Lift the lock to change them.'),
            const SizedBox(height: 14),
          ],
          AppTextField(
            label: 'Name',
            controller: _title,
            hint: 'e.g. Fractions practice',
            icon: Icons.label_rounded,
            maxLength: 60,
          ),
          const SizedBox(height: 14),
          Text('Subject', style: text.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final s in {...config.subjects, ?_subject})
                ChoicePill(label: s, selected: _subject == s, onTap: () => setState(() => _subject = s)),
            ],
          ),
          const SizedBox(height: 22),
          for (final (i, q) in _questions.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _QuestionCard(
                key: ObjectKey(q),
                number: i + 1,
                draft: q,
                onChanged: () => setState(() {}),
                onRemove: _questions.length <= 3
                    ? null
                    : () => setState(() {
                        _questions.remove(q);
                        q.dispose();
                      }),
              ),
            ),
          if (_questions.length < 50)
            Button3D.secondary(
              label: 'Add a question',
              icon: Icons.add_rounded,
              onPressed: () => setState(() => _questions.add(_Draft())),
            ),
          if (_error != null) ...[const SizedBox(height: 14), MessageBanner.error(_error!)],
          const SizedBox(height: 18),
          Button3D(
            label: 'Save questions',
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: _inUse ? null : _save,
          ),
          if (widget.set != null && !_inUse) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _delete,
              icon: Icon(Icons.delete_outline_rounded, color: AppColors.coralDeep),
              label: Text('Delete', style: TextStyle(color: AppColors.coralDeep)),
            ),
          ],
        ],
      ),
    );
  }
}

/// One question being written.
class _Draft {
  _Draft({
    this.type = QuestionType.mcq,
    String prompt = '',
    List<String>? options,
    this.correct = 0,
    String answer = '',
    String keyPoints = '',
  }) : prompt = TextEditingController(text: prompt),
       options = [
         for (var i = 0; i < 4; i++)
           TextEditingController(text: options != null && i < options.length ? options[i] : ''),
       ],
       answer = TextEditingController(text: answer),
       keyPoints = TextEditingController(text: keyPoints);

  factory _Draft.from(ParentQuestion q) => _Draft(
    type: q.type,
    prompt: q.prompt,
    options: q.options,
    correct: q.type == QuestionType.mcq ? int.tryParse(q.answer) ?? 0 : (q.answer == 'false' ? 1 : 0),
    answer: q.type == QuestionType.short ? q.answer : '',
    keyPoints: q.keyPoints.join(', '),
  );

  QuestionType type;
  final TextEditingController prompt;
  final List<TextEditingController> options;

  /// MCQ: the right option's index. True/false: 0 = true, 1 = false.
  int correct;
  final TextEditingController answer;
  final TextEditingController keyPoints;

  String? get problem {
    if (prompt.text.trim().length < 3) return 'write the question.';
    switch (type) {
      case QuestionType.mcq:
        final choices = [for (final o in options) o.text.trim().toLowerCase()];
        if (choices.any((c) => c.isEmpty)) return 'fill in all four choices.';
        if (choices.toSet().length < 4) return 'make the four choices different.';
      case QuestionType.trueFalse:
        break;
      case QuestionType.short:
        if (answer.text.trim().isEmpty) return 'give the right answer.';
    }
    return null;
  }

  ParentQuestion toQuestion() => ParentQuestion(
    type: type,
    prompt: prompt.text,
    options: type == QuestionType.mcq ? [for (final o in options) o.text] : const [],
    answer: switch (type) {
      QuestionType.mcq => '$correct',
      QuestionType.trueFalse => correct == 0 ? 'true' : 'false',
      QuestionType.short => answer.text,
    },
    keyPoints: type == QuestionType.short
        ? [
            for (final k in keyPoints.text.split(','))
              if (k.trim().isNotEmpty) k.trim(),
          ].take(6).toList()
        : const [],
  );

  void dispose() {
    prompt.dispose();
    answer.dispose();
    keyPoints.dispose();
    for (final o in options) {
      o.dispose();
    }
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({super.key, required this.number, required this.draft, required this.onChanged, this.onRemove});

  final int number;
  final _Draft draft;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final q = draft;
    return ClayCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Question $number', style: Theme.of(context).textTheme.titleMedium)),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Remove question',
                  onPressed: onRemove,
                  icon: Icon(Icons.delete_outline_rounded, color: AppColors.coralDeep),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in QuestionType.values)
                ChoicePill(
                  label: t.label,
                  selected: q.type == t,
                  onTap: () {
                    q
                      ..type = t
                      ..correct = 0;
                    onChanged();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          AppTextField(label: 'Question', controller: q.prompt, maxLines: 3, textInputAction: TextInputAction.newline),
          const SizedBox(height: 10),
          switch (q.type) {
            QuestionType.mcq => Column(
              children: [
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Right answer',
                          onPressed: () {
                            q.correct = i;
                            onChanged();
                          },
                          icon: Icon(
                            q.correct == i ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                            color: q.correct == i ? AppColors.mintDeep : AppColors.line,
                          ),
                        ),
                        Expanded(
                          child: AppTextField(label: 'Choice ${String.fromCharCode(65 + i)}', controller: q.options[i]),
                        ),
                      ],
                    ),
                  ),
                Text(
                  'Tap the circle next to the right answer.',
                  style: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            QuestionType.trueFalse => Wrap(
              spacing: 10,
              children: [
                for (final (i, label) in ['True', 'False'].indexed)
                  ChoicePill(
                    label: label,
                    icon: Icons.check_rounded,
                    color: AppColors.mintDeep,
                    selected: q.correct == i,
                    onTap: () {
                      q.correct = i;
                      onChanged();
                    },
                  ),
              ],
            ),
            QuestionType.short => Column(
              children: [
                AppTextField(
                  label: 'Right answer',
                  controller: q.answer,
                  maxLines: 2,
                  textInputAction: TextInputAction.newline,
                ),
                const SizedBox(height: 10),
                AppTextField(
                  label: 'Words the answer must include (optional)',
                  controller: q.keyPoints,
                  hint: 'e.g. photosynthesis, sunlight',
                ),
              ],
            ),
          },
        ],
      ),
    );
  }
}
