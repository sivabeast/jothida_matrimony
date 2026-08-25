// Regression tests for the Guest-mode and matrimony-photo rules.
//
//   §1  a guest is never offered Sign Out — they get Login instead;
//   §3  the guest login prompt honours a real 10-minute interval;
//   §6  a Google (or any identity-provider) account picture is never used as
//       a matrimony profile photo, and never as a fallback for one.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/utils/matrimony_photo.dart';
import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:jothida_matrimony/providers/auth_provider.dart';
import 'package:jothida_matrimony/providers/guest_login_prompt_provider.dart';
import 'package:jothida_matrimony/widgets/common/app_drawer.dart';

/// A minimal host for the drawer with [isGuestProvider] pinned to [isGuest].
Widget _drawerHost({required bool isGuest}) => ProviderScope(
      overrides: [isGuestProvider.overrideWithValue(isGuest)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AppDrawer()),
      ),
    );

void main() {
  group('§1 / PART 4 — one menu, only the bottom action changes', () {
    /// Every navigation entry's label, in order.
    List<String> menuLabels(WidgetTester tester) => tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data ?? '')
        .toList();

    testWidgets('a guest is offered Login, never Sign Out', (tester) async {
      await tester.pumpWidget(_drawerHost(isGuest: true));
      await tester.pump();

      expect(find.text('Login to Continue'), findsOneWidget);
      expect(find.text('Sign Out'), findsNothing);
      expect(find.byIcon(Icons.logout), findsNothing);
    });

    testWidgets('a signed-in member is offered Sign Out, never Login',
        (tester) async {
      await tester.pumpWidget(_drawerHost(isGuest: false));
      await tester.pump();

      expect(find.byIcon(Icons.logout), findsOneWidget);
      expect(find.text('Login to Continue'), findsNothing);
    });

    testWidgets('the menu structure is IDENTICAL either way', (tester) async {
      await tester.pumpWidget(_drawerHost(isGuest: false));
      await tester.pump();
      final member = menuLabels(tester);

      await tester.pumpWidget(_drawerHost(isGuest: true));
      await tester.pump();
      final guest = menuLabels(tester);

      // Same count, same order — only the last entry (the auth action) differs.
      expect(guest.length, member.length);
      expect(guest.sublist(0, guest.length - 1),
          member.sublist(0, member.length - 1));
      expect(member.last, 'Sign Out');
      expect(guest.last, 'Login to Continue');
    });

    testWidgets('no sign-up button or extra auth card in the menu',
        (tester) async {
      await tester.pumpWidget(_drawerHost(isGuest: true));
      await tester.pump();

      // The "Create Account" action was removed from the drawer (PART 4.3):
      // the bottom slot holds exactly ONE authentication action.
      expect(find.text('Create Account'), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byIcon(Icons.login), findsOneWidget);
    });
  });

  group('§3 guest login prompt interval', () {
    final now = DateTime(2026, 8, 24, 12, 0);

    test('a signed-in member is never prompted', () {
      expect(
        shouldShowGuestLoginPrompt(
            isGuest: false, lastShownMs: null, now: now),
        isFalse,
      );
      expect(
        shouldShowGuestLoginPrompt(
          isGuest: false,
          lastShownMs:
              now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
          now: now,
        ),
        isFalse,
      );
    });

    test('a guest who has never been prompted is prompted', () {
      expect(
        shouldShowGuestLoginPrompt(isGuest: true, lastShownMs: null, now: now),
        isTrue,
      );
    });

    test('closing it does not let it come straight back', () {
      for (final elapsed in const [
        Duration.zero,
        Duration(seconds: 30),
        Duration(minutes: 5),
        Duration(minutes: 9, seconds: 59),
      ]) {
        expect(
          shouldShowGuestLoginPrompt(
            isGuest: true,
            lastShownMs: now.subtract(elapsed).millisecondsSinceEpoch,
            now: now,
          ),
          isFalse,
          reason: 'prompted again after only $elapsed',
        );
      }
    });

    test('it returns once the 10-minute interval has passed', () {
      for (final elapsed in const [
        Duration(minutes: 10),
        Duration(minutes: 11),
        Duration(hours: 2),
      ]) {
        expect(
          shouldShowGuestLoginPrompt(
            isGuest: true,
            lastShownMs: now.subtract(elapsed).millisecondsSinceEpoch,
            now: now,
          ),
          isTrue,
          reason: 'not prompted after $elapsed',
        );
      }
    });

    test('a stamp in the future does not lock the prompt out for ever', () {
      expect(
        shouldShowGuestLoginPrompt(
          isGuest: true,
          lastShownMs:
              now.add(const Duration(days: 2)).millisecondsSinceEpoch,
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('§6 Google photo is never a matrimony photo', () {
    const google =
        'https://lh3.googleusercontent.com/a/ACg8ocK_abc123=s96-c';
    const facebook = 'https://graph.facebook.com/1234567890/picture';
    const uploaded =
        'https://res.cloudinary.com/demo/image/upload/v1/profiles/abc.jpg';

    test('identity-provider avatars are recognised', () {
      expect(isAuthProviderPhoto(google), isTrue);
      expect(isAuthProviderPhoto(facebook), isTrue);
      expect(isAuthProviderPhoto(uploaded), isFalse);
      expect(isAuthProviderPhoto(''), isFalse);
      expect(isAuthProviderPhoto(null), isFalse);
    });

    test('the uploaded matrimony photo is used when there is one', () {
      expect(matrimonyPhotoUrl(uploaded, google), uploaded);
      expect(matrimonyPhotoUrl(null, uploaded), uploaded);
    });

    test('a Google photo is never a fallback — the placeholder is', () {
      expect(matrimonyPhotoUrl(null, google), '');
      expect(matrimonyPhotoUrl('', google), '');
      expect(matrimonyPhotoUrl(google, google), '');
      expect(matrimonyPhotoUrl(google, facebook), '');
      expect(matrimonyPhotoUrl(null, null), '');
    });

    test('a Google photo stored on the profile itself is still dropped', () {
      // Legacy documents written before the rule existed.
      expect(matrimonyPhotoUrl(google, uploaded), uploaded);
    });
  });
}
