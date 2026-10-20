import '../features/auth/application/auth_controller.dart';
import '../features/auth/domain/app_user.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const login = '/login';
  static const register = '/register';
  static const verify = '/verify';
  static const forgotPassword = '/forgot-password';
  static const linkParent = '/link-parent';
  static const home = '/home';
  static const family = '/home/family';
  static const studyNew = '/home/study';
  static const studySession = '/home/session';
  static const stats = '/home/stats';
  static const exam = '/home/exam';
  static const tutor = '/home/tutor';
  static const calendar = '/home/calendar';
  static const calendarEdit = '/home/calendar/edit';
  static const calendarImport = '/home/calendar/import';
  static const parentHome = '/parent';
  static const addChild = '/parent/add-child';
  static const appLock = '/home/app-lock';

  /// Settings shared by students and parents.
  static const appearance = '/settings/appearance';

  /// Shown over a locked app. Reachable in every sign-in state.
  static const locked = '/locked';

  static const signedOutOnly = {welcome, login, register, verify, forgotPassword};

  static String homeFor(AppUser user) => user.isParent ? parentHome : home;
}

/// Decides where a navigation may go for the current auth state.
/// Returns the location to redirect to, or null to allow it.
String? guardRoute(AuthState auth, String location) {
  if (location == Routes.locked) return null;
  switch (auth) {
    case AuthUnknown():
      return location == Routes.splash ? null : Routes.splash;

    case AuthSignedOut():
      return Routes.signedOutOnly.contains(location) ? null : Routes.welcome;

    case AuthSignedIn(:final user):
      // An under-15 student cannot go anywhere until a parent links.
      if (user.needsParentLink) return location == Routes.linkParent ? null : Routes.linkParent;

      final home = Routes.homeFor(user);
      if (location == Routes.splash || location == Routes.linkParent || Routes.signedOutOnly.contains(location)) {
        return home;
      }
      if (location.startsWith('/settings/')) return null;
      final inParentArea = location == Routes.parentHome || location.startsWith('${Routes.parentHome}/');
      if (inParentArea != user.isParent) return home;
      return null;
  }
}
