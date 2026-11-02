import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';

/// What a report is about (matches the API).
enum ReportKind {
  tutor('TUTOR'),
  exam('EXAM'),
  calendar('CALENDAR');

  const ReportKind(this.api);
  final String api;
}

/// A small "Report" link under AI-written content. Google Play asks apps with AI content
/// to let people report anything wrong or inappropriate.
class ReportLink extends ConsumerWidget {
  const ReportLink({super.key, required this.kind, required this.content, this.refId});

  final ReportKind kind;
  final String content;
  final String? refId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.inkSoft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(48, 36),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: () => showReportSheet(context, ref, kind: kind, content: content, refId: refId),
      icon: const Icon(Icons.flag_outlined, size: 18),
      label: const Text('Report', style: TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

Future<void> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required ReportKind kind,
  required String content,
  String? refId,
}) async {
  const reasons = ['It is wrong', 'It is not suitable for students', 'Something else'];
  String? reason = reasons.first;
  final details = TextEditingController();
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setState) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Report this', style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'The AI can make mistakes. Tell us what is wrong and we will look at it.',
              style: TextStyle(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: reason,
              onChanged: (v) => setState(() => reason = v),
              child: Column(
                children: [
                  for (final r in reasons)
                    RadioListTile<String>(value: r, title: Text(r), contentPadding: EdgeInsets.zero),
                ],
              ),
            ),
            TextField(
              controller: details,
              maxLength: 300,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(hintText: 'More details (optional)'),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: () => Navigator.pop(sheetContext, true), child: const Text('Send report')),
          ],
        ),
      ),
    ),
  );
  if (sent != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(apiClientProvider)
        .post(
          '/v1/reports',
          data: {
            'kind': kind.api,
            'content': content.length > 4000 ? content.substring(0, 4000) : content,
            'reason': [reason, details.text.trim()].where((s) => s != null && s.isNotEmpty).join(': '),
            'refId': ?refId,
          },
        );
    messenger.showSnackBar(const SnackBar(content: Text('Thanks! We will review it.')));
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } finally {
    details.dispose();
  }
}
