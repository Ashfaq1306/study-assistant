import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/routes.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/choice_controls.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/wizard.dart';
import '../../app_lock/application/app_lock_controller.dart';
import '../../app_lock/presentation/app_picker.dart';
import '../../auth/application/auth_controller.dart';
import '../application/study_providers.dart';
import '../data/study_api.dart';
import '../domain/study_session.dart';
import 'widgets/exam_settings_editor.dart';

/// Plan a study session: what, how long, and the exam that unlocks the apps.
class StartSessionScreen extends ConsumerStatefulWidget {
  const StartSessionScreen({super.key});

  @override
  ConsumerState<StartSessionScreen> createState() => _StartSessionScreenState();
}

class _StartSessionScreenState extends ConsumerState<StartSessionScreen> {
  static const _presets = [15, 25, 45, 60, 90];

  final _pages = PageController();
  final _topics = TextEditingController();
  final _customSubject = TextEditingController();

  int _step = 0;
  String? _subject;
  bool _otherSubject = false;
  int _minutes = 25;
  ExamSettings _exam = const ExamSettings(
    questionCount: 10,
    totalMarks: 50,
    passMarks: 30,
    questionTypes: [QuestionType.mcq, QuestionType.trueFalse],
  );
  Set<String> _apps = {};
  bool _strict = true;
  bool _loading = false;
  ApiException? _error;
  String? _whatError;

  static const _lastAppsKey = 'study.lastLockedApps';

  @override
  void initState() {
    super.initState();
    _loadLastApps();
  }

