import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Shown only when a development server returns the code, so the app can be
/// tested on a phone without real email or SMS. Tap to fill the code in.
class DevCodeBanner extends StatelessWidget {
  const DevCodeBanner({super.key, required this.code, required this.onUse});

  final String code;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.sunshineSoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onUse,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.developer_mode_rounded, color: AppColors.sunshineDeep),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Test mode: your code is $code. Tap to fill it in.',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
