// Unit tests for pure-Dart business rules (no Firebase).
//
// The old subscription-entitlements tests were removed along with the whole
// subscription system: every matrimony feature is free and only the two
// astrology services are paid (per booking).

import 'package:flutter_test/flutter_test.dart';
import 'package:jothida_matrimony/core/constants/app_constants.dart';
import 'package:jothida_matrimony/core/services/porutham_match.dart';

void main() {
  group('Paid-service pricing', () {
    test('Horoscope Compatibility Report costs ₹199', () {
      expect(AppConstants.horoscopeAnalysisFee, 199);
    });

    test('Astrologer appointment booking costs ₹20', () {
      expect(AppConstants.appointmentBookingFee, 20);
    });
  });

  group('Star (nakshatra) compatibility', () {
    test('star porutham count is within 0..7', () {
      for (var bride = 1; bride <= 27; bride++) {
        for (var groom = 1; groom <= 27; groom++) {
          final n = matchedStarPoruthams(brideStar: bride, groomStar: groom);
          expect(n, inInclusiveRange(0, 7),
              reason: 'bride=$bride groom=$groom');
        }
      }
    });

    test('same-rajju pairs are never compatible', () {
      // Stars 1 and 9 share the Pada rajju group → incompatible by rule.
      expect(isStarPairCompatible(brideStar: 1, groomStar: 9), isFalse);
    });

    test('every star has at least one compatible partner star', () {
      for (var star = 1; star <= 27; star++) {
        expect(compatibleStarsFor(myStar: star, iAmFemale: true), isNotEmpty,
            reason: 'bride star $star');
        expect(compatibleStarsFor(myStar: star, iAmFemale: false), isNotEmpty,
            reason: 'groom star $star');
      }
    });

    test('compatibleStarsFor mirrors isStarPairCompatible', () {
      const myStar = 4; // Rohini
      final stars = compatibleStarsFor(myStar: myStar, iAmFemale: true);
      for (final s in stars) {
        expect(isStarPairCompatible(brideStar: myStar, groomStar: s), isTrue);
      }
    });
  });

  group('Nakshatra master lists', () {
    test('Tamil and English lists stay index-aligned (27 stars)', () {
      expect(AppConstants.nakshatraList.length, 27);
      expect(AppConstants.nakshatraEnList.length, 27);
    });
  });
}
