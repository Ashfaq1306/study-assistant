import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'dreamy_background.dart';
import 'feedback.dart';
import 'page_shell.dart';

/// A multi-step flow: back button, progress dots, and one page per step.
class WizardScaffold extends StatelessWidget {
  const WizardScaffold({
    super.key,
    required this.controller,
    required this.step,
    required this.pages,
    required this.onBack,
  });

  final PageController controller;
  final int step;
  final List<Widget> pages;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: Scaffold(
        body: DreamyBackground(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      RoundBackButton(onPressed: onBack),
                      Expanded(
                        child: StepDots(current: step, count: pages.length),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: controller,
                    physics: const NeverScrollableScrollPhysics(),
                    children: pages,
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

/// One step's content: icon, title, subtitle, then the controls.
class WizardPage extends StatelessWidget {
  const WizardPage({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  /// The theme accent when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppColors.violet;
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: IconBadge(icon, size: 72, color: color)),
              const SizedBox(height: 14),
              Text(title, textAlign: TextAlign.center, style: text.headlineMedium),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 26),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class StepDots extends StatelessWidget {
  const StepDots({super.key, required this.current, required this.count});

  final int current;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${current + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == current ? 28 : 10,
              height: 10,
              decoration: BoxDecoration(
                color: i <= current ? AppColors.violet : AppColors.line,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small heading above a group of controls.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6, bottom: 10),
    child: Text(
      text,
      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.ink),
    ),
  );
}
