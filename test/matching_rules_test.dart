// The Matches page's matching + browsing-resume rules, as pure functions.
//
// These pin the behaviour the spec calls out explicitly:
//   • opposite-gender only, whatever casing/language the stored value uses;
//   • the default age windows (male 25 → 18–25 · female 21 → 21–31);
//   • browsing RESUMES where the user left off, and when every profile has
//     been seen it stays on the LAST one instead of restarting at profile 1.

import 'package:flutter_test/flutter_test.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/providers/matches_prefs_provider.dart';
import 'package:jothida_matrimony/providers/profile_provider.dart';

ProfileModel _profile({
  required String gender,
  required int age,
  PartnerPreferences? preferences,
}) =>
    ProfileModel.fromMap({
      'id': 'p-$gender-$age',
      'userId': 'u-$gender-$age',
      'name': 'Test',
      'gender': gender,
      'age': age,
      if (preferences != null)
        'partnerPreferences': preferences.toMap(),
    });

void main() {
  group('gender normalisation (rule 1: never the same gender)', () {
    test('every stored spelling of male collapses to one token', () {
      for (final raw in ['Male', 'male', 'MALE', ' male ', 'M', 'ஆண்']) {
        expect(normalizedGender(raw), 'm', reason: raw);
      }
    });

    test('every stored spelling of female collapses to one token', () {
      for (final raw in ['Female', 'female', 'FEMALE', 'F', 'Woman', 'பெண்']) {
        expect(normalizedGender(raw), 'f', reason: raw);
      }
    });

    test('an unknown or missing value is never guessed', () {
      for (final raw in [null, '', '  ', 'Other', 'x']) {
        expect(normalizedGender(raw), '', reason: '$raw');
      }
    });
  });

  group('default age windows (rule 2)', () {
    test('a 25-year-old man is shown women aged 18–25', () {
      final range = resolveAgeRange(_profile(gender: 'Male', age: 25));
      expect(range.minAge, 18);
      expect(range.maxAge, 25);
    });

    test('a 21-year-old woman is shown men aged 21–31', () {
      final range = resolveAgeRange(_profile(gender: 'Female', age: 21));
      expect(range.minAge, 21);
      expect(range.maxAge, 31);
    });

    test('the lower bound never drops below 18', () {
      final range = resolveAgeRange(_profile(gender: 'Male', age: 22));
      expect(range.minAge, 18);
      expect(range.maxAge, 22);
    });

    test('an age range the member actually chose wins (rule 3)', () {
      final range = resolveAgeRange(_profile(
        gender: 'Male',
        age: 25,
        preferences: const PartnerPreferences(minAge: 24, maxAge: 30),
      ));
      expect(range.minAge, 24);
      expect(range.maxAge, 30);
    });

    test('lowercase gender still gets the default window', () {
      // Regression: the old rule compared against the literal 'Male'/'Female',
      // so a lowercased value silently fell back to the member's raw 18–40.
      final range = resolveAgeRange(_profile(gender: 'male', age: 30));
      expect(range.minAge, 20);
      expect(range.maxAge, 30);
    });
  });

  group('browsing resume (P5)', () {
    const ids = ['a', 'b', 'c', 'd', 'e'];

    test('a first-ever session starts at profile 1', () {
      expect(
        resolveResumeIndex(profileIds: ids, viewed: const {}),
        0,
      );
    });

    test('reopening continues from the exact profile last shown', () {
      expect(
        resolveResumeIndex(
          profileIds: ids,
          viewed: const {'a', 'b', 'c'},
          lastViewed: 'c',
        ),
        2,
      );
    });

    test('swiping BACK moves the resume anchor back too', () {
      expect(
        resolveResumeIndex(
          profileIds: ids,
          viewed: const {'a', 'b', 'c', 'd'},
          lastViewed: 'b',
        ),
        1,
      );
    });

    test('without an anchor it resumes at the first unseen profile', () {
      expect(
        resolveResumeIndex(profileIds: ids, viewed: const {'a', 'b'}),
        2,
      );
    });

    test('a stale anchor falls back to the first unseen profile', () {
      // The last-viewed profile went inactive / was filtered out.
      expect(
        resolveResumeIndex(
          profileIds: ids,
          viewed: const {'a', 'b'},
          lastViewed: 'zz',
        ),
        2,
      );
    });

    test('when every profile has been viewed it STAYS on the last one', () {
      // Spec: "If 5 matching profiles exist and the user has viewed all 5 —
      // keep showing the last profile, allow Previous Swipe." Never restart at
      // profile 1, never fall through to an empty state.
      expect(
        resolveResumeIndex(profileIds: ids, viewed: ids.toSet()),
        ids.length - 1,
      );
    });

    test('new matches merged in do not move the user', () {
      // 'c' is where the user is; 'x' ranked in above them.
      expect(
        resolveResumeIndex(
          profileIds: const ['x', 'a', 'b', 'c', 'd', 'e'],
          viewed: const {'a', 'b', 'c'},
          lastViewed: 'c',
        ),
        3,
      );
    });

    test('an empty feed is index-safe', () {
      expect(
        resolveResumeIndex(profileIds: const [], viewed: const {}),
        0,
      );
    });
  });
}
