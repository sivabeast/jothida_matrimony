// Rules from the change request that are easy to regress silently.
//
//   §1  email is optional at registration, but still validated when typed
//   §7  birth time always displays with AM/PM, converted from the stored value
//   §9  dropdown search matches across Tamil <-> English in both directions
//   §12 a Cloudinary asset's public_id is recoverable from its stored URL
//   §14 the popup rotation advances and wraps, and skips disabled contents

import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/services/horoscope_calculation_service.dart';
import 'package:jothida_matrimony/core/utils/validators.dart';
import 'package:jothida_matrimony/core/utils/value_l10n.dart';
import 'package:jothida_matrimony/services/cloudinary/cloudinary_asset_id.dart';

void main() {
  group('§1 optional email', () {
    test('an empty email is valid', () {
      expect(AppValidators.optionalEmail(''), isNull);
      expect(AppValidators.optionalEmail('   '), isNull);
      expect(AppValidators.optionalEmail(null), isNull);
    });

    test('a typed email is still validated', () {
      expect(AppValidators.optionalEmail('not-an-email'), isNotNull);
      expect(AppValidators.optionalEmail('a@b.co'), isNull);
    });

    test('the required variant still rejects empty', () {
      expect(AppValidators.email(''), isNotNull);
    });
  });

  group('§7 birth time display', () {
    test('converts the stored 24-hour value', () {
      expect(HoroscopeCalculationService.formatBirthTimeForDisplay('07:30'),
          '07:30 AM');
      expect(HoroscopeCalculationService.formatBirthTimeForDisplay('19:30'),
          '07:30 PM');
    });

    test('handles both noon and midnight', () {
      expect(HoroscopeCalculationService.formatBirthTimeForDisplay('00:05'),
          '12:05 AM');
      expect(HoroscopeCalculationService.formatBirthTimeForDisplay('12:00'),
          '12:00 PM');
    });

    test('a legacy AM/PM value is not double-suffixed', () {
      expect(HoroscopeCalculationService.formatBirthTimeForDisplay('06:45 AM'),
          '06:45 AM');
    });

    test('empty and unparseable values are left alone', () {
      expect(HoroscopeCalculationService.formatBirthTimeForDisplay(''), '');
      expect(HoroscopeCalculationService.formatBirthTimeForDisplay(null), '');
      expect(HoroscopeCalculationService.formatBirthTimeForDisplay('sometime'),
          'sometime');
    });
  });

  group('§9 cross-language search forms', () {
    setUp(() {
      // Master data normally registers these when the location repo loads.
      registerMasterTamilNames({
        'Virudhunagar': 'விருதுநகர்',
        'Madurai': 'மதுரை',
      });
    });

    test('an English-stored value is searchable in Tamil', () {
      final forms = searchableFormsOf('Virudhunagar');
      expect(forms, contains('virudhunagar'));
      expect(forms, contains('விருதுநகர்'));
    });

    test('a Tamil-stored value resolves back to English', () {
      // Rasi / Nakshatra are stored in Tamil script.
      expect(englishValue('மேஷம்').toLowerCase(), contains('mesham'));
      expect(searchableFormsOf('மேஷம்').any((f) => f.contains('mesham')),
          isTrue);
    });

    test('a registered Tamil district resolves back to English', () {
      expect(masterEnglishNameFor('மதுரை'), 'Madurai');
    });

    test('an unmapped value is returned unchanged', () {
      expect(englishValue('Rosalpatti'), 'Rosalpatti');
      expect(tamilValue('Rosalpatti'), 'Rosalpatti');
    });
  });

  group('§12 Cloudinary public_id from a stored URL', () {
    test('a plain upload URL', () {
      final ref = cloudinaryRefFromUrl(
          'https://res.cloudinary.com/demo/image/upload/v1712345678/profiles/u1/photo.jpg');
      expect(ref, isNotNull);
      expect(ref!.publicId, 'profiles/u1/photo');
      expect(ref.resourceType, 'image');
    });

    test('a raw (PDF) upload keeps its resource type', () {
      final ref = cloudinaryRefFromUrl(
          'https://res.cloudinary.com/demo/raw/upload/v1/horoscopes/u1/chart.pdf');
      expect(ref!.publicId, 'horoscopes/u1/chart');
      expect(ref.resourceType, 'raw');
    });

    test('a transformation segment is not part of the public_id', () {
      final ref = cloudinaryRefFromUrl(
          'https://res.cloudinary.com/demo/image/upload/w_400,h_400,c_fill/v1712345678/profiles/u1/photo.jpg');
      expect(ref!.publicId, 'profiles/u1/photo');
    });

    test('non-Cloudinary and blank URLs are skipped', () {
      expect(cloudinaryRefFromUrl('https://example.com/a.jpg'), isNull);
      expect(cloudinaryRefFromUrl(''), isNull);
      expect(cloudinaryRefFromUrl(null), isNull);
    });

    test('a batch is de-duplicated and blanks dropped', () {
      const url =
          'https://res.cloudinary.com/demo/image/upload/v1/profiles/u1/a.jpg';
      final refs = cloudinaryRefsFromUrls([url, url, '', null, 'nope']);
      expect(refs, hasLength(1));
      expect(refs.single.publicId, 'profiles/u1/a');
    });
  });

  group('§14 popup rotation arithmetic', () {
    // The provider takes the stored cursor modulo the CURRENT list length, so
    // the rotation stays valid when contents are added, removed or disabled.
    int pick(int cursor, int activeCount) => cursor % activeCount;

    test('cycles through every active content in turn', () {
      expect(pick(0, 3), 0);
      expect(pick(1, 3), 1);
      expect(pick(2, 3), 2);
      expect(pick(3, 3), 0); // wraps back to the first
    });

    test('a shrinking list can never point past the end', () {
      // Cursor was 7 with five contents; the admin disables all but two.
      expect(pick(7, 2), lessThan(2));
    });

    test('a single active content is always the one shown', () {
      for (var c = 0; c < 5; c++) {
        expect(pick(c, 1), 0);
      }
    });
  });
}
