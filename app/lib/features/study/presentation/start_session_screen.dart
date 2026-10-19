import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
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
import 'widgets/study_photos.dart';

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
  final _notes = TextEditingController();

  /// Photos of the study material, uploaded once the session starts.
  final List<Uint8List> _photos = [];

  int _step = 0;
  String? _subject;
  bool _otherSubject = false;
  int _minutes = 25;
  // A short, easy quiz by default; students can make it longer or harder.
  ExamSettings _exam = const ExamSettings(
    questionCount: 5,
    totalMarks: 10,
    passMarks: 5,
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
    _notes.dispose();
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
      final session = await ref
          .read(activeSessionProvider.notifier)
          .start(
            StartSessionRequest(
              subject: _chosenSubject,
              topics: _topics.text,
              notes: _notes.text,
              plannedMinutes: _minutes,
              exam: _exam,
              lockedApps: _apps.toList(),
              strict: _strict,
            ),
          );
      unawaited(SharedPreferences.getInstance().then((p) => p.setStringList(_lastAppsKey, _apps.toList())));
      if (_photos.isNotEmpty) await _uploadPhotos(session.id);
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

  /// The session has started: a photo that fails to upload can be added again from the timer.
  Future<void> _uploadPhotos(String sessionId) async {
    var failed = 0;
    for (final bytes in _photos) {
      try {
        await ref.read(studyApiProvider).addPhoto(sessionId, bytes, mime: imageMime(bytes));
      } on ApiException {
        failed++;
      }
    }
    await ref.read(activeSessionProvider.notifier).refresh();
    if (failed > 0 && mounted) {
      showSnack(
        context,
        "${failed == 1 ? 'A photo' : '$failed photos'} didn't upload. You can add them on the timer screen.",
      );
    }
  }

  Future<void> _addPhoto() async {
    final bytes = await pickStudyPhoto(context);
    if (bytes != null && mounted) setState(() => _photos.add(bytes));
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
        ),
        const SizedBox(height: 20),
        AppTextField(
          label: 'Your plan (optional)',
          controller: _notes,
          hint: 'e.g. Read pages 12-14, then practise 5 sums',
          icon: Icons.edit_note_rounded,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.newline,
          maxLines: 4,
          maxLength: 1000,
        ),
        const SizedBox(height: 12),
        const FieldLabel('Photos of what you will study (optional)'),
        const Text(
          'Snap your book pages or notes. Your quiz will ask about them.',
          style: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (i, bytes) in _photos.indexed)
              PhotoThumb(image: MemoryImage(bytes), onRemove: () => setState(() => _photos.removeAt(i))),
            if (_photos.length < maxStudyPhotos) AddPhotoTile(onTap: _addPhoto),
          ],
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
        if (_lockNotReady) ...[
          const SizedBox(height: 16),
          ClayCard(
            color: AppColors.coralSoft,
            glow: AppColors.coralDeep,
            padding: const EdgeInsets.all(16),
            onTap: _setUpAppLock,
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: AppColors.coralDeep),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'App lock is off on this phone. Tap to turn it on, so these apps really get blocked.',
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.coralDeep),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.coralDeep),
              ],
            ),
          ),
        ],
        const SizedBox(height: 28),
        Button3D(label: 'Continue', onPressed: () => _goTo(4)),
      ],
    );
  }

  /// Locked apps need the blocker: without it a session would only be a timer.
  bool get _lockNotReady {
    final status = ref.watch(appLockProvider).value;
    return _apps.isNotEmpty && status != null && status.supported && !status.ready;
  }

  Future<void> _setUpAppLock() async {
    await context.push(Routes.appLock);
    if (mounted) await ref.read(appLockProvider.notifier).refresh();
  }

  Widget _reviewPage() {
    final lockOff = _lockNotReady;
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
              if (_notes.text.trim().isNotEmpty)
                _SummaryRow(icon: Icons.edit_note_rounded, label: 'Plan', value: _notes.text.trim()),
              if (_photos.isNotEmpty)
                _SummaryRow(
                  icon: Icons.photo_library_rounded,
                  label: 'Photos',
                  value: '${_photos.length} for your quiz',
                ),
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
        if (lockOff) ...[
          const SizedBox(height: 16),
          const MessageBanner.error(
            'App lock is off on this phone, so nothing would be blocked. Turn it on first: it takes a minute.',
          ),
        ],
        if (_error != null) ...[const SizedBox(height: 16), MessageBanner.error(_error!.message)],
        const SizedBox(height: 28),
        if (lockOff) ...[
          Button3D(label: 'Turn on App lock', icon: Icons.shield_rounded, onPressed: _setUpAppLock),
          const SizedBox(height: 12),
          Button3D.secondary(
            label: 'Study without locking apps',
            icon: Icons.lock_open_rounded,
            onPressed: () => setState(() => _apps = {}),
          ),
        ] else
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
