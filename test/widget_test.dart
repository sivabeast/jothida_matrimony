// Unit tests for pure-Dart business rules (no Firebase).
//
// The old subscription-entitlements tests were removed along with the whole
// subscription system: the app is free and the ONE-TIME Horoscope Request fee
// is the only payment in it.

import 'package:flutter_test/flutter_test.dart';
import 'package:jothida_matrimony/core/constants/app_constants.dart';
import 'package:jothida_matrimony/core/data/sample_profiles.dart';
import 'package:jothida_matrimony/core/services/porutham_match.dart';

void main() {
  group('Paid-service pricing', () {
    // The ONE-TIME Horoscope Request fee is the only payment in the app.
    test('Horoscope Compatibility Report costs ₹200', () {
      expect(AppConstants.horoscopeAnalysisFee, 200);
    });
  });

  // The Horoscope Match Result page renders these three numbers and the two
  // lists directly, so the counts it shows can only ever be consistent if the
  // invariant below holds for every pairing.
  group('Porutham result counts', () {
    test('matched + not matched always equals the total, and the lists agree',
        () {
      final profiles = sampleProfiles();
      var compared = 0;
      for (final me in profiles) {
        for (final other in profiles) {
          if (me.id == other.id) continue;
          final r = computePorutham(me, other);
          if (r == null) continue;
          compared++;
          final reason = '${me.id} x ${other.id}';
          expect(r.totalCount, 10, reason: reason);
          expect(r.poruthams.length, r.totalCount, reason: reason);
          expect(r.matching.length, r.matchedCount, reason: reason);
          expect(r.nonMatching.length, r.totalCount - r.matchedCount,
              reason: reason);
          expect(r.matching.length + r.nonMatching.length, r.totalCount,
              reason: reason);
        }
      }
      expect(compared, greaterThan(0),
          reason: 'no sample pairing produced a result to check');
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
