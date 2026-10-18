import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/otp_input.dart';
import '../../../core/widgets/page_shell.dart';
import '../../../core/widgets/resend_button.dart';
import '../application/auth_controller.dart';
import '../domain/otp.dart';

/// Enter the 6-digit code that opens a new account. On success the router
/// takes the user on (to home, or to linking a parent if under 15).
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key, required this.pending});

  final PendingVerification? pending;

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _code = TextEditingController();
  late OtpChannel _channel = widget.pending?.channel ?? OtpChannel.email;
  late OtpDelivery? _delivery = widget.pending?.delivery;

  /// Fixed once, so rebuilds do not restart the resend countdown.
  late DateTime _resendAt = _delivery?.resendAvailableAt ?? DateTime.now();
  bool _loading = false;
  ApiException? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return; // Auto-submit and the button can fire together.
    final pending = widget.pending!;
    if (_code.text.length != 6) {
      setState(() => _error = const ApiException(code: 'OTP_INVALID', message: 'Enter all 6 digits.'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).verify(pending.userId, _code.text);
    } on ApiException catch (e) {
      if (!mounted) return;
      _code.clear();
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<DateTime?> _resend({OtpChannel? channel}) async {
    try {
      final delivery = await ref
          .read(authControllerProvider.notifier)
          .resendCode(widget.pending!.userId, channel: channel);
      if (!mounted) return null;
      setState(() {
        _delivery = delivery;
        _resendAt = delivery.resendAvailableAt;
        _channel = delivery.channel;
        _error = null;
      });
      showSnack(context, 'New code sent to ${delivery.destination}');
      return delivery.resendAvailableAt;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.pending;
    if (pending == null) return _Expired(onRestart: () => context.go(Routes.login));

    final text = Theme.of(context).textTheme;
    final where = _delivery?.destination ?? (_channel == OtpChannel.email ? 'your email' : 'your phone');
    final other = _channel == OtpChannel.email ? OtpChannel.sms : OtpChannel.email;

    return PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: EmojiBadge(_channel == OtpChannel.email ? '📬' : '💬', size: 80, color: AppColors.sunshineSoft),
          ),
          const SizedBox(height: 16),
          Text(
            'Check your ${_channel == OtpChannel.email ? 'inbox' : 'messages'}',
            textAlign: TextAlign.center,
            style: text.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              text: 'We sent a 6-digit code to ',
              children: [
                TextSpan(
                  text: where,
                  style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink),
                ),
                const TextSpan(text: '. It works for 10 minutes.'),
              ],
            ),
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 28),
          OtpInput(controller: _code, hasError: _error != null, onCompleted: (_) => _submit()),
          if (_error != null) ...[const SizedBox(height: 16), MessageBanner.error(_attemptsMessage(_error!))],
          const SizedBox(height: 28),
          Button3D(label: 'Open my account', loading: _loading, onPressed: _submit),
          const SizedBox(height: 16),
          Center(
            child: ResendButton(availableAt: _resendAt, onResend: _resend),
          ),
          if (pending.otherChannelAvailable)
            Center(
              child: TextButton(
                onPressed: () => _resend(channel: other),
                child: Text('Send it by ${other.label} instead'),
              ),
            ),
        ],
      ),
    );
  }

  static String _attemptsMessage(ApiException e) {
    final left = e.details['attemptsLeft'];
    return left is num ? '${e.message} ${left.toInt()} tries left.' : e.message;
  }
}

class _Expired extends StatelessWidget {
  const _Expired({required this.onRestart});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return PageShell(
      child: Column(
        children: [
          const EmojiBadge('⌛', size: 80),
          const SizedBox(height: 16),
          Text('This page has expired', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Sign in again and we will send you a fresh code.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Button3D(label: 'Go to sign in', onPressed: onRestart),
        ],
      ),
    );
  }
}
