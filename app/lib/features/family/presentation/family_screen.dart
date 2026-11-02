import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../../auth/application/auth_controller.dart';
import '../application/family_providers.dart';
import '../data/family_api.dart';
import 'pairing_qr_card.dart';

/// A student's linked parents, and a QR to add another. Refreshes while
/// open, so a parent who just scanned appears without leaving the screen.
class FamilyScreen extends ConsumerStatefulWidget {
  const FamilyScreen({super.key});

  @override
  ConsumerState<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends ConsumerState<FamilyScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => ref.invalidate(familyLinksProvider));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final links = ref.watch(familyLinksProvider);
    final auth = ref.watch(authControllerProvider);
    final mustKeepOne = auth is AuthSignedIn && auth.user.parentalControlRequired;
    final text = Theme.of(context).textTheme;

    return PageShell(
      title: 'Family',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Linked parents', style: text.titleLarge),
          const SizedBox(height: 12),
          links.when(
            loading: () => const Center(
              child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
            ),
            error: (e, _) => MessageBanner.error(e is ApiException ? e.message : 'Could not load your family.'),
            data: (items) => items.isEmpty
                ? const MessageBanner.info(
                    'No parent linked yet. Parental control is optional for you: add one if you want help staying on track.',
                  )
                : Column(
                    children: [
                      for (final link in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ParentTile(link: link, canRemove: !mustKeepOne || items.length > 1),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          Text('Add a parent', style: text.titleLarge),
          const SizedBox(height: 6),
          Text('Your parent scans this in their Study Assistant app.', style: text.bodyMedium),
          const SizedBox(height: 12),
          // Wait for the first load so only one code is created; after that a
          // new link count means the shown code was used, so make a fresh one.
          if (links.value case final items?)
            PairingQrCard(key: ValueKey(items.length))
          else
            const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}

class _ParentTile extends ConsumerWidget {
  const _ParentTile({required this.link, required this.canRemove});

  final FamilyLink link;
  final bool canRemove;

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Unlink ${link.personName}?'),
        content: const Text('They will no longer see your study time or manage your app locks.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Unlink')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(familyApiProvider).unlink(link.id);
      ref.invalidate(familyLinksProvider);
      await ref.read(authControllerProvider.notifier).refreshUser();
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClayCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      glow: AppColors.mint,
      child: Row(
        children: [
          IconBadge(Icons.family_restroom_rounded, size: 48, color: AppColors.mintDeep),
          const SizedBox(width: 14),
          Expanded(child: Text(link.personName, style: Theme.of(context).textTheme.titleMedium)),
          if (canRemove)
            IconButton(
              tooltip: 'Unlink',
              icon: Icon(Icons.link_off_rounded, color: AppColors.coralDeep),
              onPressed: () => _remove(context, ref),
            ),
        ],
      ),
    );
  }
}
