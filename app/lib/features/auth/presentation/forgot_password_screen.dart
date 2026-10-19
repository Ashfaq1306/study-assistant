import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/otp_input.dart';
import '../../../core/widgets/page_shell.dart';
import '../../../core/widgets/password_meter.dart';
import '../../../core/widgets/resend_button.dart';
import '../application/auth_controller.dart';

/// Ask for a code, then set a new password with it. Success signs you in.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  static const _resendCooldown = Duration(seconds: 61);

  final _requestForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();

  bool _codeSent = false;
  bool _loading = false;
  DateTime _resendAt = DateTime.now();
  ApiException? _error;

  @override
  void dispose() {
    for (final c in [_identifier, _code, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestCode() async {
    if (!_requestForm.currentState!.validate()) return;
    await _run(() async {
      await ref.read(authControllerProvider.notifier).forgotPassword(_identifier.text);
      setState(() {
        _codeSent = true;
        _resendAt = DateTime.now().add(_resendCooldown);
      });
    });
  }

  Future<void> _reset() async {
    if (!_resetForm.currentState!.validate()) return;
    if (Validators.otp(_code.text) != null) {
      setState(() => _error = const ApiException(code: 'OTP_INVALID', message: 'Enter all 6 digits.'));
      return;
    }
    // On success the router takes over and opens the app.
    await _run(
      () => ref.read(authControllerProvider.notifier).resetPassword(_identifier.text, _code.text, _password.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PageShell(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _codeSent ? _resetStep(text) : _requestStep(text),
      ),
    );
  }

  Widget _requestStep(TextTheme text) {
    return Form(
      key: _requestForm,
      child: Column(
        key: const ValueKey('request'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: IconBadge(Icons.key_rounded, size: 76, color: AppColors.sunshineDeep)),
          const SizedBox(height: 16),
          Text('Forgot your password?', textAlign: TextAlign.center, style: text.headlineMedium),
          const SizedBox(height: 6),
          Text(
            "No worries! Enter your email or mobile number and we'll send a code.",
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 28),
          AppTextField(
            label: 'Email or mobile number',
            controller: _identifier,
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            validator: Validators.identifier,
            onSubmitted: (_) => _requestCode(),
          ),
          if (_error != null) ...[const SizedBox(height: 16), MessageBanner.error(_error!.message)],
          const SizedBox(height: 28),
          Button3D(label: 'Send code', loading: _loading, onPressed: _requestCode),
        ],
      ),
    );
  }

  Widget _resetStep(TextTheme text) {
    return Form(
      key: _resetForm,
      child: Column(
        key: const ValueKey('reset'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: IconBadge(Icons.mark_email_read_rounded, size: 76, color: AppColors.sunshineDeep)),
          const SizedBox(height: 16),
          Text('Enter your code', textAlign: TextAlign.center, style: text.headlineMedium),
          const SizedBox(height: 6),
          Text(
            'If an account matches ${_identifier.text.trim()}, a code is on its way.',
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 24),
          OtpInput(controller: _code, hasError: _error != null),
          const SizedBox(height: 22),
          AppTextField(
            label: 'New password',
            controller: _password,
            icon: Icons.lock_reset_rounded,
            obscure: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            validator: Validators.password,
            errorText: _error?.fieldErrors['newPassword'],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _reset(),
          ),
          const SizedBox(height: 10),
          PasswordMeter(password: _password.text),
          if (_error != null && _error!.fieldErrors.isEmpty) ...[
            const SizedBox(height: 16),
            MessageBanner.error(_error!.message),
          ],
          const SizedBox(height: 28),
          Button3D(label: 'Save & sign in', loading: _loading, onPressed: _reset),
          const SizedBox(height: 12),
          Center(
            child: ResendButton(
              availableAt: _resendAt,
              onResend: () async {
                try {
                  await ref.read(authControllerProvider.notifier).forgotPassword(_identifier.text);
                  return DateTime.now().add(_resendCooldown);
                } on ApiException catch (e) {
                  if (mounted) setState(() => _error = e);
                  return null;
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
