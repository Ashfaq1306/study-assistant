import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/validators.dart';

/// Three-segment strength bar shown under new-password fields.
class PasswordMeter extends StatelessWidget {
  const PasswordMeter({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final strength = passwordStrength(password);
    final (label, color) = switch (strength) {
      0 => ('Use 8+ characters with letters and numbers', AppColors.inkFaint),
      1 => ('Weak', AppColors.coral),
      2 => ('Good', AppColors.sunshineDeep),
      _ => ('Strong 💪', AppColors.mintDeep),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 1; i <= 3; i++) ...[
              if (i > 1) const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 6,
                  decoration: BoxDecoration(
                    color: i <= strength ? color : AppColors.line,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ],
    );
  }
}
