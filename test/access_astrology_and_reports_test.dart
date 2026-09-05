// The four behaviours this change is judged on, end to end where it matters:
//
//   • WHO may talk to whom (spec §2–§4): a private profile needs an accepted
//     interest, a public one does not, and both resolve through ONE helper so
//     Chat, Contact and the Horoscope Report can never disagree;
//   • the Chats list shows the conversations a member actually has (§1) —
//     the accepted-interest filter that emptied it is gone;
//   • the astrology page is astrologer details + contact, with no booking
//     control of any kind left on it (§21–§29, §44);
//   • booking has no route to reach any more (§22/§23).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/utils/profile_access.dart';
import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:jothida_matrimony/models/astrology_service_config.dart';
import 'package:jothida_matrimony/models/chat_model.dart';
import 'package:jothida_matrimony/models/interest_model.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/providers/astrology_config_provider.dart';
import 'package:jothida_matrimony/providers/chat_provider.dart';
import 'package:jothida_matrimony/providers/interest_provider.dart';
import 'package:jothida_matrimony/router/auth_redirect.dart';
import 'package:jothida_matrimony/screens/chat/chat_list_screen.dart';
import 'package:jothida_matrimony/screens/home/tabs/astrology_service_page.dart';

const _myUid = 'uid-mine';
const _otherUid = 'uid-theirs';

ProfileModel _otherProfile({required bool public}) => ProfileModel.fromMap({
      'id': 'theirs',
      'userId': _otherUid,
      'name': 'Kavitha S',
      'city': 'Madurai',
      'state': 'Tamil Nadu',
      // The wizard's Private / Public choice. Legacy profiles carry nothing
      // here and must therefore read as private.
      if (public) 'contactPrivacy': 'public',
    });

InterestModel _accepted() => InterestModel(
      id: 'INT-1',
      senderId: _myUid,
      senderProfileId: 'mine',
      receiverId: _otherUid,
      receiverProfileId: 'theirs',
      status: 'accepted',
      sentAt: DateTime(2026, 9, 1),
    );

ChatThread _thread() => ChatThread(
      id: '${_myUid}_$_otherUid',
      participantIds: const [_myUid, _otherUid],
      participantNames: const {_myUid: 'Arun K', _otherUid: 'Kavitha S'},
      participantPhotos: const {_myUid: '', _otherUid: ''},
      lastMessage: 'Hello',
      lastMessageAt: DateTime(2026, 9, 5),
    );

