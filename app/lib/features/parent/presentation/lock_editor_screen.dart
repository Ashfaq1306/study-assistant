import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/platform/app_lock_platform.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/choice_controls.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../../app_lock/presentation/app_picker.dart';
import '../../study/domain/study_session.dart';
import '../../study/presentation/widgets/exam_settings_editor.dart';
import '../application/parent_providers.dart';
import '../domain/parent_models.dart';

/// A parent locks apps on a child's phone; passing an exam unlocks them.
class LockEditorScreen extends ConsumerStatefulWidget {
  const LockEditorScreen({super.key, required this.childId});

  final String childId;

  @override
  ConsumerState<LockEditorScreen> createState() => _LockEditorScreenState();
}

class _LockEditorScreenState extends ConsumerState<LockEditorScreen> {
  final _title = TextEditingController(text: 'Homework first');
  final _topics = TextEditingController();
  String? _subject;
  QuestionSet? _set;
  bool _ownQuestions = false;
  ExamSettings _exam = const ExamSettings(
    questionCount: 5,
    totalMarks: 10,
    passMarks: 5,
    questionTypes: [QuestionType.mcq, QuestionType.trueFalse],
  );
  Set<String> _apps = {wholePhone};
  bool _strict = true;
  bool _saving = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _title.dispose();
    _topics.dispose();
    super.dispose();
  }

  void _pickSet(QuestionSet set) {
    final minPercent = (ref.read(remoteConfigProvider).value ?? const RemoteConfig()).minPassPercent;
    final count = set.questions.length;
    final total = _exam.totalMarks < count ? count : _exam.totalMarks;
    setState(() {
      _set = set;
      _subject = set.subject;
      if (_topics.text.trim().isEmpty) _topics.text = set.title;
      _exam = _exam.copyWith(
        questionCount: count,
        totalMarks: total,
        passMarks: _exam.passMarks.clamp(ExamSettings.minPassMarks(total, minPercent), total),
        questionTypes: {for (final q in set.questions) q.type}.toList(),
      );
    });
  }

  Future<void> _save(ChildDetail child) async {
    final subject = _subject;
    setState(() {
      _error = null;
      _fieldErrors = const {};
    });
    if (subject == null) return setState(() => _error = 'Pick a subject.');
    if (_ownQuestions && _set == null) return setState(() => _error = 'Pick one of your question sets.');
    if (_apps.isEmpty) return setState(() => _error = 'Pick at least one app to lock.');
    setState(() => _saving = true);
    try {
      await ref
          .read(parentApiProvider)
          .lock(
            childId: widget.childId,
            title: _title.text,
            subject: subject,
            topics: _topics.text,
            lockedApps: _apps.toList(),
            strict: _strict || child.summary.age < 15,
            exam: _exam,
            questionSetId: _ownQuestions ? _set?.id : null,
          );
      ref
        ..invalidate(childDetailProvider(widget.childId))
        ..invalidate(childrenProvider);
      if (!mounted) return;
      showSnack(context, 'Locked. ${child.summary.firstName} unlocks it by passing the exam.');
      context.pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _fieldErrors = e.fieldErrors;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(childDetailProvider(widget.childId));
    return PageShell(
      title: 'Lock apps',
      child: detail.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => MessageBanner.error(e is ApiException ? e.message : 'Could not load this child.'),
        data: _form,
      ),
    );
  }

  Widget _form(ChildDetail child) {
    final text = Theme.of(context).textTheme;
    final config = ref.watch(remoteConfigProvider).value ?? const RemoteConfig();
    final sets = ref.watch(questionSetsProvider);
    final young = child.summary.age < 15;
    final apps = [for (final a in child.installedApps) InstalledApp(packageName: a.package, label: a.label)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${child.summary.firstName} unlocks these apps by passing a quiz. Nobody can skip it, but you can lift the lock any time.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 18),
        AppTextField(
          label: 'Name of the lock',
          controller: _title,
          icon: Icons.label_rounded,
          errorText: _fieldErrors['title'],
          maxLength: 60,
        ),
        const SizedBox(height: 18),
        Text('Questions', style: text.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ChoicePill(
              label: 'AI writes them',
              icon: Icons.auto_awesome_rounded,
              selected: !_ownQuestions,
              onTap: () => setState(() => _ownQuestions = false),
            ),
            ChoicePill(
              label: 'My own questions',
              icon: Icons.edit_note_rounded,
              selected: _ownQuestions,
              onTap: () => setState(() => _ownQuestions = true),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_ownQuestions)
          sets.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => MessageBanner.error(e is ApiException ? e.message : 'Could not load your questions.'),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final set in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ClayCard(
                      selected: _set?.id == set.id,
                      padding: const EdgeInsets.all(14),
                      onTap: () => _pickSet(set),
                      child: Row(
                        children: [
                          IconBadge(Icons.quiz_rounded, size: 40, color: AppColors.sunshineDeep),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(set.title, style: text.titleMedium),
                                Text('${set.subject} · ${set.questions.length} questions', style: text.bodyMedium),
                              ],
                            ),
                          ),
                          Icon(
                            _set?.id == set.id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            color: _set?.id == set.id ? AppColors.hero : AppColors.line,
                          ),
                        ],
                      ),
                    ),
                  ),
                Button3D.secondary(
                  label: list.isEmpty ? 'Write your first questions' : 'Write new questions',
                  icon: Icons.add_rounded,
                  onPressed: () async {
                    await context.push(Routes.questionSetEdit);
                    ref.invalidate(questionSetsProvider);
                  },
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
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
        const SizedBox(height: 18),
        AppTextField(
          label: _ownQuestions ? 'What it covers (optional note)' : 'What should the quiz cover?',
          controller: _topics,
          hint: 'e.g. Chapter 3: fractions and decimals',
          icon: Icons.menu_book_rounded,
          errorText: _fieldErrors['topics'],
          maxLines: 3,
          textInputAction: TextInputAction.newline,
        ),
        const SizedBox(height: 22),
        Text('Marks', style: text.titleMedium),
        const SizedBox(height: 10),
        if (_ownQuestions)
          ClayCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                NumberStepper(
                  label: 'Total marks',
                  value: _exam.totalMarks,
                  min: _exam.questionCount,
                  max: 500,
                  onChanged: (v) => setState(
                    () => _exam = _exam.copyWith(
                      totalMarks: v,
                      passMarks: _exam.passMarks.clamp(ExamSettings.minPassMarks(v, config.minPassPercent), v),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                NumberStepper(
                  label: 'Pass mark',
                  value: _exam.passMarks,
                  min: ExamSettings.minPassMarks(_exam.totalMarks, config.minPassPercent),
                  max: _exam.totalMarks,
                  onChanged: (v) => setState(() => _exam = _exam.copyWith(passMarks: v)),
                ),
              ],
            ),
          )
        else
          ExamSettingsEditor(
            value: _exam,
            onChanged: (v) => setState(() => _exam = v),
            minPassPercent: config.minPassPercent,
            maxQuestions: config.maxQuestions,
          ),
        const SizedBox(height: 22),
        Text('What to lock', style: text.titleMedium),
        const SizedBox(height: 10),
        AppPicker(selected: _apps, apps: apps, onChanged: (v) => setState(() => _apps = v)),
        const SizedBox(height: 14),
        SwitchListTile(
          value: _strict || young,
          onChanged: young ? null : (v) => setState(() => _strict = v),
          contentPadding: EdgeInsets.zero,
          title: const Text('Strict mode', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
            young
                ? 'Always on under 15: Settings and uninstalling are blocked too.'
                : 'Also blocks Settings and uninstalling while locked.',
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 12), MessageBanner.error(_error!)],
        const SizedBox(height: 18),
        Button3D(label: 'Lock now', icon: Icons.lock_rounded, loading: _saving, onPressed: () => _save(child)),
      ],
    );
  }
}
