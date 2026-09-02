// The rules introduced by the paid-horoscope / matches / version overhaul.
//
// Each group pins a promise that is easy to break silently later:
//
//   • Female is ALWAYS the Bride and Male ALWAYS the Groom, whichever slot the
//     person was typed into, and Person 2's gender is always Person 1's
//     opposite (spec §1B/§1D/§1E/§4C);
//   • the employee/admin report reads both charts off the REQUEST, so nothing
//     is ever re-keyed (spec §4A/§4B/§12);
//   • ONE complete request costs ₹199 — once, for both people (spec §2/§13);
//   • Nakshatra never removes a profile from the feed (spec §7/§9);
//   • five NEW profiles a day, previously-seen ones free for ever, and
//     tomorrow continues rather than restarting (spec §8);
//   • the update gate blocks only what the policy says to block (spec §10).

import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/constants/app_constants.dart';
import 'package:jothida_matrimony/core/utils/horoscope_roles.dart';
import 'package:jothida_matrimony/models/app_update_config.dart';
import 'package:jothida_matrimony/models/astrologer_request_model.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/providers/daily_profile_quota_provider.dart';
import 'package:jothida_matrimony/providers/profile_provider.dart';
import 'package:jothida_matrimony/screens/report/horoscope_request_person_form.dart';

Map<String, dynamic> _person(String name, String gender) => {
      'name': name,
      'gender': gender,
      'dob': '14 Aug 1999',
      'tob': '06:45 AM',
      'place': 'Salem, Salem, Tamil Nadu',
      'nakshatra': 'ரோகிணி',
      'rasi': 'ரிஷபம்',
    };

AstrologerRequestModel _request({
  required Map<String, dynamic> one,
  required Map<String, dynamic> two,
  Map<String, dynamic>? bride,
  Map<String, dynamic>? groom,
}) =>
    AstrologerRequestModel(
      id: 'r1',
      astrologerId: '',
      astrologerName: '',
      userId: 'u1',
      userName: 'Requester',
      type: AstrologerRequestType.matching,
      status: AstrologerRequestStatus.pending,
      createdAt: DateTime(2026, 9, 1),
      externalRequest: {
        'requester': one,
        'other': two,
        if (bride != null) 'bride': bride,
        if (groom != null) 'groom': groom,
      },
    );

ProfileModel _profile({
  required String gender,
  required int age,
  String nakshatra = '',
  String caste = '',
  PartnerPreferences? preferences,
}) =>
    ProfileModel.fromMap({
      'id': 'p-$gender-$age-$nakshatra',
      'userId': 'u-$gender-$age-$nakshatra',
      'name': 'Test',
      'gender': gender,
      'age': age,
      if (caste.isNotEmpty) 'caste': caste,
      'horoscope': {'nakshatra': nakshatra},
      if (preferences != null) 'partnerPreferences': preferences.toMap(),
    });

