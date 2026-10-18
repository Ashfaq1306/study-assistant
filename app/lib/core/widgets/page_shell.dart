import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'dreamy_background.dart';

/// Standard page: pastel background, safe area, scrolling body with a
/// comfortable max width, and an optional round back button.
class PageShell extends StatelessWidget {
  const PageShell({
    super.key,
    required this.child,
    this.showBack = true,
    this.title,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(24, 8, 24, 32),
  });

  final Widget child;
  final bool showBack;
  final String? title;
  final List<Widget> actions;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final canPop = showBack && Navigator.of(context).canPop();
    return Scaffold(
      body: DreamyBackground(
        child: SafeArea(
          child: Column(
            children: [
              if (canPop || title != null || actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      if (canPop) const RoundBackButton() else const SizedBox(width: 48),
                      Expanded(
                        child: Text(
                          title ?? '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      if (actions.isEmpty) const SizedBox(width: 48) else ...actions,
                    ],
                  ),
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: SingleChildScrollView(
                      padding: padding,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      child: child,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoundBackButton extends StatelessWidget {
  const RoundBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: const CircleBorder(side: BorderSide(color: AppColors.line, width: 1.5)),
      child: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink),
        onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
