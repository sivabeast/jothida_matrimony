// PART 1 — the "permission denied" bug class, guarded at the source.
//
// Guest Mode broke an assumption the whole app was built on. Before it,
// `FirebaseAuth.currentUser?.uid == null` meant "nobody is signed in", so a
// personal Firestore query could safely run whenever a uid existed. An
// anonymous session HAS a uid, so every provider still written that way kept
// firing `where('userId', ==, <anonymous uid>)` listeners against collections
// guarded by `isAuthenticated()` — which deliberately excludes anonymous
// sessions. Firestore answered `permission-denied`, and the user saw "could
// not load" on Astrology, notifications, chats, interests and reports.
//
// The fix is `memberUidProvider`: null for a guest, the uid for a real member.
// These tests fail if a personal query goes back to keying off the raw auth
// stream, and if the routing rules that decide what a guest may open drift.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/router/auth_redirect.dart';

/// Providers that legitimately still read the RAW auth stream, with why.
const _allowedRawAuthUidReads = <String, String>{
  // The app-opening popup rotation is a per-device cursor in SharedPreferences,
  // not a Firestore query. A guest deliberately gets their own 'guest' cursor.
  'app_popup_provider.dart': 'local popup rotation cursor, no Firestore query',
};

void main() {
  group('personal Firestore queries never key off a guest uid', () {
    test('no provider watches the raw auth uid for a user-scoped query', () {
      final dir = Directory('lib/providers');
      expect(dir.existsSync(), isTrue, reason: 'lib/providers must exist');

      final offenders = <String>[];
      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final name = entity.uri.pathSegments.last;
        if (_allowedRawAuthUidReads.containsKey(name)) continue;

        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains(
              'ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid')) {
            offenders.add('$name:${i + 1}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'These read the uid straight off the auth stream, so they also '
            'run for a GUEST (anonymous sessions have a uid) and Firestore '
            'rejects them with permission-denied. Use memberUidProvider — it '
            'is null for a guest. Offenders: $offenders',
      );
    });
  });

  group('what a guest is allowed to open', () {
    test('the public pages a guest browses are all allow-listed', () {
      // Each of these renders admin-published content that the security rules
      // expose to `isAnyVisitor()`. If one is dropped from the allow-list the
      // router bounces guests to /login-required instead.
      for (final route in const [
        '/home', // banners + app popups
        '/astrology-appointment', // astrology_service/config
        '/muhurtham-calendar',
        '/help',
        '/privacy-policy',
        '/terms',
        '/child-safety',
      ]) {
        expect(isGuestAllowedRoute(route), isTrue,
            reason: '$route must stay browsable by a guest');
      }
      // Admin broadcasts are deep-linked from a push notification.
      expect(isGuestAllowedRoute('/announcement/abc123'), isTrue);
    });

    test('personal pages stay closed to a guest', () {
      for (final route in const [
        '/my-profile',
        '/partner-preferences',
        '/horoscope',
        '/settings',
        '/notifications',
        '/my-appointments',
        '/blocked-users',
      ]) {
        expect(isGuestAllowedRoute(route), isFalse,
            reason: '$route is personal and must require a login');
      }
    });

    test('a guest can never reach profile creation', () {
      // A guest has no account to attach a profile to, and the rules reject
      // every anonymous write.
      expect(isGuestAllowedRoute('/profile/create'), isFalse);
      expect(isGuestAllowedRoute('/complete-profile'), isFalse);
    });
  });

  group('the security rules keep their shape', () {
    late final String rules = File('firestore.rules').readAsStringSync();

    test('nothing is world-writable', () {
      // The blanket escape hatch must never appear (PART 8).
      expect(rules.contains('allow read, write: if true'), isFalse);
      expect(rules.contains('allow write: if true'), isFalse);
      expect(rules.contains('allow read, write: if request.auth != null;'),
          isFalse);
    });

    test('isAnyVisitor still means "signed in, anonymous included"', () {
      expect(rules.contains('function isAnyVisitor()'), isTrue);
      expect(rules.contains('function isAuthenticated()'), isTrue);
      // isAuthenticated must keep EXCLUDING anonymous — that exclusion is what
      // protects personal data from a guest session.
      expect(
        rules.contains(
            "request.auth.token.firebase.sign_in_provider != 'anonymous'"),
        isTrue,
      );
    });

    test('public admin-published content is readable by any visitor', () {
      // Each of these is content the admin publishes FOR everyone, and each was
      // a real permission-denied before: the banner carousel, the app-opening
      // popup, the Astrology page, admin broadcasts and the version gate.
      for (final collection in const [
        'banners',
        'app_popups',
        'astrology_service',
        'announcements',
        'app_config',
      ]) {
        final block = _matchBlock(rules, collection);
        expect(block, isNotNull, reason: 'no rule block for /$collection');
        expect(block, contains('allow read: if isAnyVisitor();'),
            reason: '/$collection must be readable by a guest');
        expect(block, contains('isAdmin()'),
            reason: '/$collection writes must stay admin-only');
      }
    });

    test('personal collections are NOT readable by a guest', () {
      for (final collection in const [
        'notifications',
        'contacts',
        'chats',
        'interests',
        'astrologer_requests',
      ]) {
        final block = _matchBlock(rules, collection);
        expect(block, isNotNull, reason: 'no rule block for /$collection');
        expect(block, isNot(contains('allow read: if isAnyVisitor();')),
            reason: '/$collection holds personal data — never isAnyVisitor()');
      }
    });
  });
}

/// The text of the `match /<collection>/{...} { ... }` block, or null.
///
/// Brace counting has to start at the brace that opens the BLOCK, not at the
/// `{bannerId}` path parameter on the same line — that one opens and closes
/// immediately and would end the block after a single character.
String? _matchBlock(String rules, String collection) {
  final start = rules.indexOf('match /$collection/{');
  if (start < 0) return null;
  final lineEnd = rules.indexOf('\n', start);
  if (lineEnd < 0) return null;
  final open = rules.lastIndexOf('{', lineEnd);
  if (open < 0) return null;

  var depth = 0;
  for (var i = open; i < rules.length; i++) {
    if (rules[i] == '{') depth++;
    if (rules[i] == '}') {
      depth--;
      if (depth == 0) return rules.substring(start, i + 1);
    }
  }
  return null;
}
