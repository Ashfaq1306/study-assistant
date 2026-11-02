import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/button_3d.dart';
import '../../core/widgets/clay_card.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/page_shell.dart';
import '../auth/application/auth_controller.dart';

/// Deletes the account for good, after the password is confirmed (Google Play requires
/// account deletion inside the app). The server refuses while a lock is running.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  var _confirmed = false;
  var _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_password.text.isEmpty) {
      setState(() => _error = const ApiException(code: 'VALIDATION_FAILED', message: 'Enter your password.'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).delete('/v1/me', data: {'password': _password.text});
      // The account is gone: forget it on this phone (the route guard shows the welcome screen).
      await ref.read(authControllerProvider.notifier).forgetSession();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PageShell(
      title: 'Delete account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: IconBadge(Icons.delete_forever_rounded, size: 80, color: AppColors.coralDeep)),
          const SizedBox(height: 16),
          Text('Delete your account?', textAlign: TextAlign.center, style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'This cannot be undone. We delete your account and everything in it right away:',
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 16),
          ClayCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in const [
                  'Your profile, email and phone number',
                  'Study sessions, study time, photos and notes',
                  'Exams, results and AI helper chats',
                  'Your calendar and reminders',
                  'Family links and locks set by or for you',
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.remove_circle_outline_rounded, size: 20, color: AppColors.coralDeep),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(line, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[MessageBanner.error(_error!.message), const SizedBox(height: 12)],
          AppTextField(
            label: 'Your password',
            controller: _password,
            icon: Icons.lock_rounded,
            obscure: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            errorText: _error?.fieldErrors['password'],
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('I understand that this deletes everything for good.'),
          ),
          const SizedBox(height: 12),
          Button3D(
            label: 'Delete my account',
            icon: Icons.delete_forever_rounded,
            color: AppColors.coralDeep,
            loading: _busy,
            onPressed: _confirmed && !_busy ? _delete : null,
          ),
          const SizedBox(height: 12),
          Button3D.secondary(label: 'Keep my account', onPressed: () => Navigator.of(context).maybePop()),
        ],
      ),
    );
  }
}
