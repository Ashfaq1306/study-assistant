import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// "Resend code" link that counts down until the server allows another code.
class ResendButton extends StatefulWidget {
  const ResendButton({super.key, required this.availableAt, required this.onResend, this.label = 'Send a new code'});

  final DateTime availableAt;

  /// Sends a new code; returns when the next one may be requested.
  final Future<DateTime?> Function() onResend;
  final String label;

  @override
  State<ResendButton> createState() => _ResendButtonState();
}

class _ResendButtonState extends State<ResendButton> {
  late DateTime _availableAt = widget.availableAt;
  Timer? _ticker;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  @override
  void didUpdateWidget(ResendButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.availableAt != widget.availableAt) {
      _availableAt = widget.availableAt;
      _tick();
    }
  }

  void _tick() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 0) t.cancel();
      setState(() {});
    });
  }

  int get _secondsLeft => _availableAt.difference(DateTime.now()).inSeconds + 1;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      final next = await widget.onResend();
      if (next != null && mounted) {
        _availableAt = next;
        _tick();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wait = _secondsLeft;
    if (wait > 0) {
      return Text(
        'You can ask for a new code in ${wait}s',
        style: const TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w700),
      );
    }
    return TextButton.icon(
      onPressed: _sending ? null : _resend,
      icon: _sending
          ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh_rounded),
      label: Text(widget.label),
    );
  }
}
