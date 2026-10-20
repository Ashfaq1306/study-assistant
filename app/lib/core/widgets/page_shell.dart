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

class RoundBackButton extends StatefulWidget {
  const RoundBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  State<RoundBackButton> createState() => _RoundBackButtonState();
}

/// A round 3D button that sinks into its rim when pressed.
class _RoundBackButtonState extends State<RoundBackButton> {
  static const _size = 48.0;
  static const _depth = 4.0;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final rim = AppColors.isDark ? Color.lerp(AppColors.card, Colors.black, 0.45)! : const Color(0xFFE2DDF7);
    return Semantics(
      button: true,
      label: 'Back',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed ?? () => Navigator.of(context).maybePop(),
        child: Tooltip(
          message: 'Back',
          child: SizedBox(
            width: _size,
            height: _size + _depth,
            child: Stack(
              children: [
                Positioned(
                  top: _depth,
                  left: 0,
                  right: 0,
                  height: _size,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: rim,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.violet.withValues(alpha: 0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 70),
                  top: _pressed ? _depth : 0,
                  left: 0,
                  right: 0,
                  height: _size,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.card,
                      border: Border.all(
                        color: AppColors.isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(Icons.arrow_back_rounded, color: AppColors.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
