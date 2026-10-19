import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../../auth/application/auth_controller.dart';
import '../application/family_providers.dart';

/// A parent scans the QR on their child's phone, or types its code.
class AddChildScreen extends ConsumerStatefulWidget {
  const AddChildScreen({super.key});

  static const qrPrefix = 'studyassistant://pair?code=';

  @override
  ConsumerState<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends ConsumerState<AddChildScreen> {
  final _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final _manual = TextEditingController();
  bool _linking = false;
  ApiException? _error;

  @override
  void dispose() {
    _scanner.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || !value.startsWith(AddChildScreen.qrPrefix) || _linking) return;
    _link(value);
  }

  Future<void> _link(String code) async {
    setState(() {
      _linking = true;
      _error = null;
    });
    try {
      final link = await ref.read(familyApiProvider).link(code);
      await HapticFeedback.mediumImpact();
      ref.invalidate(familyLinksProvider);
      await ref.read(authControllerProvider.notifier).refreshUser();
      if (!mounted) return;
      showSnack(context, '${link.personName} is now linked!');
      context.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PageShell(
      title: 'Add a child',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "On your child's phone, open Study Assistant. Point your camera at the QR code it shows.",
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 20),
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _scanner,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) => _CameraProblem(error),
                  ),
                  // The aiming frame only makes sense while the camera runs;
                  // otherwise it would cut through the "camera is off" message.
                  ValueListenableBuilder(
                    valueListenable: _scanner,
                    builder: (context, state, _) => !state.isRunning
                        ? const SizedBox.shrink()
                        : IgnorePointer(
                            child: Center(
                              child: FractionallySizedBox(
                                widthFactor: 0.68,
                                heightFactor: 0.68,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(color: Colors.white, width: 4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                  if (_linking)
                    const ColoredBox(
                      color: Color(0x88000000),
                      child: Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[const SizedBox(height: 16), MessageBanner.error(_error!.message)],
          const SizedBox(height: 24),
          AppTextField(
            label: 'Or type the code',
            controller: _manual,
            hint: 'ABCD-EFGH',
            icon: Icons.keyboard_rounded,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
              LengthLimitingTextInputFormatter(11),
            ],
            onSubmitted: (_) => _linkManual(),
          ),
          const SizedBox(height: 18),
          Button3D(
            label: 'Link my child',
            icon: Icons.link_rounded,
            color: AppColors.mint,
            edgeColor: AppColors.mintDeep,
            loading: _linking,
            onPressed: _linkManual,
          ),
        ],
      ),
    );
  }

  void _linkManual() {
    final code = _manual.text.trim();
    if (code.isEmpty) {
      setState(() => _error = const ApiException(code: 'EMPTY', message: 'Type the 8-character code first.'));
      return;
    }
    _link(code);
  }
}

class _CameraProblem extends StatelessWidget {
  const _CameraProblem(this.error);

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final message = error.errorCode == MobileScannerErrorCode.permissionDenied
        ? 'Camera access is off. Allow it in Settings, or type the code below.'
        : "The camera couldn't start. Type the code below instead.";
    return ColoredBox(
      color: AppColors.violetSoft,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IconBadge(Icons.no_photography_rounded, size: 64),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
