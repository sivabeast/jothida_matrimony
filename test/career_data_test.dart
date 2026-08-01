import 'package:flutter_test/flutter_test.dart';
import 'package:jothida_matrimony/core/constants/app_constants.dart';
import 'package:jothida_matrimony/core/data/career_data.dart';

/// Guards the Education / Occupation hierarchy (§5–§7).
///
/// The hierarchy is a GROUPING of the website's flat catalogues, not a new set
/// of values: every leaf must come from the website list, and no website entry
/// may be lost, otherwise the app and the website would start storing different
/// strings and matching would silently drift.
void main() {
  group('Education hierarchy', () {
    test('every degree in the hierarchy exists in the website catalogue', () {
      final catalogue =
          AppConstants.educationList.map((e) => e.toLowerCase()).toSet();
      for (final entry in CareerData.coursesByLevel.entries) {
        for (final course in entry.value) {
          expect(catalogue, contains(course.toLowerCase()),
              reason: '"$course" (level ${entry.key}) is not in '
                  'AppConstants.educationList');
        }
      }
    });

    test('every website qualification is placed in exactly one level', () {
      final placements = <String, List<String>>{};
      for (final entry in CareerData.coursesByLevel.entries) {
        for (final course in entry.value) {
          placements.putIfAbsent(course.toLowerCase(), () => []).add(entry.key);
        }
      }
      for (final degree in AppConstants.educationList) {
        final levels = placements[degree.toLowerCase()] ?? const [];
        expect(levels.length, 1,
            reason: '"$degree" is in ${levels.length} levels ($levels); '
                'it must be in exactly one');
      }
    });

    test('levelForDegree round-trips every degree', () {
      for (final entry in CareerData.coursesByLevel.entries) {
        for (final course in entry.value) {
          expect(CareerData.levelForDegree(course), entry.key);
        }
      }
      expect(CareerData.levelForDegree('Totally Made Up Degree'), isNull);
      expect(CareerData.levelForDegree(''), isNull);
      expect(CareerData.levelForDegree(null), isNull);
    });

    test('single-qualification levels auto-fill and hide the course picker',
        () {
      for (final level in [
        CareerData.level10,
        CareerData.level12,
        CareerData.levelIti,
      ]) {
        expect(CareerData.levelHasCourses(level), isFalse,
            reason: '$level has one qualification, so no picker is shown');
        expect(CareerData.defaultCourseFor(level), isNotNull);
      }
      for (final level in [
        CareerData.levelBelow10,
        CareerData.levelDiploma,
        CareerData.levelUg,
        CareerData.levelPg,
        CareerData.levelDoctorate,
      ]) {
        expect(CareerData.levelHasCourses(level), isTrue);
        expect(CareerData.defaultCourseFor(level), isNull);
      }
    });
  });

  group('Occupation hierarchy', () {
    test('every occupation in the hierarchy exists in the website catalogue',
        () {
      final catalogue =
          AppConstants.occupationList.map((e) => e.toLowerCase()).toSet();
      final buckets = {
        'government': CareerData.governmentOccupations,
        'private': CareerData.privateOccupations,
        'business': CareerData.businessOccupations,
        'profession': CareerData.professionOccupations,
      };
      buckets.forEach((name, list) {
        for (final occupation in list) {
          expect(catalogue, contains(occupation.toLowerCase()),
              reason: '"$occupation" ($name) is not in '
                  'AppConstants.occupationList');
        }
      });
    });

    test('each bucket is sorted and free of duplicates', () {
      final buckets = [
        CareerData.governmentOccupations,
        CareerData.privateOccupations,
        CareerData.businessOccupations,
        CareerData.professionOccupations,
      ];
      for (final list in buckets) {
        expect(list.toSet().length, list.length,
            reason: 'duplicate entry in $list');
        final sorted = [...list]
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        expect(list, sorted, reason: 'bucket must stay alphabetically sorted');
      }
    });

    test('only Employed / Self Employed ask for a sector + occupation', () {
      expect(CareerData.statusHasOccupation(CareerData.statusEmployed), isTrue);
      expect(
          CareerData.statusHasOccupation(CareerData.statusSelfEmployed), isTrue);
      for (final status in [
        CareerData.statusStudent,
        CareerData.statusJobSeeker,
        CareerData.statusHomemaker,
        CareerData.statusRetired,
      ]) {
        expect(CareerData.statusHasOccupation(status), isFalse);
        expect(CareerData.sectorsFor(status), isEmpty);
        expect(CareerData.occupationsFor(status: status, sector: 'Private'),
            isEmpty);
      }
    });

    test('sectors match the spec wording', () {
      expect(CareerData.sectorsFor(CareerData.statusEmployed),
          ['Government', 'Private']);
      expect(CareerData.sectorsFor(CareerData.statusSelfEmployed),
          ['Business', 'Profession']);
    });

    test('a non-working status still stores a valid website occupation', () {
      final catalogue =
          AppConstants.occupationList.map((e) => e.toLowerCase()).toSet();
      final expected = {
        CareerData.statusStudent: 'Student',
        CareerData.statusJobSeeker: 'Not Working',
        CareerData.statusHomemaker: 'Homemaker',
        CareerData.statusRetired: 'Retired',
      };
      expected.forEach((status, occupation) {
        final stored = CareerData.occupationValueFor(status, 'Ignored');
        expect(stored, occupation);
        expect(catalogue, contains(stored.toLowerCase()));
      });
      // Employed / Self Employed keep whatever the member picked.
      expect(
          CareerData.occupationValueFor(CareerData.statusEmployed, 'Nurse'),
          'Nurse');
    });

    test('a legacy profile recovers its status and sector', () {
      expect(CareerData.statusForOccupation('Homemaker'),
          CareerData.statusHomemaker);
      expect(CareerData.statusForOccupation('Not Working'),
          CareerData.statusJobSeeker);
      expect(CareerData.statusForOccupation('Student'),
          CareerData.statusStudent);
      expect(CareerData.statusForOccupation('Software Engineer'),
          CareerData.statusEmployed);
      expect(
          CareerData.statusForOccupation('Doctor', employmentType: 'Business'),
          CareerData.statusSelfEmployed);
      expect(CareerData.statusForOccupation(''), isNull);

      // The legacy employmentType wins when it names a sector.
      expect(
          CareerData.sectorForOccupation('Nurse', employmentType: 'Government'),
          CareerData.sectorGovernment);
      // The legacy 'Self Employed' employmentType maps onto Business.
      expect(
          CareerData.sectorForOccupation('Shop Owner',
              employmentType: 'Self Employed'),
          CareerData.sectorBusiness);
      // Otherwise it is inferred from the buckets.
      expect(CareerData.sectorForOccupation('Police Officer'),
          CareerData.sectorGovernment);
      expect(CareerData.sectorForOccupation('Software Engineer'),
          CareerData.sectorPrivate);
    });
  });

  group('Flat lists kept for filters', () {
    test('allDegrees covers the whole website catalogue', () {
      final all = CareerData.allDegrees.map((e) => e.toLowerCase()).toSet();
      for (final degree in AppConstants.educationList) {
        expect(all, contains(degree.toLowerCase()));
      }
    });

    test('allOccupations covers the whole website catalogue', () {
      final all = CareerData.allOccupations.map((e) => e.toLowerCase()).toSet();
      for (final occupation in AppConstants.occupationList) {
        expect(all, contains(occupation.toLowerCase()));
      }
    });
  });
}
