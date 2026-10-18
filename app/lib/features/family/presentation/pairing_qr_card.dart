import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../data/family_api.dart';

/// Shows a fresh pairing QR (plus the code to type) and replaces it
/// automatically when it expires.
class PairingQrCard extends ConsumerStatefulWidget {
  const PairingQrCard({super.key});

  @override
  ConsumerState<PairingQrCard> createState() => _PairingQrCardState();
}

class _PairingQrCardState extends ConsumerState<PairingQrCard> {
  PairingCode? _code;
  ApiException? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _ticker?.cancel();
    setState(() => _error = null);
    try {
      final code = await ref.read(familyApiProvider).createPairingCode();
      if (!mounted) return;
      setState(() => _code = code);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_remaining <= Duration.zero) {
          _load();
        } else {
          setState(() {});
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Duration get _remaining => _code == null ? Duration.zero : _code!.expiresAt.difference(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final code = _code;
    return ClayCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (_error != null) ...[
            MessageBanner.error(_error!.message),
            const SizedBox(height: 16),
            Button3D.secondary(label: 'Try again', onPressed: _load),
          ] else if (code == null)
            const SizedBox.square(dimension: 220, child: Center(child: CircularProgressIndicator()))
          else ...[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: QrImageView(
                key: ValueKey(code.qrPayload),
                data: code.qrPayload,
                size: 220,
                padding: EdgeInsets.zero,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                semanticsLabel: 'QR code for your parent to scan',
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.violetDeep),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Or type this code',
              style: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            SelectableText(
              code.code,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 4, color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'New code in ${_format(_remaining)}',
              style: const TextStyle(color: AppColors.inkFaint, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  static String _format(Duration d) {
    final s = d.inSeconds.clamp(0, 3600);
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