  /// Students usually lock the same apps each time: start from the last choice.
  Future<void> _loadLastApps() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getStringList(_lastAppsKey);
      if (saved != null && mounted && _apps.isEmpty) setState(() => _apps = saved.toSet());
    } on Object {
      // Preferences unavailable: start empty.
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _topics.dispose();
    _customSubject.dispose();
    super.dispose();
  }

  String get _chosenSubject => _otherSubject ? _customSubject.text.trim() : (_subject ?? '');

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    _pages.animateToPage(step, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  void _back() => _step == 0 ? context.pop() : _goTo(_step - 1);

  void _nextFromWhat() {
    final error = _chosenSubject.isEmpty
        ? 'Pick a subject.'
        : _topics.text.trim().length < 2
        ? 'Write what you will study, e.g. "Chapter 3: Fractions".'
        : null;
    setState(() => _whatError = error);
    if (error == null) _goTo(1);
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(activeSessionProvider.notifier)
          .start(
            StartSessionRequest(
              subject: _chosenSubject,
              topics: _topics.text,
              plannedMinutes: _minutes,
              exam: _exam,
              lockedApps: _apps.toList(),
              strict: _strict,
            ),
          );
      unawaited(SharedPreferences.getInstance().then((p) => p.setStringList(_lastAppsKey, _apps.toList())));
      // Hand the new lock to the blocker straight away.
      unawaited(ref.read(appLockProvider.notifier).refresh());
      if (mounted) context.pushReplacement(Routes.studySession);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'SESSION_ACTIVE') {
        // Home was out of date: take the student to the session that is running.
        await ref.read(activeSessionProvider.notifier).refresh();
        if (mounted) context.pushReplacement(Routes.studySession);
        return;
      }
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(remoteConfigProvider).value ?? const RemoteConfig();
    // Keep the defaults valid if the admin raised the floor.
    final minPass = ExamSettings.minPassMarks(_exam.totalMarks, config.minPassPercent);
    if (_exam.passMarks < minPass) _exam = _exam.copyWith(passMarks: minPass);
    _minutes = _minutes.clamp(config.minStudyMinutes, config.maxStudyMinutes);

    return WizardScaffold(
      controller: _pages,
      step: _step,
      onBack: _back,
      pages: [_whatPage(config), _durationPage(config), _examPage(config), _appsPage(), _reviewPage()],
    );
  }

  Widget _whatPage(RemoteConfig config) {
    return WizardPage(
      icon: Icons.menu_book_rounded,
      title: 'What will you study?',
      subtitle: 'Your exam will be about exactly this.',
      children: [
        const FieldLabel('Subject'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final s in config.subjects)
              ChoicePill(
                label: s,
                selected: !_otherSubject && _subject == s,
                onTap: () => setState(() {
                  _subject = s;
                  _otherSubject = false;
                }),
              ),
            ChoicePill(
              label: 'Other',
              icon: Icons.add_rounded,
              selected: _otherSubject,
              onTap: () => setState(() => _otherSubject = true),
            ),
          ],
        ),
        if (_otherSubject) ...[
          const SizedBox(height: 16),
          AppTextField(
            label: 'Your subject',
            controller: _customSubject,
            icon: Icons.school_rounded,
            textCapitalization: TextCapitalization.words,
            autofocus: true,
          ),
        ],
        const SizedBox(height: 20),
        AppTextField(
          label: 'Topics',
          controller: _topics,
          hint: 'e.g. Chapter 3: Fractions and decimals',
          icon: Icons.topic_rounded,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _nextFromWhat(),
        ),
        if (_whatError != null) ...[const SizedBox(height: 16), MessageBanner.error(_whatError!)],
        const SizedBox(height: 28),
        Button3D(label: 'Continue', onPressed: _nextFromWhat),
      ],
    );
  }

  Widget _durationPage(RemoteConfig config) {
    return WizardPage(
      icon: Icons.timer_rounded,
      title: 'How long?',
      subtitle: 'Your chosen apps stay locked until you pass the exam afterwards.',
      color: AppColors.mintDeep,
      children: [
        ClayCard(
          child: Column(
            children: [
              Text(
                '$_minutes',
                style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, height: 1, color: AppColors.ink),
              ),
              const Text(
                'minutes',
                style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft),
              ),
              Slider(
                value: _minutes.toDouble(),
                min: config.minStudyMinutes.toDouble(),
                max: config.maxStudyMinutes.toDouble(),
                divisions: (config.maxStudyMinutes - config.minStudyMinutes) ~/ 5 > 0
                    ? (config.maxStudyMinutes - config.minStudyMinutes) ~/ 5
                    : null,
                label: '$_minutes min',
                onChanged: (v) => setState(() => _minutes = (v / 5).round() * 5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            for (final p in _presets)
              if (p >= config.minStudyMinutes && p <= config.maxStudyMinutes)
                ChoicePill(
                  label: '$p min',
                  color: AppColors.mintDeep,
                  selected: _minutes == p,
                  onTap: () => setState(() => _minutes = p),
                ),
          ],
        ),
        const SizedBox(height: 16),
        MessageBanner.info('You can finish early once you are ${config.earlyFinishPercent}% of the way through.'),
        const SizedBox(height: 28),
        Button3D(label: 'Continue', onPressed: () => _goTo(2)),
      ],
    );
  }

  Widget _examPage(RemoteConfig config) {
    return WizardPage(
      icon: Icons.quiz_rounded,
      title: 'Your unlock exam',
      subtitle: 'You set the rules. Pass it to get your apps back.',
      color: AppColors.sunshineDeep,
      children: [
        ExamSettingsEditor(
          value: _exam,
          minPassPercent: config.minPassPercent,
          maxQuestions: config.maxQuestions,
          onChanged: (v) => setState(() => _exam = v),
        ),
        const SizedBox(height: 28),
        Button3D(label: 'Continue', onPressed: () => _goTo(3)),
      ],
    );
  }

  Widget _appsPage() {
    final auth = ref.watch(authControllerProvider);
    final mustBeStrict = auth is AuthSignedIn && auth.user.parentalControlRequired;
    return WizardPage(
      icon: Icons.lock_rounded,
      title: 'Lock distractions',
      subtitle: 'These stay locked until you pass your exam.',
      children: [
        AppPicker(selected: _apps, onChanged: (v) => setState(() => _apps = v)),
        const SizedBox(height: 16),
        ClayCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: mustBeStrict || _strict,
            onChanged: mustBeStrict ? null : (v) => setState(() => _strict = v),
            secondary: const IconBadge(Icons.admin_panel_settings_rounded, size: 44),
            title: const Text('Strict mode', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              mustBeStrict
                  ? 'Always on for students under 15.'
                  : 'Also blocks Settings and app uninstalls while locked, so you cannot cheat.',
            ),
          ),
        ),
        const SizedBox(height: 28),
        Button3D(label: 'Continue', onPressed: () => _goTo(4)),
      ],
    );
  }

  Widget _reviewPage() {
    return WizardPage(
      icon: Icons.rocket_launch_rounded,
      title: 'Ready?',
      subtitle: 'Once you start, the timer runs and your apps lock.',
      color: AppColors.coralDeep,
      children: [
        ClayCard(
          child: Column(
            children: [
              _SummaryRow(icon: Icons.menu_book_rounded, label: 'Subject', value: _chosenSubject),
              _SummaryRow(icon: Icons.topic_rounded, label: 'Topics', value: _topics.text.trim()),
              _SummaryRow(icon: Icons.timer_rounded, label: 'Study time', value: '$_minutes minutes'),
              _SummaryRow(
                icon: Icons.quiz_rounded,
                label: 'Exam',
                value: '${_exam.questionCount} questions · pass ${_exam.passMarks}/${_exam.totalMarks}',
              ),
              _SummaryRow(
                icon: Icons.lock_rounded,
                label: 'Locked',
                value: _apps.contains(wholePhone)
                    ? 'Whole phone'
                    : _apps.isEmpty
                    ? 'Nothing'
                    : '${_apps.length} apps',
              ),
            ],
          ),
        ),
        if (_apps.isNotEmpty && !(ref.watch(appLockProvider).value?.ready ?? true)) ...[
          const SizedBox(height: 16),
          ClayCard(
            color: AppColors.coralSoft,
            glow: AppColors.coralDeep,
            padding: const EdgeInsets.all(16),
            onTap: () => context.push(Routes.appLock),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: AppColors.coralDeep),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'App lock is off, so your apps will not be blocked. Tap to turn it on.',
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.coralDeep),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[const SizedBox(height: 16), MessageBanner.error(_error!.message)],
        const SizedBox(height: 28),
        Button3D(label: 'Start studying', icon: Icons.play_arrow_rounded, loading: _loading, onPressed: _start),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.violet, size: 22),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
