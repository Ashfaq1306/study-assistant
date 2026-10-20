import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../domain/calendar_event.dart';

final _day = DateFormat('EEE, d MMM');
final _time = DateFormat('h:mm a');

String formatDay(DateTime t) => _day.format(t);
String formatTime(DateTime t) => _time.format(t);

/// "Today", "Tomorrow", "In 5 days" or the date, for countdowns.
String relativeDay(DateTime t, DateTime now) {
  final days = DateTime(t.year, t.month, t.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days > 1 && days < 60) return 'In $days days';
  return formatDay(t);
}

/// When an occurrence happens, in words: "All day", "8:00 AM – 8:45 AM", "20 Dec – 31 Dec".
String occurrenceTime(Occurrence o) {
  final e = o.event;
  final end = o.end;
  final multiDay = end != null && DateUtils.dateOnly(end) != DateUtils.dateOnly(o.start);
  if (multiDay) return '${formatDay(o.start)} – ${formatDay(end)}';
  if (e.allDay) return 'All day';
  return end == null ? formatTime(o.start) : '${formatTime(o.start)} – ${formatTime(end)}';
}

/// A calendar item: kind badge, title, when and where.
class OccurrenceTile extends StatelessWidget {
  const OccurrenceTile({super.key, required this.occurrence, this.onTap, this.trailing, this.showDate = false});

  final Occurrence occurrence;

  /// Lists that span many days (review, coming up) also show the date.
  final bool showDate;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final e = occurrence.event;
    final when = occurrenceTime(occurrence);
    final multiDay = when.contains('–') && when.contains(',');
    final details = [
      if (showDate && !multiDay) '${formatDay(occurrence.start)}${e.weekly ? ' (weekly)' : ''}',
      when,
      if (e.subject.isNotEmpty && e.subject != e.title) e.subject,
      if (e.location.isNotEmpty) e.location,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClayCard(
        glow: e.kind.color,
        padding: const EdgeInsets.all(14),
        radius: 22,
        onTap: onTap,
        child: Row(
          children: [
            IconBadge(e.kind.icon, size: 44, color: e.kind.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: AppColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    details,
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (e.weekly)
              Icon(Icons.repeat_rounded, size: 18, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// A month of days with coloured dots for what happens on each.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.month,
    required this.selected,
    required this.occurrences,
    required this.onSelect,
  });

  /// Any day in the month to show.
  final DateTime month;
  final DateTime selected;
  final List<Occurrence> occurrences;
  final ValueChanged<DateTime> onSelect;

  static const _weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final lead = first.weekday % 7; // Sunday first
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final today = DateUtils.dateOnly(DateTime.now());
    final cells = ((lead + days) / 7).ceil() * 7;

    return Column(
      children: [
        Row(
          children: [
            for (final d in _weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkFaint),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < cells ~/ 7; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: () {
                    final index = row * 7 + col - lead;
                    if (index < 0 || index >= days) return const SizedBox(height: 52);
                    final day = DateTime(month.year, month.month, index + 1);
                    final kinds = {
                      for (final o in occurrences)
                        if (o.onDay(day)) o.event.kind,
                    }.toList()..sort((a, b) => a.index.compareTo(b.index));
                    return _DayCell(
                      day: day,
                      kinds: kinds,
                      isToday: day == today,
                      isSelected: day == DateUtils.dateOnly(selected),
                      onTap: () => onSelect(day),
                    );
                  }(),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.kinds,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final List<CalendarKind> kinds;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${formatDay(day)}${kinds.isEmpty ? '' : ', ${kinds.map((k) => k.label).join(', ')}'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 52,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.hero : (isToday ? AppColors.violetSoft : Colors.transparent),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  fontWeight: isToday || isSelected ? FontWeight.w900 : FontWeight.w700,
                  color: isSelected ? Colors.white : AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final k in kinds.take(3))
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: isSelected ? Colors.white : k.color),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
