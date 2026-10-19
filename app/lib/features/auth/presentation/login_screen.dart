import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../application/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  ApiException? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final pending = await ref.read(authControllerProvider.notifier).login(_identifier.text, _password.text);
      // Signed in: the router moves on by itself. Otherwise finish verification.
      if (pending != null && mounted) await context.push(Routes.verify, extra: pending);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PageShell(
      child: AutofillGroup(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: IconBadge(Icons.waving_hand_rounded, size: 76)),
              const SizedBox(height: 16),
              Text('Welcome back!', textAlign: TextAlign.center, style: text.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'Sign in with your email or mobile number.',
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 28),
              AppTextField(
                label: 'Email or mobile number',
                controller: _identifier,
                hint: 'you@example.com or 017…',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                validator: Validators.identifier,
                errorText: _error?.fieldErrors['identifier'],
              ),
              const SizedBox(height: 18),
              AppTextField(
                label: 'Password',
                controller: _password,
                icon: Icons.lock_rounded,
                obscure: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                validator: (v) => (v ?? '').isEmpty ? 'Enter your password.' : null,
                onSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push(Routes.forgotPassword),
                  child: const Text('Forgot password?'),
                ),
              ),
              if (_error != null) ...[MessageBanner.error(_error!.message), const SizedBox(height: 16)],
              const SizedBox(height: 8),
              Button3D(label: 'Sign in', loading: _loading, onPressed: _submit),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'New here?',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft),
                  ),
                  TextButton(
                    onPressed: () => context.pushReplacement(Routes.register),
                    child: const Text('Create an account'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
