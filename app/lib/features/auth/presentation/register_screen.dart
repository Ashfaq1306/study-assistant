import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/button_3d.dart';
import '../../../core/widgets/clay_card.dart';
import '../../../core/widgets/dreamy_background.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/page_shell.dart';
import '../../../core/widgets/password_meter.dart';
import '../application/auth_controller.dart';
import '../data/auth_api.dart';
import '../domain/app_user.dart';
import '../domain/otp.dart';

/// Three short steps: who you are → about you → your login.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  static const _stepCount = 3;
  static const _minStudentAge = 5;
  static const _minParentAge = 18;

  final _pages = PageController();
  final _aboutForm = GlobalKey<FormState>();
  final _loginForm = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _dob = TextEditingController();

  int _step = 0;
  UserRole? _role;
  DateTime? _dateOfBirth;
  OtpChannel _channel = OtpChannel.email;
  bool _loading = false;
  ApiException? _error;

  int? get _age => _dateOfBirth == null ? null : ageOn(_dateOfBirth!, DateTime.now());

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _dob]) {
      c.dispose();
    }
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    _pages.animateToPage(step, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  void _back() => _step == 0 ? context.pop() : _goTo(_step - 1);

  String? _dobError() {
    final age = _age;
    if (age == null) return 'Pick your date of birth.';
    if (_role == UserRole.parent && age < _minParentAge) return 'Parents must be at least $_minParentAge.';
    if (_role == UserRole.student && age < _minStudentAge) return 'Students must be at least $_minStudentAge.';
    return null;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - (_role == UserRole.parent ? 35 : 12), now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Your date of birth',
    );
    if (picked == null) return;
    _dob.text = _formatDate(picked);
    setState(() => _dateOfBirth = picked);
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_loginForm.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final pending = await ref
          .read(authControllerProvider.notifier)
          .register(
            RegisterRequest(
              role: _role!,
              name: _name.text,
              dateOfBirth: _dateOfBirth!,
              email: _email.text,
              phone: _phone.text,
              password: _password.text,
              otpChannel: _channel,
            ),
          );
      if (mounted) await context.push(Routes.verify, extra: pending);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      // Send the user to the step that holds the first problem.
      final fields = e.fieldErrors.keys;
      if (fields.any((f) => f == 'name' || f == 'dateOfBirth')) _goTo(1);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DreamyBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    RoundBackButton(onPressed: _back),
                    Expanded(
                      child: _StepDots(current: _step, count: _stepCount),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [_roleStep(), _aboutStep(), _loginStep()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepBody({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
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
              Center(child: IconBadge(icon, size: 72)),
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

  Widget _roleStep() {
    return _stepBody(
      icon: Icons.auto_awesome_rounded,
      title: 'Who is joining?',
      subtitle: 'Pick one. You can link student and parent accounts later.',
      children: [
        _RoleCard(
          icon: Icons.backpack_rounded,
          title: "I'm a student",
          subtitle: 'Focus, lock distracting apps and pass quizzes to unlock them.',
          color: AppColors.violet,
          selected: _role == UserRole.student,
          onTap: () => setState(() => _role = UserRole.student),
        ),
        const SizedBox(height: 16),
        _RoleCard(
          icon: Icons.family_restroom_rounded,
          title: "I'm a parent",
          subtitle: "Link to your child's phone, see screen time and set quizzes.",
          color: AppColors.mintDeep,
          selected: _role == UserRole.parent,
          onTap: () => setState(() => _role = UserRole.parent),
        ),
        const SizedBox(height: 28),
        Button3D(label: 'Continue', onPressed: _role == null ? null : () => _goTo(1)),
      ],
    );
  }

  Widget _aboutStep() {
    final age = _age;
    final dobError = _dateOfBirth == null ? null : _dobError();
    final needsParent =
        _role == UserRole.student && age != null && age >= _minStudentAge && age < AppConfig.parentalControlAge;
    return Form(
      key: _aboutForm,
      child: _stepBody(
        icon: Icons.badge_rounded,
        title: 'Tell us about you',
        subtitle: 'This helps us keep the app right for your age.',
        children: [
          AppTextField(
            label: _role == UserRole.parent ? 'Your name' : 'Your first and last name',
            controller: _name,
            icon: Icons.face_rounded,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            validator: Validators.name,
            errorText: _error?.fieldErrors['name'],
          ),
          const SizedBox(height: 18),
          AppTextField(
            label: 'Date of birth',
            controller: _dob,
            hint: 'Tap to pick',
            icon: Icons.cake_rounded,
            readOnly: true,
            onTap: _pickDate,
            validator: (_) => _dobError(),
            errorText: dobError ?? _error?.fieldErrors['dateOfBirth'],
          ),
          if (needsParent) ...[
            const SizedBox(height: 16),
            const MessageBanner.info(
              "You're under ${AppConfig.parentalControlAge}, so a parent links to your account right after you "
              'sign up. Keep their phone nearby!',
            ),
          ],
          const SizedBox(height: 28),
          Button3D(
            label: 'Continue',
            onPressed: () {
              if (_aboutForm.currentState!.validate()) _goTo(2);
            },
          ),
        ],
      ),
    );
  }

  Widget _loginStep() {
    return Form(
      key: _loginForm,
      child: AutofillGroup(
        child: _stepBody(
          icon: Icons.lock_person_rounded,
          title: 'Create your login',
          subtitle: "We'll send a 6-digit code to open your account.",
          children: [
            AppTextField(
              label: _channel == OtpChannel.email ? 'Email' : 'Email (optional)',
              controller: _email,
              hint: 'you@example.com',
              icon: Icons.mail_rounded,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: (v) => Validators.email(v, required: _channel == OtpChannel.email),
              errorText: _error?.fieldErrors['email'],
            ),
            const SizedBox(height: 18),
            AppTextField(
              label: _channel == OtpChannel.sms ? 'Mobile number' : 'Mobile number (optional)',
              controller: _phone,
              hint: '01712345678',
              icon: Icons.phone_iphone_rounded,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              validator: (v) => Validators.phone(v, required: _channel == OtpChannel.sms),
              errorText: _error?.fieldErrors['phone'],
            ),
            const SizedBox(height: 18),
            const Padding(
              padding: EdgeInsets.only(left: 6, bottom: 8),
              child: Text('Send my code by', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ),
            Row(
              children: [
                for (final channel in OtpChannel.values) ...[
                  if (channel != OtpChannel.values.first) const SizedBox(width: 12),
                  Expanded(
                    child: ClayCard(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      radius: 20,
                      selected: _channel == channel,
                      onTap: () => setState(() => _channel = channel),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            channel == OtpChannel.email ? Icons.mail_rounded : Icons.sms_rounded,
                            color: _channel == channel ? AppColors.violet : AppColors.inkSoft,
                          ),
                          const SizedBox(width: 8),
                          Text(channel.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            AppTextField(
              label: 'Password',
              controller: _password,
              icon: Icons.lock_rounded,
              obscure: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              validator: Validators.password,
              errorText: _error?.fieldErrors['password'],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            PasswordMeter(password: _password.text),
            if (_error != null && _error!.fieldErrors.isEmpty) ...[
              const SizedBox(height: 16),
              MessageBanner.error(_error!.message),
            ],
            const SizedBox(height: 28),
            Button3D(label: 'Send my code', icon: Icons.send_rounded, loading: _loading, onPressed: _submit),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: ClayCard(
        glow: color,
        selected: selected,
        onTap: onTap,
        child: Row(
          children: [
            IconBadge(icon, color: color, size: 64),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: selected
                  ? Icon(Icons.check_circle_rounded, key: const ValueKey(true), color: color, size: 30)
                  : Icon(Icons.circle_outlined, key: const ValueKey(false), color: AppColors.line, size: 30),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.current, required this.count});

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
