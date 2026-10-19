import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../../../core/widgets/timer_ring.dart';
import '../application/study_providers.dart';
import '../domain/study_session.dart';
import 'widgets/study_photos.dart';

/// The running session: a countdown while studying, then the way to the exam.
class ActiveSessionScreen extends ConsumerStatefulWidget {
  const ActiveSessionScreen({super.key});

  @override
  ConsumerState<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends ConsumerState<ActiveSessionScreen> {
  Timer? _ticker;
  bool _finishing = false;
  bool _refreshedAtZero = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    final session = ref.read(activeSessionProvider).value;
    if (session == null) return;
    final now = ref.read(serverClockProvider).now();
    // Ask the server once when time runs out, so the status moves to the exam.
    if (session.status == SessionStatus.studying && !now.isBefore(session.endsAt) && !_refreshedAtZero) {
      _refreshedAtZero = true;
      unawaited(ref.read(activeSessionProvider.notifier).refresh().catchError((_) {}));
    }
    setState(() {});
  }

  Future<void> _finishEarly() async {
    setState(() => _finishing = true);
    try {
      await ref.read(activeSessionProvider.notifier).finishEarly();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _addPhoto(StudySession session) async {
    final bytes = await pickStudyPhoto(context);
    if (bytes == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await ref.read(studyApiProvider).addPhoto(session.id, bytes, mime: imageMime(bytes));
      await ref.read(activeSessionProvider.notifier).refresh();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto(StudySession session, String photoId) async {
    try {
      await ref.read(studyApiProvider).removePhoto(session.id, photoId);
      await ref.read(activeSessionProvider.notifier).refresh();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activeSessionProvider);
    return PageShell(
      title: 'Study session',
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => MessageBanner.error(e is ApiException ? e.message : 'Could not load your session.'),
        data: (session) => session == null ? _NoSession(onHome: () => context.go(Routes.home)) : _body(session),
      ),
    );
  }

  Widget _body(StudySession session) {
    final text = Theme.of(context).textTheme;
    final now = ref.read(serverClockProvider).now();
    final total = session.endsAt.difference(session.startedAt);
    final left = session.endsAt.difference(now);
    final studying = session.status == SessionStatus.studying && left > Duration.zero;
    final progress = studying ? 1 - left.inMilliseconds / total.inMilliseconds : 1.0;
    final canFinish = !now.isBefore(session.canFinishAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(session.subject, textAlign: TextAlign.center, style: text.headlineMedium),
        const SizedBox(height: 4),
        Text(
          session.topics,
          textAlign: TextAlign.center,
          style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
        ),
        const SizedBox(height: 24),
        Center(
          child: TimerRing(
            progress: progress,
            done: !studying,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  studying ? Icons.local_fire_department_rounded : Icons.emoji_events_rounded,
                  color: studying ? AppColors.coral : AppColors.sunshineDeep,
                  size: 32,
                ),
                Text(
                  studying ? _clock(left) : 'Done!',
                  style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1.1),
                ),
                Text(
                  studying ? 'left to focus' : 'Time for your exam',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (studying) ...[
          ClayCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const IconBadge(Icons.lock_rounded, size: 46),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    session.lockedApps.isEmpty
                        ? 'Stay focused. Put your phone face down and study!'
                        : '${session.lockedApps.length} apps are locked until you pass your exam.',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PlanCard(
            session: session,
            uploading: _uploading,
            onAdd: () => _addPhoto(session),
            onRemove: (id) => _removePhoto(session, id),
          ),
          const SizedBox(height: 16),
          Button3D(
            label: 'Ask the AI helper',
            icon: Icons.smart_toy_rounded,
            color: AppColors.sky,
            edgeColor: AppColors.skyDeep,
            onPressed: () => context.push(Routes.tutor),
          ),
          const SizedBox(height: 12),
          Button3D.secondary(
            label: canFinish
                ? 'I am done, take the exam'
                : 'Finish early in ${_clock(session.canFinishAt.difference(now))}',
            icon: Icons.flag_rounded,
            loading: _finishing,
            onPressed: canFinish ? _finishEarly : null,
          ),
        ] else ...[
          MessageBanner.success(
            'Great work! You studied ${session.studiedMinutes} minutes. '
            'Pass the exam (${session.exam.passMarks}/${session.exam.totalMarks}) to unlock your apps.',
          ),
          const SizedBox(height: 20),
          Button3D(
            label: 'Start my exam',
            icon: Icons.quiz_rounded,
            color: AppColors.sunshine,
            edgeColor: AppColors.sunshineDeep,
            foreground: AppColors.ink,
            onPressed: () => context.push(Routes.exam),
          ),
        ],
      ],
    );
  }

  static String _clock(Duration d) {
    final s = d.inSeconds.clamp(0, 360000);
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
  }
}

class _NoSession extends StatelessWidget {
  const _NoSession({required this.onHome});

  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const IconBadge(Icons.check_circle_rounded, size: 80, color: AppColors.mintDeep),
        const SizedBox(height: 16),
        Text('No session running', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 24),
        Button3D(label: 'Back home', onPressed: onHome),
      ],
    );
  }
}

/// The student's plan and photos of the material; photos can change until the timer ends.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.session, required this.uploading, required this.onAdd, required this.onRemove});

  final StudySession session;
  final bool uploading;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return ClayCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: AppColors.violet),
              SizedBox(width: 8),
              Text(
                'Your plan',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.ink),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            session.notes.isEmpty ? 'Add photos of your pages: your quiz will ask about them.' : session.notes,
            style: const TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600, height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final id in session.photoIds) ServerPhotoThumb(photoId: id, size: 72, onRemove: () => onRemove(id)),
              if (session.photoIds.length < maxStudyPhotos) AddPhotoTile(onTap: onAdd, size: 72, busy: uploading),
            ],
          ),
        ],
      ),
    );
  }
}
