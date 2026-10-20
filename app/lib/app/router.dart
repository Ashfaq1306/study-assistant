import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/app_lock/presentation/app_lock_screen.dart';
import '../features/app_lock/presentation/locked_screen.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/domain/otp.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/verify_screen.dart';
import '../features/auth/presentation/welcome_screen.dart';
import '../features/exam/presentation/exam_screen.dart';
import '../features/family/presentation/add_child_screen.dart';
import '../features/family/presentation/family_screen.dart';
import '../features/family/presentation/link_parent_screen.dart';
import '../features/home/presentation/parent_home_screen.dart';
import '../features/home/presentation/student_home_screen.dart';
import '../features/study/presentation/active_session_screen.dart';
import '../features/study/presentation/start_session_screen.dart';
import '../features/study/presentation/stats_screen.dart';
import '../features/tutor/tutor_screen.dart';
import 'routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Bridges Riverpod to go_router: every auth change re-runs the guard.
  final authListenable = ValueNotifier<AuthState>(ref.read(authControllerProvider));
  ref.listen(authControllerProvider, (_, next) => authListenable.value = next);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: authListenable,
    redirect: (context, state) => guardRoute(authListenable.value, state.matchedLocation),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: Routes.locked,
        pageBuilder: (_, s) => _fade(s, LockedScreen(appLabel: s.uri.queryParameters['app'])),
      ),
      GoRoute(path: Routes.welcome, pageBuilder: (_, s) => _fade(s, const WelcomeScreen())),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: Routes.verify,
        builder: (_, state) => VerifyScreen(pending: state.extra as PendingVerification?),
      ),
      GoRoute(path: Routes.forgotPassword, builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: Routes.linkParent, pageBuilder: (_, s) => _fade(s, const LinkParentScreen())),
      GoRoute(
        path: Routes.home,
        pageBuilder: (_, s) => _fade(s, const StudentHomeScreen()),
        routes: [
          GoRoute(path: 'family', builder: (_, _) => const FamilyScreen()),
          GoRoute(path: 'study', builder: (_, _) => const StartSessionScreen()),
          GoRoute(path: 'session', builder: (_, _) => const ActiveSessionScreen()),
          GoRoute(path: 'stats', builder: (_, _) => const StatsScreen()),
          GoRoute(path: 'exam', builder: (_, _) => const ExamScreen()),
          GoRoute(path: 'app-lock', builder: (_, _) => const AppLockScreen()),
          GoRoute(path: 'tutor', builder: (_, _) => const TutorScreen()),
        ],
      ),
      GoRoute(
        path: Routes.parentHome,
        pageBuilder: (_, s) => _fade(s, const ParentHomeScreen()),
        routes: [GoRoute(path: 'add-child', builder: (_, _) => const AddChildScreen())],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    authListenable.dispose();
  });
  return router;
});

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage(
  key: state.pageKey,
  child: child,
  transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
);
