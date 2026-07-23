// Where does a signed-in account land?
//
// These pin the second half of the "stuck after Google Sign-In" fix: once
// authentication succeeds and `users/{uid}` has been read, the router must
// always move the user OFF the login screen. Anything that returns `null` here
// while sitting on /login is, by definition, an app that looks frozen.

import 'package:flutter_test/flutter_test.dart';
import 'package:jothida_matrimony/models/user_model.dart';
import 'package:jothida_matrimony/router/auth_redirect.dart';

UserModel _user({
  String role = 'user',
  bool isProfileComplete = false,
}) {
  final now = DateTime(2026, 7, 23);
  return UserModel(
    uid: 'uid-1',
    email: 'someone@gmail.com',
    role: role,
    isProfileComplete: isProfileComplete,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('signed out', () {
    test('an anonymous visitor is pushed to /login from a gated route', () {
      expect(
        resolveAuthRedirect(
            location: '/home',
            isAuthenticated: false,
            userDocLoading: false,
            user: null),
        '/login',
      );
    });

    test('the splash and login screens are left alone', () {
      for (final loc in ['/', '/login', '/register', '/forgot-password']) {
        expect(
          resolveAuthRedirect(
              location: loc,
              isAuthenticated: false,
              userDocLoading: false,
              user: null),
          isNull,
          reason: loc,
        );
      }
    });
  });

  group('just signed in on /login', () {
    test('an existing member with a complete profile goes to /home', () {
      expect(
        resolveAuthRedirect(
          location: '/login',
          isAuthenticated: true,
          userDocLoading: false,
          user: _user(isProfileComplete: true),
        ),
        '/home',
      );
    });

    test('a brand-new member goes to onboarding', () {
      expect(
        resolveAuthRedirect(
          location: '/login',
          isAuthenticated: true,
          userDocLoading: false,
          user: _user(isProfileComplete: false),
        ),
        '/profile/create',
      );
    });

    test('an employee goes to the Employee Portal', () {
      expect(
        resolveAuthRedirect(
          location: '/login',
          isAuthenticated: true,
          userDocLoading: false,
          user: _user(role: 'astrologer'),
        ),
        '/astrologer-dashboard',
      );
    });

    test('a pure admin goes to the admin panel', () {
      expect(
        resolveAuthRedirect(
          location: '/login',
          isAuthenticated: true,
          userDocLoading: false,
          user: _user(role: 'admin'),
        ),
        '/admin',
      );
    });

    test('a super_admin is treated as a normal member', () {
      expect(
        resolveAuthRedirect(
          location: '/login',
          isAuthenticated: true,
          userDocLoading: false,
          user: _user(role: 'super_admin', isProfileComplete: true),
        ),
        '/home',
      );
    });

    test('a family member goes to the Wedding Workspace', () {
      expect(
        resolveAuthRedirect(
          location: '/login',
          isAuthenticated: true,
          userDocLoading: false,
          user: _user(role: 'family'),
        ),
        '/wedding-workspace',
      );
    });

    test(
        'NOBODY authenticated is ever left on /login once the user doc has '
        'resolved', () {
      const roles = ['user', 'admin', 'super_admin', 'astrologer', 'family'];
      for (final role in roles) {
        for (final complete in [true, false]) {
          final destination = resolveAuthRedirect(
            location: '/login',
            isAuthenticated: true,
            userDocLoading: false,
            user: _user(role: role, isProfileComplete: complete),
          );
          expect(destination, isNotNull,
              reason: 'role=$role, isProfileComplete=$complete would sit on '
                  'the login screen forever');
          expect(destination, isNot('/login'), reason: 'role=$role');
        }
      }
    });

    test('a missing user document still moves off /login', () {
      // The document read failed or returned nothing: /home is a real screen
      // that can recover, the login spinner is not.
      expect(
        resolveAuthRedirect(
          location: '/login',
          isAuthenticated: true,
          userDocLoading: false,
          user: null,
        ),
        '/home',
      );
    });

    test('the family-login invite check holds the user on /login', () {
      expect(
        resolveAuthRedirect(
          location: '/login',
          isAuthenticated: true,
          userDocLoading: false,
          user: _user(),
          familyLoginInProgress: true,
        ),
        isNull,
      );
    });
  });

  test('while the user document is still loading, nothing moves', () {
    expect(
      resolveAuthRedirect(
        location: '/login',
        isAuthenticated: true,
        userDocLoading: true,
        user: null,
      ),
      isNull,
    );
  });

  group('route protection for an authenticated account', () {
    test('a member cannot open the Employee Portal', () {
      expect(
        resolveAuthRedirect(
          location: '/astrologer-dashboard',
          isAuthenticated: true,
          userDocLoading: false,
          user: _user(isProfileComplete: true),
        ),
        '/home',
      );
    });

    test('an employee stays inside the Employee Portal', () {
      expect(
        resolveAuthRedirect(
          location: '/astrologer-request/abc',
          isAuthenticated: true,
          userDocLoading: false,
          user: _user(role: 'astrologer'),
        ),
        isNull,
      );
      expect(
        resolveAuthRedirect(
          location: '/home',
          isAuthenticated: true,
          userDocLoading: false,
          user: _user(role: 'astrologer'),
        ),
        '/astrologer-dashboard',
      );
    });

    test('a non-admin cannot open /admin routes', () {
      expect(
        resolveAuthRedirect(
          location: '/admin/users',
          isAuthenticated: true,
          userDocLoading: false,
          user: _user(isProfileComplete: true),
        ),
        '/home',
      );
    });

    test('an incomplete profile is funnelled back into onboarding', () {
      expect(
        resolveAuthRedirect(
          location: '/chats',
          isAuthenticated: true,
          userDocLoading: false,
          user: _user(isProfileComplete: false),
        ),
        '/profile/create',
      );
    });

    test('a completed profile is not sent back through onboarding', () {
      expect(
        resolveAuthRedirect(
          location: '/profile/create',
          isAuthenticated: true,
          userDocLoading: false,
          user: _user(isProfileComplete: true),
        ),
        '/home',
      );
    });

    test('demo mode (kBypassAuth) never redirects', () {
      expect(
        resolveAuthRedirect(
          location: '/home',
          isAuthenticated: false,
          userDocLoading: false,
          user: null,
          bypassAuth: true,
        ),
        isNull,
      );
    });
  });
}
