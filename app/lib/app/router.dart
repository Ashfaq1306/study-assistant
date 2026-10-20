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
import '../features/parent/domain/parent_models.dart';
import '../features/parent/presentation/alerts_screen.dart';
import '../features/parent/presentation/child_screen.dart';
import '../features/parent/presentation/lock_editor_screen.dart';
import '../features/parent/presentation/question_set_editor_screen.dart';
import '../features/parent/presentation/question_sets_screen.dart';
import '../features/home/presentation/student_home_screen.dart';
import '../features/study/presentation/active_session_screen.dart';
import '../features/study/presentation/start_session_screen.dart';
import '../features/study/presentation/stats_screen.dart';
import '../features/calendar/domain/calendar_event.dart';
import '../features/calendar/presentation/calendar_screen.dart';
import '../features/calendar/presentation/event_editor_screen.dart';
import '../features/calendar/presentation/import_calendar_screen.dart';
import '../features/settings/appearance_screen.dart';
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
          GoRoute(
            path: 'exam',
            builder: (_, s) => ExamScreen(lockId: s.uri.queryParameters['lock']),
          ),
          GoRoute(path: 'app-lock', builder: (_, _) => const AppLockScreen()),
          GoRoute(path: 'tutor', builder: (_, _) => const TutorScreen()),
          GoRoute(
            path: 'calendar',
            builder: (_, _) => const CalendarScreen(),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (_, state) => EventEditorScreen(
                  event:
                      state.extra as CalendarEvent? ??
                      CalendarEvent(kind: CalendarKind.exam, title: '', startsAt: DateTime.now()),
                ),
              ),
              GoRoute(path: 'import', builder: (_, _) => const ImportCalendarScreen()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.parentHome,
        pageBuilder: (_, s) => _fade(s, const ParentHomeScreen()),
        routes: [
          GoRoute(path: 'add-child', builder: (_, _) => const AddChildScreen()),
          GoRoute(path: 'alerts', builder: (_, _) => const AlertsScreen()),
          GoRoute(
            path: 'questions',
            builder: (_, _) => const QuestionSetsScreen(),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (_, s) => QuestionSetEditorScreen(set: s.extra as QuestionSet?),
              ),
            ],
          ),
          GoRoute(
            path: 'child/:id',
            builder: (_, s) => ChildScreen(childId: s.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'lock',
                builder: (_, s) => LockEditorScreen(childId: s.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: Routes.appearance, builder: (_, _) => const AppearanceScreen()),
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
