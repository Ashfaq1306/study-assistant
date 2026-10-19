import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../../auth/application/auth_controller.dart';
import 'pairing_qr_card.dart';

/// The gate for students under 15: nothing else opens until a parent scans
/// this QR. Checks every few seconds, and the router moves on once linked.
class LinkParentScreen extends ConsumerStatefulWidget {
  const LinkParentScreen({super.key});

  @override
  ConsumerState<LinkParentScreen> createState() => _LinkParentScreenState();
}

class _LinkParentScreenState extends ConsumerState<LinkParentScreen> {
  static const _pollEvery = Duration(seconds: 4);
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(_pollEvery, (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      await ref.read(authControllerProvider.notifier).refreshUser();
    } on ApiException {
      // Offline for a moment: try again on the next tick.
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final auth = ref.watch(authControllerProvider);
    final name = auth is AuthSignedIn ? auth.user.firstName : 'there';

    return PageShell(
      showBack: false,
      actions: [
        TextButton(onPressed: () => ref.read(authControllerProvider.notifier).logout(), child: const Text('Sign out')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: IconBadge(Icons.family_restroom_rounded, size: 76, color: AppColors.mintDeep)),
          const SizedBox(height: 14),
          Text('One last step, $name!', textAlign: TextAlign.center, style: text.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Students under ${AppConfig.parentalControlAge} study with a parent linked. '
            'Ask your parent to scan this code with their phone.',
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 24),
          const PairingQrCard(),
          const SizedBox(height: 24),
          const _HowTo(),
          const SizedBox(height: 20),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2.4)),
              SizedBox(width: 10),
              Text(
                'Waiting for your parent…',
                style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HowTo extends StatelessWidget {
  const _HowTo();

  static const _steps = [
    (Icons.install_mobile_rounded, 'Your parent installs ${AppConfig.appName}.'),
    (Icons.person_add_alt_1_rounded, 'They create an account and choose "I\'m a parent".'),
    (Icons.qr_code_scanner_rounded, 'They tap "Add a child" and scan this code.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (i, (icon, step)) in _steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                IconBadge(icon, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${i + 1}. $step',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
