import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../../../core/widgets/pencil_3d.dart';
import '../../study/presentation/widgets/study_photos.dart';
import '../application/calendar_controller.dart';
import '../domain/calendar_event.dart';
import 'calendar_widgets.dart';

/// The AI reads a school or university calendar, exam routine or timetable;
/// the student ticks what to keep, and every item gets reminders.
class ImportCalendarScreen extends ConsumerStatefulWidget {
  const ImportCalendarScreen({super.key});

  @override
  ConsumerState<ImportCalendarScreen> createState() => _ImportCalendarScreenState();
}

class _ImportCalendarScreenState extends ConsumerState<ImportCalendarScreen> {
  final _text = TextEditingController();
  bool _reading = false;
  bool _saving = false;
  String? _error;
  List<CalendarEvent>? _found;
  final Set<int> _keep = {};

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _read({Uint8List? file, String? mime}) async {
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final found = await ref.read(calendarApiProvider).read(text: _text.text, file: file, mime: mime);
      if (!mounted) return;
      setState(() {
        _found = found;
        _keep
          ..clear()
          ..addAll(List.generate(found.length, (i) => i));
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _pickPdf() async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
    final bytes = await picked?.readAsBytes();
    if (bytes == null || !mounted) return;
    if (bytes.length > 8000000) {
      setState(() => _error = 'That PDF is over 8 MB. Try a smaller file or a photo of the page.');
      return;
    }
    await _read(file: bytes, mime: 'application/pdf');
  }

  Future<void> _pickPhoto() async {
    final bytes = await pickStudyPhoto(context);
    if (bytes != null) await _read(file: bytes, mime: imageMime(bytes));
  }

  Future<void> _save() async {
    final chosen = [
      for (final (i, e) in _found!.indexed)
        if (_keep.contains(i)) e,
    ];
    if (chosen.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(calendarProvider.notifier).saveAll(chosen);
      if (!mounted) return;
      showSnack(context, 'Added ${chosen.length} items with reminders.');
      context.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_reading) return const _Reading();
    final found = _found;
    return PageShell(title: 'Import calendar', child: found == null ? _choose() : _review(found));
  }

  Widget _choose() {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: IconBadge(Icons.auto_awesome_rounded, size: 80, color: AppColors.violet)),
        const SizedBox(height: 14),
        Text('Your academic calendar', textAlign: TextAlign.center, style: text.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Add the calendar, exam routine or class timetable from your school or university. '
          'The AI finds every exam, class, deadline and holiday, and you choose what to keep.',
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        const SizedBox(height: 22),
        _Option(
          icon: Icons.picture_as_pdf_rounded,
          color: AppColors.coralDeep,
          title: 'Upload a PDF',
          body: 'Up to 8 MB',
          onTap: _pickPdf,
        ),
        _Option(
          icon: Icons.photo_camera_rounded,
          color: AppColors.violet,
          title: 'Take or choose a photo',
          body: 'Of the notice board, routine or printed calendar',
          onTap: _pickPhoto,
        ),
        const SizedBox(height: 10),
        AppTextField(
          label: 'Or paste the text',
          controller: _text,
          hint: 'e.g. 15 Nov Bangla 1st paper 10:00-1:00 …',
          icon: Icons.content_paste_rounded,
          maxLines: 6,
          textInputAction: TextInputAction.newline,
        ),
        const SizedBox(height: 12),
        Button3D.secondary(
          label: 'Read the text',
          icon: Icons.auto_awesome_rounded,
          onPressed: () =>
              _text.text.trim().isEmpty ? setState(() => _error = 'Paste the calendar text first.') : _read(),
        ),
        if (_error != null) ...[const SizedBox(height: 16), MessageBanner.error(_error!)],
        const SizedBox(height: 16),
        const MessageBanner.info(
          'Bangla and English both work. Check the dates before saving: the AI can make mistakes.',
        ),
      ],
    );
  }

  Widget _review(List<CalendarEvent> found) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Found ${found.length} items', style: text.headlineSmall),
        const SizedBox(height: 4),
        Text('Untick anything you don’t want. Reminders are added for each one.', style: text.bodyMedium),
        const SizedBox(height: 14),
        for (final (i, e) in found.indexed)
          OccurrenceTile(
            occurrence: Occurrence(e, e.startsAt, e.endsAt),
            showDate: true,
            onTap: () => setState(() => _keep.contains(i) ? _keep.remove(i) : _keep.add(i)),
            trailing: Checkbox(
              value: _keep.contains(i),
              onChanged: (v) => setState(() => v! ? _keep.add(i) : _keep.remove(i)),
            ),
          ),
        if (_error != null) ...[const SizedBox(height: 8), MessageBanner.error(_error!)],
        const SizedBox(height: 16),
        Button3D(
          label: 'Add ${_keep.length} to my calendar',
          icon: Icons.event_available_rounded,
          loading: _saving,
          onPressed: _keep.isEmpty ? null : _save,
        ),
        const SizedBox(height: 12),
        Button3D.secondary(label: 'Start over', onPressed: () => setState(() => _found = null)),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClayCard(
        glow: color,
        padding: const EdgeInsets.all(16),
        onTap: onTap,
        child: Row(
          children: [
            IconBadge(icon, size: 48, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.ink),
                  ),
                  Text(
                    body,
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading();

  @override
  Widget build(BuildContext context) {
    return PageShell(
      showBack: false,
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Pencil3D(size: 220, interactive: false),
          Text('Reading your calendar…', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Finding exams, classes, deadlines and holidays.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          const SizedBox(width: 180, child: LinearProgressIndicator(minHeight: 8)),
        ],
      ),
    );
  }
}
