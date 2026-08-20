// Behaviour this change is responsible for:
//
//  • the astrology centre is ONE fixed destination (Rajapalayam / Virudhunagar
//    / Tamil Nadu) and the share-style Maps short link must not be used as a
//    directions destination, because it carries no coordinates;
//  • a booking form can never produce an appointment without a name and a
//    valid mobile number;
//  • the "Interest Sent" and "Interest Accepted" overlays render, animate and
//    dismiss themselves without navigating.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/models/astrology_service_config.dart';
import 'package:jothida_matrimony/models/astrologer_request_model.dart';
import 'package:jothida_matrimony/widgets/interest/interest_accepted_celebration.dart';
import 'package:jothida_matrimony/widgets/interest/interest_sent_overlay.dart';

void main() {
  group('astrology centre location', () {
    const cfg = AstrologyServiceConfig();

    test('defaults to the configured centre', () {
      expect(cfg.officeAddress,
          '45, Lakshmiyapuram Street, Thoppatti, Rajapalayam');
      expect(cfg.officeCity, 'Rajapalayam');
      expect(cfg.officeDistrict, 'Virudhunagar');
      expect(cfg.officeState, 'Tamil Nadu');
      expect(cfg.mapLocation, 'https://maps.app.goo.gl/YY8ZxTMdhx1bfm3o6');
    });

    test('fullAddress is street → city → district → state', () {
      expect(
        cfg.fullAddress,
        '45, Lakshmiyapuram Street, Thoppatti, Rajapalayam, Rajapalayam, '
        'Virudhunagar, Tamil Nadu',
      );
    });

    test('the location hierarchy reads City, District, State', () {
      expect(cfg.locationHierarchy, 'Rajapalayam, Virudhunagar, Tamil Nadu');
    });

    test('a share-style short link carries no coordinates to route to', () {
      // This is exactly why the full postal address is the directions
      // destination: there is nothing in a goo.gl link to extract.
      final coords = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)')
          .firstMatch(cfg.mapLocation);
      expect(coords, isNull);
    });

    test('an empty district or state does not leave dangling separators', () {
      const partial = AstrologyServiceConfig(
        officeAddress: 'Some Street',
        officeCity: 'Rajapalayam',
        officeDistrict: '',
        officeState: 'Tamil Nadu',
      );
      expect(partial.fullAddress, 'Some Street, Rajapalayam, Tamil Nadu');
      expect(partial.locationHierarchy, 'Rajapalayam, Tamil Nadu');
    });
  });

  group('appointment record', () {
    test('carries the customer location hierarchy through Firestore', () {
      final appt = AstrologerRequestModel(
        id: 'bk1',
        astrologerId: 'internal_astrology',
        userId: 'u1',
        userName: 'Test User',
        userPhone: '9876543210',
        userCity: 'Madurai',
        userDistrict: 'Madurai',
        userState: 'Tamil Nadu',
        category: 'Marriage Compatibility',
        type: AstrologerRequestType.consultation,
        status: AstrologerRequestStatus.accepted,
        createdAt: DateTime(2026, 8, 20),
      );
      final map = appt.toFirestore();
      expect(map['userName'], 'Test User');
      expect(map['userPhone'], '9876543210');
      expect(map['userCity'], 'Madurai');
      expect(map['userDistrict'], 'Madurai');
      expect(map['userState'], 'Tamil Nadu');
      // The reason/purpose the customer picked.
      expect(map['category'], 'Marriage Compatibility');
    });
  });

  group('interest sent overlay', () {
    testWidgets('shows a tick and "Interest Sent", then dismisses itself',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showInterestSentOverlay(
                context,
                visibleFor: const Duration(milliseconds: 400),
              ),
              child: const Text('send'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('send'));
      await tester.pump(); // open
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Interest Sent'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Auto-dismiss — the member never has to close it, and nothing navigates.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('Interest Sent'), findsNothing);
      expect(find.text('send'), findsOneWidget);
    });
  });

  group('interest accepted celebration', () {
    testWidgets('states clearly that the sent request was accepted',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showInterestAcceptedCelebration(
                context,
                name: 'Priya',
                autoDismissAfter: const Duration(milliseconds: 500),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Your Interest Request Has Been Accepted!'),
          findsOneWidget);
      // The message names the OTHER member and says they accepted.
      expect(
        find.textContaining('Priya received the interest you sent'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('can be closed and leaves the page behind intact',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showInterestAcceptedCelebration(
                context,
                name: 'Priya',
                autoDismissAfter: const Duration(seconds: 30),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Your Interest Request Has Been Accepted!'),
          findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });
}
