import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/choice_controls.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../../../core/widgets/wizard.dart';
import '../application/calendar_controller.dart';
import '../domain/calendar_event.dart';
import 'calendar_widgets.dart';

/// Reminder choices, in minutes before the start.
const _reminderOptions = [
  (0, 'At the time'),
  (15, '15 min'),
  (60, '1 hour'),
  (1440, '1 day'),
  (2880, '2 days'),
  (10080, '1 week'),
];

/// Add or change one calendar item.
class EventEditorScreen extends ConsumerStatefulWidget {
  const EventEditorScreen({super.key, required this.event});

  final CalendarEvent event;

  @override
  ConsumerState<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends ConsumerState<EventEditorScreen> {
  late CalendarEvent _e = widget.event.id == null
      ? widget.event.copyWith(reminders: widget.event.kind.defaultReminders)
      : widget.event;
  late final _title = TextEditingController(text: _e.title);
  late final _subject = TextEditingController(text: _e.subject);
  late final _location = TextEditingController(text: _e.location);
  late final _notes = TextEditingController(text: _e.notes);
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.event.id == null;

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _setKind(CalendarKind kind) => setState(() {
    _e = _e.copyWith(kind: kind, reminders: kind.defaultReminders, weekly: kind == CalendarKind.classSession);
  });

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _e.startsAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    final start = DateTime(date.year, date.month, date.day, _e.startsAt.hour, _e.startsAt.minute);
    final length = _e.endsAt?.difference(_e.startsAt);
    setState(() => _e = _e.copyWith(startsAt: start, endsAt: () => length == null ? null : start.add(length)));
  }

  Future<void> _pickTime({required bool end}) async {
    final base = end ? (_e.endsAt ?? _e.startsAt.add(const Duration(hours: 1))) : _e.startsAt;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (time == null) return;
    final day = _e.startsAt;
    final picked = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    setState(() {
      if (end) {
        _e = _e.copyWith(endsAt: () => picked.isAfter(_e.startsAt) ? picked : null);
      } else {
        final length = _e.endsAt?.difference(_e.startsAt);
        _e = _e.copyWith(startsAt: picked, endsAt: () => length == null ? null : picked.add(length));
      }
    });
  }

  void _toggleReminder(int minutes) => setState(() {
    final next = {..._e.reminders};
    next.contains(minutes) ? next.remove(minutes) : next.add(minutes);
    _e = _e.copyWith(reminders: next.toList()..sort((a, b) => b.compareTo(a)));
  });

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Give it a name, e.g. "Physics midterm".');
      return;
    }
    final allDayStart = DateTime(_e.startsAt.year, _e.startsAt.month, _e.startsAt.day);
    final event = _e.copyWith(
      title: _title.text,
      subject: _subject.text,
      location: _location.text,
      notes: _notes.text,
      startsAt: _e.allDay ? allDayStart : null,
      endsAt: _e.allDay ? () => null : null,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(calendarProvider.notifier).save(event);
      if (mounted) context.pop();
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
        title: const Text('Remove from calendar?'),
        content: Text(
          _e.weekly ? 'Every week of "${_e.title}" and its reminders.' : '"${_e.title}" and its reminders.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (!(ok ?? false) || !mounted) return;
    try {
      await ref.read(calendarProvider.notifier).delete(widget.event);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: _isNew ? 'Add to calendar' : 'Edit',
      actions: [
        if (!_isNew)
          IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.delete_outline_rounded, color: AppColors.coralDeep),
            onPressed: _delete,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('What is it?'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final k in CalendarKind.values)
                ChoicePill(
                  label: k.label,
                  icon: k.icon,
                  color: k.color,
                  selected: _e.kind == k,
                  onTap: () => _setKind(k),
                ),
            ],
          ),
          const SizedBox(height: 20),
          AppTextField(
            label: 'Name',
            controller: _title,
            hint: switch (_e.kind) {
              CalendarKind.exam => 'e.g. Physics midterm',
              CalendarKind.classSession => 'e.g. Chemistry',
              CalendarKind.assignment => 'e.g. Science project',
              CalendarKind.holiday => 'e.g. Winter vacation',
              CalendarKind.event => 'e.g. Results day',
            },
            icon: _e.kind.icon,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Subject (optional)',
            controller: _subject,
            icon: Icons.menu_book_rounded,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 20),
          const FieldLabel('When'),
          ClayCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.event_rounded, color: AppColors.violet),
                  title: Text(formatDay(_e.startsAt), style: const TextStyle(fontWeight: FontWeight.w800)),
                  trailing: const Icon(Icons.edit_calendar_rounded),
                  onTap: _pickDate,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _e.allDay,
                  onChanged: (v) => setState(() => _e = _e.copyWith(allDay: v)),
                  title: const Text('All day', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                if (!_e.allDay) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.schedule_rounded, color: AppColors.violet),
                    title: Text(
                      'Starts ${formatTime(_e.startsAt)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () => _pickTime(end: false),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.timelapse_rounded, color: AppColors.inkSoft),
                    title: Text(
                      _e.endsAt == null ? 'Add an end time' : 'Ends ${formatTime(_e.endsAt!)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () => _pickTime(end: true),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _e.weekly,
                  onChanged: (v) => setState(() => _e = _e.copyWith(weekly: v)),
                  title: const Text('Repeats every week', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('For classes in your timetable'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const FieldLabel('Remind me'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (minutes, label) in _reminderOptions)
                ChoicePill(
                  label: label,
                  icon: Icons.notifications_active_rounded,
                  selected: _e.reminders.contains(minutes),
                  onTap: () => _toggleReminder(minutes),
                ),
            ],
          ),
          const SizedBox(height: 20),
          AppTextField(label: 'Place (optional)', controller: _location, icon: Icons.place_rounded),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Notes (optional)',
            controller: _notes,
            icon: Icons.notes_rounded,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.newline,
          ),
          if (_error != null) ...[const SizedBox(height: 16), MessageBanner.error(_error!)],
          const SizedBox(height: 24),
          Button3D(
            label: _isNew ? 'Add to calendar' : 'Save changes',
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