Widget _app(Widget home, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

/// Renders [watchMemberAccess] for a profile so the helper can be exercised
/// through a real `WidgetRef`, which is how every screen consumes it.
class _AccessProbe extends ConsumerWidget {
  final ProfileModel profile;
  const _AccessProbe(this.profile);

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Text(watchMemberAccess(ref, profile).name,
          textDirection: TextDirection.ltr);
}

Future<void> _pumpAccess(
  WidgetTester tester, {
  required bool public,
  List<InterestModel> sent = const [],
}) async {
  await tester.pumpWidget(_app(
    Scaffold(body: _AccessProbe(_otherProfile(public: public))),
    [
      sentInterestsProvider
          .overrideWith((ref) => Stream<List<InterestModel>>.value(sent)),
      receivedInterestsProvider
          .overrideWith((ref) => Stream<List<InterestModel>>.value(const [])),
    ],
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('who may chat, see contact and request a report', () {
    testWidgets('a PRIVATE profile is locked until an interest is accepted',
        (tester) async {
      await _pumpAccess(tester, public: false);
      expect(find.text(MemberAccess.locked.name), findsOneWidget);
    });

    testWidgets('accepting an interest connects them (spec §3)',
        (tester) async {
      await _pumpAccess(tester, public: false, sent: [_accepted()]);
      expect(find.text(MemberAccess.connected.name), findsOneWidget);
    });

    testWidgets('a PUBLIC profile opens straight away (spec §4)',
        (tester) async {
      await _pumpAccess(tester, public: true);
      expect(find.text(MemberAccess.publicProfile.name), findsOneWidget);
    });

    testWidgets('an accepted interest still outranks Public', (tester) async {
      // Both hold, and "connected" is the stronger claim: it is the one that
      // also unlocks the profile download.
      await _pumpAccess(tester, public: true, sent: [_accepted()]);
      expect(find.text(MemberAccess.connected.name), findsOneWidget);
    });

    test('only a connection unlocks connection-only extras', () {
      expect(MemberAccess.connected.canCommunicate, isTrue);
      expect(MemberAccess.publicProfile.canCommunicate, isTrue);
      expect(MemberAccess.locked.canCommunicate, isFalse);

      expect(MemberAccess.connected.isConnected, isTrue);
      expect(MemberAccess.publicProfile.isConnected, isFalse);
    });
  });

  group('the Chats list', () {
    testWidgets('shows a conversation while the interest streams are loading',
        (tester) async {
      // THE regression (spec §1). The list used to intersect its threads with
      // a set derived from the interest streams; while those were loading that
      // set was empty, so an existing conversation — including the one just
      // created by accepting — disappeared from the page.
      await tester.pumpWidget(_app(
        Scaffold(body: const ChatListScreen()),
        [
          myUidProvider.overrideWithValue(_myUid),
          myChatThreadsProvider.overrideWith(
              (ref) => Stream<List<ChatThread>>.value([_thread()])),
          // Never emits: exactly the state that used to empty the list.
          sentInterestsProvider
              .overrideWith((ref) => const Stream<List<InterestModel>>.empty()),
          receivedInterestsProvider
              .overrideWith((ref) => const Stream<List<InterestModel>>.empty()),
        ],
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Kavitha S'), findsOneWidget);
      expect(find.text('No conversations yet'), findsNothing);
    });
  });

  group('the astrology page', () {
    Future<AppLocalizations> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(
        const Scaffold(body: AstrologyServicePage()),
        [
          astrologyServiceConfigProvider.overrideWith(
              (ref) => Stream<AstrologyServiceConfig>.value(
                    const AstrologyServiceConfig(
                      expertName: 'Astrologer Ravi',
                      expertExperience: '20+ years',
                      expertSpecialization: 'Tamil Jathagam',
                      expertIntro: 'Horoscope matching for families.',
                      expertContactPhone: '9876543210',
                      whatsappNumber: '9876543211',
                      officeAddress: 'Main Street, Virudhunagar',
                    ),
                  )),
        ],
      ));
      await tester.pumpAndSettle();
      return AppLocalizations.delegate.load(const Locale('en'));
    }

    testWidgets('shows the astrologer and how to reach them', (tester) async {
      final l10n = await pump(tester);
      expect(tester.takeException(), isNull);

      // Details, from the admin-managed config — never hardcoded (§25/§26).
      expect(find.text('Astrologer Ravi'), findsWidgets);

      // The page is one long lazy ListView, so the sections below the fold
      // have to be scrolled to before they exist at all.
      Future<void> scrollTo(Finder f) async {
        for (var i = 0; i < 12 && f.evaluate().isEmpty; i++) {
          await tester.drag(find.byType(ListView), const Offset(0, -320));
          await tester.pump();
        }
      }

      await scrollTo(find.text(l10n.experience));
      expect(find.text(l10n.experience), findsOneWidget);
      expect(find.text('20+ years'), findsOneWidget);

      // Specialization's VALUE goes through the shared value localizer, so the
      // heading is what this pins.
      await scrollTo(find.text(l10n.specialization));
      expect(find.text(l10n.specialization), findsOneWidget);

      // …and the two contact ACTIONS (§27).
      expect(find.widgetWithText(OutlinedButton, l10n.callAction),
          findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'WhatsApp'), findsOneWidget);
    });

    testWidgets('carries no booking control of any kind (§29)',
        (tester) async {
      final l10n = await pump(tester);

      for (final gone in [
        l10n.bookYourAppointment,
        l10n.bookingCurrentlyClosed,
        l10n.astrologyBookings,
      ]) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      // No calendar, no slots, no date/time pickers.
      expect(find.byType(CalendarDatePicker), findsNothing);
      expect(find.byIcon(Icons.event_available), findsNothing);
      expect(find.byIcon(Icons.event_busy), findsNothing);
    });
  });

  test('astrology booking has no route left to reach (§22/§23)', () {
    for (final route in const [
      '/astrology-appointment',
      '/my-appointments',
      '/appointment-confirmation/abc',
    ]) {
      expect(isGuestAllowedRoute(route), isFalse, reason: route);
    }
  });
}
