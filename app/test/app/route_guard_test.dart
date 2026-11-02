import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/app/routes.dart';
import 'package:study_assistant/features/auth/application/auth_controller.dart';
import 'package:study_assistant/features/auth/domain/app_user.dart';

import '../helpers.dart';

void main() {
  test('the lock screen is reachable whatever the sign-in state', () {
    expect(guardRoute(const AuthUnknown(), Routes.locked), isNull);
    expect(guardRoute(const AuthSignedOut(), Routes.locked), isNull);
    expect(guardRoute(AuthSignedIn(testUser(age: 12, parentalControlRequired: true)), Routes.locked), isNull);
  });

  group('while the session is loading', () {
    test('everything waits on the splash screen', () {
      expect(guardRoute(const AuthUnknown(), Routes.home), Routes.splash);
      expect(guardRoute(const AuthUnknown(), Routes.splash), isNull);
    });
  });

  group('signed out', () {
    const auth = AuthSignedOut();

    test('can open the sign-in pages', () {
      for (final route in Routes.signedOutOnly) {
        expect(guardRoute(auth, route), isNull, reason: route);
      }
    });

    test('is sent to welcome from anywhere else', () {
      expect(guardRoute(auth, Routes.home), Routes.welcome);
      expect(guardRoute(auth, Routes.parentHome), Routes.welcome);
      expect(guardRoute(auth, Routes.splash), Routes.welcome);
    });
  });

  group('student under 15 without a parent', () {
    final auth = AuthSignedIn(testUser(age: 12, parentalControlRequired: true));

    test('cannot leave the link-parent screen', () {
      expect(guardRoute(auth, Routes.home), Routes.linkParent);
      expect(guardRoute(auth, Routes.family), Routes.linkParent);
      expect(guardRoute(auth, Routes.login), Routes.linkParent);
      expect(guardRoute(auth, Routes.linkParent), isNull);
    });

    test('moves on once a parent links', () {
      final linked = AuthSignedIn(testUser(age: 12, parentalControlRequired: true, linkedParents: 1));
      expect(guardRoute(linked, Routes.linkParent), Routes.home);
      expect(guardRoute(linked, Routes.home), isNull);
    });
  });

  group('student 15 or over', () {
    final auth = AuthSignedIn(testUser());

    test('goes straight home and can open family', () {
      expect(guardRoute(auth, Routes.splash), Routes.home);
      expect(guardRoute(auth, Routes.linkParent), Routes.home);
      expect(guardRoute(auth, Routes.family), isNull);
    });

    test('cannot open parent pages', () {
      expect(guardRoute(auth, Routes.parentHome), Routes.home);
      expect(guardRoute(auth, Routes.addChild), Routes.home);
    });
  });

  group('parent', () {
    final auth = AuthSignedIn(testUser(role: UserRole.parent, age: 40));

    test('lands on the parent home and can add a child', () {
      expect(guardRoute(auth, Routes.welcome), Routes.parentHome);
      expect(guardRoute(auth, Routes.addChild), isNull);
    });

    test('cannot open student pages', () {
      expect(guardRoute(auth, Routes.home), Routes.parentHome);
      expect(guardRoute(auth, Routes.family), Routes.parentHome);
    });
  });

  group('admin', () {
    final auth = AuthSignedIn(testUser(role: UserRole.admin, age: 30));

    test('lands in the Control Room and stays there', () {
      expect(guardRoute(auth, Routes.splash), Routes.admin);
      expect(guardRoute(auth, Routes.login), Routes.admin);
      expect(guardRoute(auth, Routes.admin), isNull);
      expect(guardRoute(auth, Routes.home), Routes.admin);
      expect(guardRoute(auth, Routes.studyNew), Routes.admin);
      expect(guardRoute(auth, Routes.parentHome), Routes.admin);
    });

    test('students and parents never reach it', () {
      expect(guardRoute(AuthSignedIn(testUser()), Routes.admin), Routes.home);
      expect(guardRoute(AuthSignedIn(testUser(role: UserRole.parent, age: 40)), Routes.admin), Routes.parentHome);
    });
  });

  test('students and parents can always reach Delete account (Google Play)', () {
    expect(guardRoute(AuthSignedIn(testUser()), Routes.deleteAccount), isNull);
    expect(guardRoute(AuthSignedIn(testUser(role: UserRole.parent, age: 40)), Routes.deleteAccount), isNull);
  });
}
