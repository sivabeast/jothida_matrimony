import 'package:flutter_test/flutter_test.dart';
import 'package:jothida_matrimony/core/data/education_catalog.dart';
import 'package:jothida_matrimony/core/data/location_catalog.dart';
import 'package:jothida_matrimony/core/data/master_option.dart';
import 'package:jothida_matrimony/core/data/occupation_catalog.dart';
import 'package:jothida_matrimony/models/profile_model.dart';

/// Covers the conditional flows the Profile Creation spec introduced: which
/// fields appear for which choice (§3, §5), multi-degree display (§4),
/// education-aware occupation ordering (§6) and bilingual search (§9).
void main() {
  group('§3 education level gating', () {
    test('schooling levels offer no degree picker', () {
      for (final level in [
        EducationCatalog.levelBelow10,
        EducationCatalog.level10,
        EducationCatalog.level12,
      ]) {
        expect(EducationCatalog.levelHasDegrees(level), isFalse,
            reason: '$level must not ask for a degree');
        expect(EducationCatalog.degreesFor(level), isEmpty);
      }
    });

    test('everything from ITI upwards does offer degrees', () {
      for (final level in [
        EducationCatalog.levelIti,
        EducationCatalog.levelDiploma,
        EducationCatalog.levelUg,
        EducationCatalog.levelPg,
        EducationCatalog.levelMPhil,
        EducationCatalog.levelPhd,
        EducationCatalog.levelProfessional,
      ]) {
        expect(EducationCatalog.levelHasDegrees(level), isTrue, reason: level);
        expect(EducationCatalog.degreesFor(level), isNotEmpty, reason: level);
      }
    });

    test('a schooling level fills its own qualification in', () {
      expect(EducationCatalog.implicitDegreeFor(EducationCatalog.level10),
          'SSLC');
      expect(EducationCatalog.implicitDegreeFor(EducationCatalog.level12), 'HSC');
      expect(EducationCatalog.implicitDegreeFor(EducationCatalog.levelUg), isNull);
    });

    test('the retired Doctorate level still resolves', () {
      expect(EducationCatalog.canonicalLevel('Doctorate'),
          EducationCatalog.levelPhd);
      expect(EducationCatalog.levelHasDegrees('Doctorate'), isTrue);
    });

    test('every degree maps back to exactly one level', () {
      for (final entry in EducationCatalog.degreesByLevel.entries) {
        for (final degree in entry.value) {
          expect(EducationCatalog.levelForDegree(degree.en), entry.key,
              reason: degree.en);
        }
      }
      expect(EducationCatalog.levelForDegree('Totally Made Up Degree'), isNull);
      expect(EducationCatalog.levelForDegree(''), isNull);
    });

    test('degree ids and canonical values are unique', () {
      final ids = <String>{};
      final values = <String>{};
      for (final d in EducationCatalog.allDegrees) {
        expect(ids.add(d.id), isTrue, reason: 'duplicate id ${d.id}');
        expect(values.add(d.en.toLowerCase()), isTrue,
            reason: 'duplicate value ${d.en}');
      }
    });
  });

  group('§4 multiple degrees', () {
    // fromMap defaults every field, so a test only states what it cares about.
    ProfileModel profile({
      List<String> degrees = const [],
      List<String> display = const [],
      String education = '',
    }) =>
        ProfileModel.fromMap({
          'id': 'p',
          'userId': 'u',
          'fullName': 'Test',
          'education': education,
          'degrees': degrees,
          'displayDegrees': display,
        });

    test('one or two degrees are both shown, no choice needed', () {
      expect(profile(degrees: ['B.Sc']).profileDegrees, ['B.Sc']);
      expect(profile(degrees: ['B.Sc', 'MBA']).profileDegrees,
          ['B.Sc', 'MBA']);
    });

    test('three or more shows the member pick', () {
      final p = profile(
        degrees: ['B.Sc', 'MBA', 'MCA', 'M.Phil'],
        display: ['MBA', 'M.Phil'],
      );
      expect(p.profileDegrees, ['MBA', 'M.Phil']);
    });

    test('a pick is capped at two', () {
      final p = profile(
        degrees: ['B.Sc', 'MBA', 'MCA'],
        display: ['B.Sc', 'MBA', 'MCA'],
      );
      expect(p.profileDegrees.length, 2);
    });

    test('three or more with no pick falls back to the first two', () {
      final p = profile(degrees: ['B.Sc', 'MBA', 'MCA']);
      expect(p.profileDegrees, ['B.Sc', 'MBA']);
    });

    test('a pick that is no longer held is ignored', () {
      final p = profile(
        degrees: ['B.Sc', 'MBA', 'MCA'],
        display: ['Ph.D'],
      );
      expect(p.profileDegrees, ['B.Sc', 'MBA']);
    });

    test('a profile written before multi-degree support still reads', () {
      final p = profile(education: 'B.E');
      expect(p.allDegrees, ['B.E']);
      expect(p.profileDegrees, ['B.E']);
    });
  });

  group('§5 employment cascade', () {
    test('only the three working statuses continue into type + occupation', () {
      for (final s in [
        OccupationCatalog.statusEmployed,
        OccupationCatalog.statusSelfEmployed,
        OccupationCatalog.statusBusinessman,
      ]) {
        expect(OccupationCatalog.statusHasOccupation(s), isTrue, reason: s);
        expect(OccupationCatalog.typesFor(s), isNotEmpty, reason: s);
      }
      for (final s in [
        OccupationCatalog.statusStudent,
        OccupationCatalog.statusJobSeeker,
        OccupationCatalog.statusHomemaker,
        OccupationCatalog.statusRetired,
        OccupationCatalog.statusOthers,
      ]) {
        expect(OccupationCatalog.statusHasOccupation(s), isFalse, reason: s);
        // The type field is HIDDEN for these, not merely empty.
        expect(OccupationCatalog.typesFor(s), isEmpty, reason: s);
        expect(
            OccupationCatalog.occupationsFor(status: s, type: 'Private'),
            isEmpty,
            reason: s);
      }
    });

    test('each status offers its own distinct types', () {
      expect(
          OccupationCatalog.typesFor(OccupationCatalog.statusEmployed).values,
          containsAll(['Government', 'Private', 'Public Sector', 'Contract']));
      expect(
          OccupationCatalog.typesFor(OccupationCatalog.statusSelfEmployed).values,
          containsAll(['Profession', 'Freelance', 'Online Business', 'Agriculture']));
      expect(
          OccupationCatalog.typesFor(OccupationCatalog.statusBusinessman).values,
          containsAll(['Retail', 'Wholesale', 'Manufacturing', 'Trading']));
    });

    test('every type has at least one occupation behind it', () {
      for (final status in [
        OccupationCatalog.statusEmployed,
        OccupationCatalog.statusSelfEmployed,
        OccupationCatalog.statusBusinessman,
      ]) {
        for (final type in OccupationCatalog.typesFor(status)) {
          expect(
              OccupationCatalog.occupationsFor(status: status, type: type.en),
              isNotEmpty,
              reason: '$status → ${type.en} has no occupations');
        }
      }
    });

    test('statuses without an occupation store a canonical value', () {
      expect(
          OccupationCatalog.occupationValueFor(
              OccupationCatalog.statusHomemaker, 'Ignored'),
          'Homemaker');
      expect(
          OccupationCatalog.occupationValueFor(
              OccupationCatalog.statusJobSeeker, 'Ignored'),
          'Not Working');
      expect(
          OccupationCatalog.occupationValueFor(
              OccupationCatalog.statusEmployed, 'Nurse'),
          'Nurse');
    });

    test('legacy documents still resolve a status and type', () {
      expect(OccupationCatalog.statusForOccupation('Homemaker'),
          OccupationCatalog.statusHomemaker);
      expect(OccupationCatalog.statusForOccupation('Software Engineer'),
          OccupationCatalog.statusEmployed);
      expect(
          OccupationCatalog.statusForOccupation('Doctor',
              employmentType: 'Government'),
          OccupationCatalog.statusEmployed);
      // 'Business' was a Self Employed sector before வணிகர் existed.
      expect(
          OccupationCatalog.typeForOccupation('Trader',
              employmentType: 'Business'),
          OccupationCatalog.typeTrading);
      expect(OccupationCatalog.statusForOccupation(''), isNull);
    });
  });

  group('§6 education-aware occupation ordering', () {
    test('a 10th-pass member is not shown software roles first', () {
      final list = OccupationCatalog.occupationsFor(
        status: OccupationCatalog.statusEmployed,
        type: OccupationCatalog.typePrivate,
        educationLevel: EducationCatalog.level10,
      ).values;
      final driver = list.indexOf('Driver');
      final softwareEngineer = list.indexOf('Software Engineer');
      expect(driver, greaterThanOrEqualTo(0));
      expect(softwareEngineer, greaterThanOrEqualTo(0));
      expect(driver, lessThan(softwareEngineer));
    });

    test('a PG member sees the senior roles first', () {
      final list = OccupationCatalog.occupationsFor(
        status: OccupationCatalog.statusEmployed,
        type: OccupationCatalog.typePrivate,
        educationLevel: EducationCatalog.levelPg,
      ).values;
      expect(list.indexOf('Data Scientist'), lessThan(list.indexOf('Driver')));
    });

    test('nothing is ever filtered out — only re-ordered', () {
      final school = OccupationCatalog.occupationsFor(
        status: OccupationCatalog.statusEmployed,
        type: OccupationCatalog.typePrivate,
        educationLevel: EducationCatalog.levelBelow10,
      ).values.toSet();
      final pg = OccupationCatalog.occupationsFor(
        status: OccupationCatalog.statusEmployed,
        type: OccupationCatalog.typePrivate,
        educationLevel: EducationCatalog.levelPg,
      ).values.toSet();
      expect(school, equals(pg));
      expect(school, contains('Software Engineer'));
    });

    test('an unknown education level leaves the list alphabetical', () {
      final list = OccupationCatalog.occupationsFor(
        status: OccupationCatalog.statusEmployed,
        type: OccupationCatalog.typePrivate,
        educationLevel: null,
      ).values;
      final sorted = [...list]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      expect(list, equals(sorted));
    });
  });

  group('§9 bilingual search', () {
    test('a Tamil-labelled option answers to its English name', () {
      final tn = LocationCatalog.indianStates.byValue('Tamil Nadu')!;
      expect(tn.ta, 'தமிழ்நாடு');
      for (final q in ['tamil', 'Tamil Na', 'tn', 'tamilnadu']) {
        expect(tn.matches(q), isTrue, reason: q);
      }
    });

    test('an English-labelled option answers to Tamil', () {
      final tn = LocationCatalog.indianStates.byValue('Tamil Nadu')!;
      expect(tn.matches('தமிழ்'), isTrue);
    });

    test('district nicknames are searchable', () {
      expect(LocationCatalog.aliasesFor('Virudhunagar'), contains('virudunagar'));
      expect(LocationCatalog.aliasesFor('Tiruchirappalli'), contains('trichy'));
    });

    test('punctuation in a degree code does not block the match', () {
      final bsc = EducationCatalog.allDegrees.byValue('B.Sc')!;
      for (final q in ['bsc', 'B.Sc', 'b.s', 'அறிவியல்']) {
        expect(bsc.matches(q), isTrue, reason: q);
      }
      expect(bsc.matches('zzz'), isFalse);
    });

    test('an occupation answers to English, Tamil and its alias', () {
      final dev = OccupationCatalog.allOccupations.byValue('Software Engineer')!;
      expect(dev.matches('software'), isTrue);
      expect(dev.matches('மென்பொருள்'), isTrue);
      expect(dev.matches('it'), isTrue); // alias
    });
  });

  group('bilingual display', () {
    test('degrees and occupations keep the English term in brackets', () {
      final bsc = EducationCatalog.allDegrees.byValue('B.Sc')!;
      expect(bsc.display(tamil: false, withEnglish: true), 'B.Sc');
      expect(bsc.display(tamil: true, withEnglish: true),
          'இளங்கலை அறிவியல் (B.Sc)');
    });

    test('ordinary vocabulary is pure Tamil', () {
      final employed =
          OccupationCatalog.statuses.byValue(OccupationCatalog.statusEmployed)!;
      expect(employed.display(tamil: true), 'பணியாளர்');
      expect(employed.display(tamil: false), 'Employed');
    });

    test('every catalogue entry has a Tamil name', () {
      final missing = <String>[
        for (final o in [
          ...EducationCatalog.levels,
          ...EducationCatalog.allDegrees,
          ...OccupationCatalog.statuses,
          ...OccupationCatalog.allOccupations,
          ...LocationCatalog.countries,
          ...LocationCatalog.indianStates,
        ])
          if (o.ta.trim().isEmpty) o.en,
      ];
      expect(missing, isEmpty, reason: 'no Tamil for: ${missing.join(', ')}');
    });
  });
}