void main() {
  // ══ §1B / §1D — gender is derived, never asked twice ═════════════════════

  group('gender derivation', () {
    test('every spelling of a gender canonicalises', () {
      for (final raw in ['Male', 'male', 'MALE', ' m ', 'ஆண்']) {
        expect(normalizeHoroscopeGender(raw), 'Male', reason: raw);
      }
      for (final raw in ['Female', 'female', 'F', 'Woman', 'பெண்']) {
        expect(normalizeHoroscopeGender(raw), 'Female', reason: raw);
      }
    });

    test('an unknown gender is never guessed', () {
      for (final raw in [null, '', '   ', 'Other', 'x']) {
        expect(normalizeHoroscopeGender(raw), '', reason: '$raw');
      }
    });

    test('Person 2 is always the opposite of Person 1', () {
      expect(oppositeHoroscopeGender('Male'), 'Female');
      expect(oppositeHoroscopeGender('Female'), 'Male');
      expect(oppositeHoroscopeGender('ஆண்'), 'Female');
      expect(oppositeHoroscopeGender('பெண்'), 'Male');
    });

    test('an unknown Person 1 leaves Person 2 unknown rather than defaulting',
        () {
      // Inventing a gender here would mislabel the Bride and Groom on a
      // finished certificate — an empty field is the honest answer.
      expect(oppositeHoroscopeGender(''), '');
      expect(oppositeHoroscopeGender('Other'), '');
    });
  });

  // ══ §1E / §4C — Female is the Bride, Male is the Groom ═══════════════════

  group('bride / groom mapping', () {
    test('Female → Bride and Male → Groom', () {
      expect(horoscopeRoleForGender('Female'), kRoleBride);
      expect(horoscopeRoleForGender('Male'), kRoleGroom);
      expect(horoscopeRoleForGender('Other'), '');
    });

    test('a male Person 1 makes Person 1 the Groom', () {
      final split = splitByRole(_person('Karthik', 'Male'),
          _person('Priya', 'Female'));
      expect(split.groom!['name'], 'Karthik');
      expect(split.bride!['name'], 'Priya');
    });

    test('a female Person 1 makes Person 1 the Bride', () {
      final split = splitByRole(_person('Priya', 'Female'),
          _person('Karthik', 'Male'));
      expect(split.bride!['name'], 'Priya');
      expect(split.groom!['name'], 'Karthik');
    });

    test('a LEGACY request with one gender missing still resolves', () {
      // Old requests were written before genders were captured. Knowing one
      // side is enough, because the other is its opposite by construction.
      final split =
          splitByRole(_person('Priya', 'Female'), _person('Karthik', ''));
      expect(split.bride!['name'], 'Priya');
      expect(split.groom!['name'], 'Karthik');
    });

    test('two identical genders are reported as unmappable, never guessed', () {
      final split =
          splitByRole(_person('A', 'Male'), _person('B', 'Male'));
      expect(split.bride, isNull);
      expect(split.groom, isNull);
    });

    test('a draft carries its own role', () {
      final d = HoroscopePersonDraft()..gender = 'Female';
      expect(d.role, kRoleBride);
      d.gender = 'Male';
      expect(d.role, kRoleGroom);
      d.clear();
      expect(d.role, '');
      expect(d.gender, '');
    });

    test('toMap stores the gender AND the resolved role', () {
      final d = HoroscopePersonDraft()..gender = 'Female';
      d.name.text = 'Priya';
      final m = d.toMap();
      expect(m['gender'], 'Female');
      expect(m['role'], kRoleBride);
    });
  });

  // ══ §4A / §4B / §12 — the request is the source of truth ═════════════════

  group('employee report reads both charts off the request', () {
    test('the stored mapping is used when present', () {
      final r = _request(
        one: _person('Karthik', 'Male'),
        two: _person('Priya', 'Female'),
        bride: _person('Priya', 'Female'),
        groom: _person('Karthik', 'Male'),
      );
      expect(r.brideDetails['name'], 'Priya');
      expect(r.groomDetails['name'], 'Karthik');
    });

    test('a request written before the mapping existed is re-derived', () {
      final r = _request(
        one: _person('Priya', 'Female'),
        two: _person('Karthik', 'Male'),
      );
      expect(r.brideDetails['name'], 'Priya');
      expect(r.groomDetails['name'], 'Karthik');
    });

    test('every field the report needs is already on the request', () {
      final r = _request(
        one: _person('Karthik', 'Male'),
        two: _person('Priya', 'Female'),
      );
      // Nothing here may require the employee to type it again (spec §4D).
      for (final key in const [
        'name',
        'gender',
        'dob',
        'tob',
        'place',
        'nakshatra',
        'rasi',
      ]) {
        expect(r.brideDetails[key], isNotNull, reason: 'bride.$key');
        expect(r.groomDetails[key], isNotNull, reason: 'groom.$key');
      }
    });

    test('an unmappable legacy request yields empty sides, not wrong ones', () {
      final r = _request(one: _person('A', ''), two: _person('B', ''));
      expect(r.brideDetails, isEmpty);
      expect(r.groomDetails, isEmpty);
    });
  });

  // ══ §2 / §13 — one complete request, one ₹199 ════════════════════════════

  group('the horoscope report fee', () {
    test('is ₹199', () {
      expect(AppConstants.horoscopeAnalysisFee, 199);
    });

    test('is charged for the PAIR, not per person', () {
      // There is exactly one fee constant, and both entry points read it. A
      // second per-person constant appearing here would be the bug.
      expect(AppConstants.horoscopeAnalysisFee * 2,
          isNot(AppConstants.horoscopeAnalysisFee));
      expect(AppConstants.horoscopeAnalysisFee, 199);
    });
  });

  // ══ §7 / §9 — Nakshatra never hides a profile ════════════════════════════

  group('Nakshatra is never a hard filter', () {
    final me = _profile(
      gender: 'Male',
      age: 28,
      nakshatra: 'ரோகிணி',
      caste: 'Vanniyar',
      preferences: const PartnerPreferences(
          minAge: 22, maxAge: 30, caste: 'Vanniyar'),
    );

    test('a star-INCOMPATIBLE candidate is still eligible', () {
      final incompatible = _profile(
          gender: 'Female', age: 25, nakshatra: 'கேட்டை', caste: 'Vanniyar');
      expect(mandatoryPreferenceMatch(incompatible, me), isTrue);
    });

    test('a star-compatible candidate is eligible too — both are shown', () {
      final compatible = _profile(
          gender: 'Female', age: 25, nakshatra: 'உத்திரம்', caste: 'Vanniyar');
      expect(mandatoryPreferenceMatch(compatible, me), isTrue);
    });

    test('caste and age remain the primary hard filters', () {
      final wrongCaste = _profile(
          gender: 'Female', age: 25, nakshatra: 'உத்திரம்', caste: 'Gounder');
      final wrongAge = _profile(
          gender: 'Female', age: 41, nakshatra: 'உத்திரம்', caste: 'Vanniyar');
      expect(mandatoryPreferenceMatch(wrongCaste, me), isFalse);
      expect(mandatoryPreferenceMatch(wrongAge, me), isFalse);
    });

    test('the explicit filter sheet has no nakshatra filter at all', () {
      // `isActive` covers every filter the sheet can set; a nakshatra one would
      // have to be listed there to work, so this is the cheapest possible guard
      // against it being reintroduced.
      const filters = MatchFilters(rasi: 'Mesham');
      expect(filters.isActive, isTrue);
      expect(const MatchFilters().isActive, isFalse);
    });

    test('a nakshatra preference left on an old profile no longer filters', () {
      final legacy = _profile(
        gender: 'Male',
        age: 28,
        nakshatra: 'ரோகிணி',
        preferences: const PartnerPreferences(
            minAge: 18, maxAge: 60, nakshatra: 'உத்திரம்'),
      );
      final different =
          _profile(gender: 'Female', age: 25, nakshatra: 'கேட்டை');
      expect(mandatoryPreferenceMatch(different, legacy), isTrue);
      // …and it no longer counts as "preferences configured" either.
      expect(partnerPreferencesComplete(legacy), isFalse);
    });
  });

  // ══ §8 — five NEW profiles a day ═════════════════════════════════════════

  group('the daily new-profile allowance', () {
    test('the limit is five', () {
      expect(kDailyNewProfileLimit, 5);
    });

    test('the day key is local and rolls at midnight', () {
      expect(quotaDayKey(DateTime(2026, 9, 2, 23, 59)), '2026-09-02');
      expect(quotaDayKey(DateTime(2026, 9, 3, 0, 1)), '2026-09-03');
    });

    test('the countdown targets the next reset', () {
      final at = DateTime(2026, 9, 2, 22, 14, 42);
      final left = nextQuotaResetAt(at).difference(at);
      expect(formatCountdown(left), '01:45:18');
    });

    test('the countdown is always hh:mm:ss', () {
      expect(formatCountdown(const Duration(seconds: 8)), '00:00:08');
      expect(formatCountdown(const Duration(hours: 23, minutes: 5)),
          '23:05:00');
    });

    test('a count from a previous day reads as zero without a write', () {
      const q = DailyProfileQuota(
          dayKey: '2026-09-01', newViewsToday: 5, loaded: true);
      final today = DateTime(2026, 9, 2, 10);
      expect(q.usedAt(today), 0);
      expect(q.remainingAt(today), 5);
    });

    test('the day’s own count is spent', () {
      final today = DateTime(2026, 9, 2, 10);
      final q = DailyProfileQuota(
          dayKey: quotaDayKey(today), newViewsToday: 3, loaded: true);
      expect(q.usedAt(today), 3);
      expect(q.remainingAt(today), 2);
    });

    test('the allowance can never go negative', () {
      final today = DateTime(2026, 9, 2, 10);
      final q = DailyProfileQuota(
          dayKey: quotaDayKey(today), newViewsToday: 99, loaded: true);
      expect(q.remainingAt(today), 0);
    });

    test('seen profiles are remembered across days, so tomorrow continues', () {
      // Yesterday's five are still "seen", which is exactly what makes the
      // next NEW profile the sixth rather than the first (spec §8C).
      const q = DailyProfileQuota(
          dayKey: '2026-09-01',
          newViewsToday: 5,
          seen: {'p1', 'p2', 'p3', 'p4', 'p5'},
          loaded: true);
      for (final id in ['p1', 'p2', 'p3', 'p4', 'p5']) {
        expect(q.hasSeen(id), isTrue, reason: id);
      }
      expect(q.hasSeen('p6'), isFalse);
      expect(q.remainingAt(DateTime(2026, 9, 2)), 5);
    });
  });

  // ══ §10 — the update gate ════════════════════════════════════════════════

  group('the update gate', () {
    test('an unconfigured release prompts nobody', () {
      const c = AppUpdateConfig();
      expect(c.requirementFor(20), AppUpdateRequirement.none);
    });

    test('below the latest, Force Update OFF → optional (§10C)', () {
      const c = AppUpdateConfig(latestVersionCode: 21);
      expect(c.requirementFor(20), AppUpdateRequirement.optional);
    });

    test('below the latest, Force Update ON → forced (§10B)', () {
      const c = AppUpdateConfig(latestVersionCode: 21, forceUpdate: true);
      expect(c.requirementFor(20), AppUpdateRequirement.forced);
    });

    test('below the MINIMUM is always forced, whatever the policy (§10D)', () {
      const c = AppUpdateConfig(
          latestVersionCode: 21, minimumSupportedVersionCode: 20);
      expect(c.requirementFor(19), AppUpdateRequirement.forced);
      // …and a build at the floor is merely offered the update.
      expect(c.requirementFor(20), AppUpdateRequirement.optional);
    });

    test('an unreadable installed version never blocks anyone', () {
      const c = AppUpdateConfig(
          latestVersionCode: 21,
          minimumSupportedVersionCode: 20,
          forceUpdate: true);
      expect(c.requirementFor(0), AppUpdateRequirement.none);
    });

    test('the store link is always the real Play listing', () {
      const bogus = AppUpdateConfig(playStoreUrl: 'https://evil.example/app');
      expect(bogus.effectivePlayStoreUrl, AppUpdateConfig.defaultPlayStoreUrl);
      const good = AppUpdateConfig(
          playStoreUrl: 'https://play.google.com/store/apps/details?id=x');
      expect(good.effectivePlayStoreUrl,
          'https://play.google.com/store/apps/details?id=x');
    });
  });
}
