import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Six friendly boxes over one hidden field, so paste and SMS autofill
/// (`AutofillHints.oneTimeCode`) work like a normal text field.
class OtpInput extends StatefulWidget {
  const OtpInput({super.key, required this.controller, this.onCompleted, this.hasError = false, this.length = 6});

  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;
  final bool hasError;
  final int length;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    final text = widget.controller.text;
    if (text.length == widget.length) widget.onCompleted?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return Semantics(
      label: 'Verification code, ${widget.length} digits',
      textField: true,
      child: GestureDetector(
        onTap: () => _focus.requestFocus(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Invisible but real: receives typing, paste and autofill.
            Opacity(
              opacity: 0,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: widget.length,
                showCursor: false,
                enableInteractiveSelection: false,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(counterText: '', border: InputBorder.none),
              ),
            ),
            IgnorePointer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < widget.length; i++)
                    _Box(
                      digit: i < text.length ? text[i] : '',
                      active: _focus.hasFocus && i == text.length.clamp(0, widget.length - 1),
                      error: widget.hasError,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.digit, required this.active, required this.error});

  final String digit;
  final bool active;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final accent = error ? AppColors.coral : AppColors.violet;
    final filled = digit.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 48,
      height: 60,
      alignment: Alignment.center,
      transform: Matrix4.translationValues(0, filled ? -3 : 0, 0),
      decoration: BoxDecoration(
        color: filled ? accent.withValues(alpha: 0.08) : AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: active || error ? accent : AppColors.line, width: active ? 2.4 : 1.6),
        boxShadow: [
          BoxShadow(
            color: (filled ? accent : AppColors.violet).withValues(alpha: filled ? 0.22 : 0.06),
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Text(
        digit,
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: error ? AppColors.coralDeep : AppColors.ink),
      ),
    );
  }
}
