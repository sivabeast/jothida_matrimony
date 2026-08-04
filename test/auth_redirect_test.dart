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

    // Profile creation is never forced: a brand-new account goes straight to
    // Home, which shows the "Create Profile" call-to-action.
    test('a brand-new member goes to Home, NOT onboarding', () {
      expect(
        resolveAuthRedirect(
          location: '/login',
          isAuthenticated: true,
          userDocLoading: false,
          user: _user(isProfileComplete: false),
        ),
        '/home',
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

    // §2 — the dedicated admin account is admin-ONLY: never the user Home,
    // never profile creation, never any other user-side page.
    test('a pure admin is confined to /admin', () {
      for (final location in [
        '/home',
        '/profile/create',
        '/matches',
        '/settings',
        '/chat/abc',
        '/interests',
      ]) {
        expect(
          resolveAuthRedirect(
            location: location,
            isAuthenticated: true,
            userDocLoading: false,
            user: _user(role: 'admin'),
          ),
          '/admin',
          reason: 'a dedicated admin must not reach "$location"',
        );
      }
    });

    test('a pure admin stays put inside the admin panel', () {
      for (final location in ['/admin', '/admin/users', '/admin/reports']) {
        expect(
          resolveAuthRedirect(
            location: location,
            isAuthenticated: true,
            userDocLoading: false,
            user: _user(role: 'admin'),
          ),
          isNull,
          reason: 'a dedicated admin should stay on "$location"',
        );
      }
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

    test('a missing user document keeps the account on /login', () {
      // REGRESSION (Delete Account): after deletion the `users/{uid}` document
      // is gone while the Auth session is still being torn down. Sending such
      // an account to /home is the "Delete Account just returns me Home and I'm
      // still logged in" bug — it must stay on the login screen.
      expect(
        resolveAuthRedirect(
          location: '/login',
          isAuthenticated: true,
          userDocLoading: false,
          user: null,
        ),
        isNull,
      );
    });

    test('a deleted account is pushed off every gated screen', () {
      for (final loc in ['/home', '/chats', '/settings', '/reports']) {
        expect(
          resolveAuthRedirect(
            location: loc,
            isAuthenticated: true,
            userDocLoading: false,
            user: null,
          ),
          '/login',
          reason: loc,
        );
      }
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

    test('an account without a profile browses freely — never forced into '
        'onboarding', () {
      for (final loc in ['/chats', '/home', '/settings', '/interests']) {
        expect(
          resolveAuthRedirect(
            location: loc,
            isAuthenticated: true,
            userDocLoading: false,
            user: _user(isProfileComplete: false),
          ),
          isNull,
          reason: loc,
        );
      }
    });

    test('the profile wizard opens on demand for an account without a profile',
        () {
      expect(
        resolveAuthRedirect(
          location: '/profile/create',
          isAuthenticated: true,
          userDocLoading: false,
          user: _user(isProfileComplete: false),
        ),
        isNull,
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

  // ── Guest Mode (§13) ──────────────────────────────────────────────────────
  //
  // A guest is authenticated to Firebase but has NO users/{uid} document, so
  // these cases all pass `user: null` — which for a NON-guest would mean
  // "bounce to /login". The guest branch has to win first, otherwise Guest
  // Mode is unusable.
  group('guest mode', () {
    String? guestAt(String location) => resolveAuthRedirect(
          location: location,
          isAuthenticated: true,
          isGuest: true,
          userDocLoading: false,
          user: null,
        );

    test('a guest may browse the public surfaces', () {
      for (final loc in const [
        '/home',
        '/muhurtham-calendar',
        '/privacy-policy',
        '/terms',
        '/child-safety',
        '/help',
        '/announcement/abc123',
      ]) {
        expect(guestAt(loc), isNull, reason: 'guest should be allowed at $loc');
      }
    });

    test('every personalized feature sends a guest to Login Required', () {
      // The exact list the spec calls out, plus the routes that would leak
      // member data or write permanent records.
      for (final loc in const [
        '/matches',
        '/interests',
        '/chats',
        '/chat/thread1',
        '/my-profile',
        '/profile/create',
        '/profile/p1',
        '/profile/p1/edit',
        '/astrology-appointment',
        '/book-appointment/u1',
        '/horoscope-files',
        '/horoscope-report/u1',
        '/reports',
        '/my-appointments',
        '/notifications',
        '/settings',
        '/partner-preferences',
        '/wedding-workspace',
      ]) {
        expect(guestAt(loc), '/login-required',
            reason: 'guest should be blocked from $loc');
      }
    });

    test('a guest never reaches the admin panel or the employee portal', () {
      expect(guestAt('/admin'), '/login-required');
      expect(guestAt('/admin/users'), '/login-required');
      expect(guestAt('/astrologer-dashboard'), '/login-required');
    });

    test('an unknown route is blocked by default, not allowed', () {
      // The allow-list is what makes a NEW personalized screen safe before
      // anyone remembers to gate it.
      expect(guestAt('/some-feature-added-next-year'), '/login-required');
    });

    test('a guest may still reach the auth pages to upgrade', () {
      expect(guestAt('/login'), isNull);
      expect(guestAt('/register'), isNull);
      expect(guestAt('/login-required'), isNull);
    });

    test('guest routing does not leak into a real signed-in account', () {
      // Same location, isGuest false → the normal rules apply and a member
      // with no user document still goes to /login.
      expect(
        resolveAuthRedirect(
          location: '/matches',
          isAuthenticated: true,
          isGuest: false,
          userDocLoading: false,
          user: null,
        ),
        '/login',
      );
      // …and a real member is NOT sent to /login-required.
      expect(
        resolveAuthRedirect(
          location: '/matches',
          isAuthenticated: true,
          isGuest: false,
          userDocLoading: false,
          user: _user(isProfileComplete: true),
        ),
        isNull,
      );
    });

    test('a signed-out visitor is unaffected by the guest branch', () {
      expect(
        resolveAuthRedirect(
          location: '/home',
          isAuthenticated: false,
          isGuest: false,
          userDocLoading: false,
          user: null,
        ),
        '/login',
      );
    });
  });
}
