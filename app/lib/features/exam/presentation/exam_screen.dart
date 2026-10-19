import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/confetti.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../../../core/widgets/pencil_3d.dart';
import '../../../core/widgets/timer_ring.dart';
import '../../app_lock/application/app_lock_controller.dart';
import '../../study/application/study_providers.dart';
import '../../study/domain/study_session.dart';
import '../domain/exam.dart';

/// Answers typed so far, per exam, so leaving the screen does not lose them.
final _draftAnswersProvider = Provider<Map<String, Map<String, String>>>((ref) => {});

/// The unlock exam for the running study session.
class ExamScreen extends ConsumerStatefulWidget {
  const ExamScreen({super.key});

  @override
  ConsumerState<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends ConsumerState<ExamScreen> {
  Exam? _exam;
  ApiException? _error;
  DateTime? _retryAt;
  bool _loading = true;
  bool _submitting = false;
  int _index = 0;
  Timer? _ticker;
  final _pages = PageController();

  Map<String, String> get _answers => ref.read(_draftAnswersProvider).putIfAbsent(_exam!.id, () => {});

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pages.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _retryAt = null;
    });
    final session = ref.read(activeSessionProvider).value ?? await ref.read(activeSessionProvider.future);
    if (!mounted) return;
    if (session == null || session.status != SessionStatus.examPending) {
      setState(() {
        _loading = false;
        _error = const ApiException(code: 'NO_EXAM', message: 'There is no exam waiting. Start a study session first.');
      });
      return;
    }
    try {
      final exam = await ref.read(examApiProvider).startForSession(session.id);
      if (mounted) setState(() => _exam = exam);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _retryAt = DateTime.tryParse(e.details['retryAt'] as String? ?? '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _tick() {
    final exam = _exam;
    if (!mounted) return;
    // Out of time: hand in whatever is answered.
    if (exam != null && exam.result == null && !_submitting) {
      if (!ref.read(serverClockProvider).now().isBefore(exam.expiresAt)) {
        _submit();
        return;
      }
    }
    setState(() {});
  }

  Future<void> _submit() async {
    final exam = _exam!;
    setState(() => _submitting = true);
    try {
      final graded = await ref.read(examApiProvider).submit(exam.id, Map.of(_answers));
      if (!mounted) return;
      setState(() => _exam = graded);
      if (graded.result?.passed ?? false) {
        ref.read(_draftAnswersProvider).remove(exam.id);
        // Unlock straight away instead of waiting for the next background sync.
        unawaited(ref.read(appLockProvider.notifier).refresh());
        unawaited(ref.read(activeSessionProvider.notifier).refresh());
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
      if (e.code == 'EXAM_EXPIRED' && mounted) await _load();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmSubmit() async {
    final exam = _exam!;
    final unanswered = exam.questions.where((q) => (_answers[q.id] ?? '').trim().isEmpty).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hand in your exam?'),
        content: Text(
          unanswered == 0
              ? 'Every question is answered. Ready?'
              : '$unanswered unanswered. You can go back and finish them.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep going')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hand in')),
        ],
      ),
    );
    if (ok ?? false) await _submit();
  }

  void _goTo(int index) {
    FocusScope.of(context).unfocus();
    setState(() => _index = index);
    _pages.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final exam = _exam;
    if (_loading) return const _Writing();
    if (exam == null) return _problem();
    if (exam.result != null) return _ResultView(exam: exam);
    return _taking(exam);
  }

  Widget _problem() {
    final e = _error!;
    final retryAt = _retryAt;
    final wait = retryAt == null ? Duration.zero : retryAt.difference(ref.read(serverClockProvider).now());
    final waiting = e.code == 'EXAM_COOLDOWN' && wait > Duration.zero;
    return PageShell(
      title: 'Exam',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: IconBadge(
              waiting ? Icons.self_improvement_rounded : Icons.info_rounded,
              size: 84,
              color: waiting ? AppColors.mintDeep : AppColors.sunshineDeep,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            waiting ? 'Quick revision break' : 'Not right now',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            waiting ? 'Look over your notes, then try again with fresh questions.' : e.message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 24),
          Button3D(
            label: waiting ? 'Try again in ${_mmss(wait)}' : 'Try again',
            icon: Icons.refresh_rounded,
            onPressed: waiting || e.code == 'NO_EXAM' ? null : _load,
          ),
          const SizedBox(height: 12),
          Button3D.secondary(
            label: 'Revise with the AI helper',
            icon: Icons.smart_toy_rounded,
            onPressed: () => context.push(Routes.tutor),
          ),
        ],
      ),
    );
  }

  Widget _taking(Exam exam) {
    final left = exam.expiresAt.difference(ref.read(serverClockProvider).now());
    final urgent = left < const Duration(minutes: 1);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leave the exam?'),
            content: const Text('Your answers are kept, but the timer keeps running.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
            ],
          ),
        );
        if ((leave ?? false) && mounted) context.pop();
      },
      child: PageShell(
        title: exam.subject,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: urgent ? AppColors.coralSoft : AppColors.card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_rounded, size: 18, color: urgent ? AppColors.coralDeep : AppColors.violet),
                const SizedBox(width: 4),
                Text(
                  _mmss(left),
                  style: TextStyle(fontWeight: FontWeight.w900, color: urgent ? AppColors.coralDeep : AppColors.ink),
                ),
              ],
            ),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (exam.isPractice) ...[
              const MessageBanner.info('Practice round: these are built-in questions, so some may be general ones.'),
              const SizedBox(height: 12),
            ],
            Text(
              'Question ${_index + 1} of ${exam.questions.length} · pass ${exam.passMarks}/${exam.totalMarks}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (_index + 1) / exam.questions.length,
                minHeight: 10,
                backgroundColor: AppColors.violetSoft,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 470,
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final (i, q) in exam.questions.indexed)
                    _QuestionCard(
                      number: i + 1,
                      question: q,
                      answer: _answers[q.id],
                      onAnswer: (value) => setState(() => _answers[q.id] = value),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_index > 0) ...[
                  Expanded(
                    child: Button3D.secondary(
                      label: 'Back',
                      icon: Icons.chevron_left_rounded,
                      onPressed: () => _goTo(_index - 1),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: _index < exam.questions.length - 1
                      ? Button3D(label: 'Next', icon: Icons.chevron_right_rounded, onPressed: () => _goTo(_index + 1))
                      : Button3D(
                          label: 'Hand in',
                          icon: Icons.check_rounded,
                          color: AppColors.mint,
                          edgeColor: AppColors.mintDeep,
                          loading: _submitting,
                          onPressed: _confirmSubmit,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _mmss(Duration d) {
  final s = d.inSeconds.clamp(0, 359999);
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class _Writing extends StatelessWidget {
  const _Writing();

  @override
  Widget build(BuildContext context) {
    return PageShell(
      showBack: false,
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Pencil3D(size: 220, interactive: false),
          Text('Writing your exam…', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Questions about exactly what you studied. Take a deep breath!', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          const SizedBox(width: 180, child: LinearProgressIndicator(minHeight: 8)),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.number, required this.question, required this.answer, required this.onAnswer});

  final int number;
  final ExamQuestion question;
  final String? answer;
  final ValueChanged<String> onAnswer;

  static const _letters = ['A', 'B', 'C', 'D'];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClayCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Q$number · ${question.marks} ${question.marks == 1 ? 'mark' : 'marks'} · ${question.type.label}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.violet),
                ),
                const SizedBox(height: 8),
                Text(question.prompt, style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.3)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (question.type == QuestionType.short)
            _ShortAnswer(initial: answer ?? '', onChanged: onAnswer)
          else
            for (final (i, option) in question.options.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _Option(
                  badge: question.type == QuestionType.trueFalse ? null : _letters[i],
                  icon: question.type == QuestionType.trueFalse
                      ? (i == 0 ? Icons.check_circle_rounded : Icons.cancel_rounded)
                      : null,
                  label: option,
                  selected: answer == question.answerForOption(i),
                  onTap: () => onAnswer(question.answerForOption(i)),
                ),
              ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.label, required this.selected, required this.onTap, this.badge, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: ClayCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        radius: 20,
        selected: selected,
        onTap: onTap,
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.violet : AppColors.violetSoft,
                shape: BoxShape.circle,
              ),
              child: icon != null
                  ? Icon(icon, size: 20, color: selected ? Colors.white : AppColors.violet)
                  : Text(
                      badge ?? '',
                      style: TextStyle(fontWeight: FontWeight.w900, color: selected ? Colors.white : AppColors.violet),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortAnswer extends StatefulWidget {
  const _ShortAnswer({required this.initial, required this.onChanged});

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_ShortAnswer> createState() => _ShortAnswerState();
}

class _ShortAnswerState extends State<_ShortAnswer> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppTextField(
    label: 'Your answer',
    controller: _controller,
    hint: 'Write a short answer',
    icon: Icons.edit_note_rounded,
    textInputAction: TextInputAction.done,
    textCapitalization: TextCapitalization.sentences,
    onChanged: widget.onChanged,
  );
}

/// Score, pass/fail, and a review of every question with the right answer.
class _ResultView extends ConsumerWidget {
  const _ResultView({required this.exam});

  final Exam exam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = exam.result!;
    final text = Theme.of(context).textTheme;
    final cooldown = ref.watch(remoteConfigProvider).value?.examRetryCooldownSeconds ?? 120;
    final missing = (exam.passMarks - result.score).clamp(0, exam.totalMarks);

    return Stack(
      children: [
        PageShell(
          title: 'Your result',
          showBack: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: TimerRing(
                  size: 220,
                  progress: result.score / exam.totalMarks,
                  done: result.passed,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_fmt(result.score)}/${exam.totalMarks}',
                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: AppColors.ink),
                      ),
                      Text(
                        result.passed ? 'Passed!' : 'Not yet',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: result.passed ? AppColors.mintDeep : AppColors.coralDeep,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (result.passed)
                const MessageBanner.success('Brilliant work! Your apps are unlocked.')
              else
                MessageBanner.info(
                  'You needed ${exam.passMarks} marks: just ${_fmt(missing.toDouble())} more. '
                  'Your apps stay locked. Revise the answers below, then try again in about ${(cooldown / 60).ceil()} min '
                  'with fresh questions.',
                ),
              const SizedBox(height: 20),
              Button3D(
                label: result.passed ? 'Back home' : 'Revise with the AI helper',
                icon: result.passed ? Icons.home_rounded : Icons.smart_toy_rounded,
                onPressed: () => result.passed ? context.go(Routes.home) : context.push(Routes.tutor),
              ),
              if (!result.passed) ...[
                const SizedBox(height: 12),
                Button3D.secondary(
                  label: 'Back to my session',
                  icon: Icons.timer_rounded,
                  onPressed: () => context.go(Routes.studySession),
                ),
              ],
              const SizedBox(height: 26),
              Text('Review', style: text.titleLarge),
              const SizedBox(height: 12),
              for (final (i, q) in exam.questions.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ReviewTile(
                    number: i + 1,
                    question: q,
                    result: result.questions.firstWhere((r) => r.id == q.id),
                  ),
                ),
            ],
          ),
        ),
        if (result.passed) const Positioned.fill(child: Confetti()),
      ],
    );
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.number, required this.question, required this.result});

  final int number;
  final ExamQuestion question;
  final QuestionResult result;

  String _given() {
    final given = result.given;
    if (given == null || given.isEmpty) return 'No answer';
    if (question.type == QuestionType.mcq) return question.options.elementAtOrNull(int.tryParse(given) ?? -1) ?? given;
    if (question.type == QuestionType.trueFalse) return given == 'true' ? 'True' : 'False';
    return given;
  }

  @override
  Widget build(BuildContext context) {
    final color = result.correct
        ? AppColors.mintDeep
        : (result.awarded > 0 ? AppColors.sunshineDeep : AppColors.coralDeep);
    return ClayCard(
      glow: color,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(result.correct ? Icons.check_rounded : Icons.close_rounded, size: 36, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Question $number',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink),
                ),
              ),
              Text(
                '${_ResultView._fmt(result.awarded)}/${result.marks}',
                style: TextStyle(fontWeight: FontWeight.w900, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            question.prompt,
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 8),
          Text(
            'Your answer: ${_given()}',
            style: const TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
          ),
          if (!result.correct)
            Text(
              'Right answer: ${result.correctAnswer}',
              style: const TextStyle(color: AppColors.mintDeep, fontWeight: FontWeight.w800),
            ),
          if (result.explanation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(result.explanation, style: const TextStyle(color: AppColors.inkSoft)),
          ],
          if (question.type == QuestionType.short && result.feedback.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              result.feedback,
              style: const TextStyle(color: AppColors.violet, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}
