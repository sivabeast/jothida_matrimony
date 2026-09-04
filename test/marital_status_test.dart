import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/constants/app_constants.dart';
import 'package:jothida_matrimony/core/utils/value_l10n.dart';

/// Marital status is the field that drifted: two competing constant lists meant
/// the SAME dropdown offered different options depending on which screen you
/// opened, and the Tamil labels were gendered. These tests pin the unified
/// contract so neither can come back.
void main() {
  group('one canonical list', () {
    test('is exactly the four agreed options, in order', () {
      expect(AppConstants.maritalStatusList, [
        'Never Married',
        'Married',
        'Divorced',
        'Widowed',
      ]);
    });

    test('offers no gendered bereavement option', () {
      expect(AppConstants.maritalStatusList, isNot(contains('Widow')));
      expect(AppConstants.maritalStatusList, isNot(contains('Widower')));
    });

    test('the shorthand alias points at the same list', () {
      // Screens reach for either name; they must never diverge again.
      expect(AppConstants.maritalStatuses, same(AppConstants.maritalStatusList));
    });

    test('gender has a shared list too', () {
      expect(AppConstants.genderList, ['Male', 'Female']);
    });
  });

  group('legacy values still resolve', () {
    test('gendered spellings fold onto Widowed', () {
      expect(AppConstants.normalizeMaritalStatus('Widow'), 'Widowed');
      expect(AppConstants.normalizeMaritalStatus('Widower'), 'Widowed');
    });

    test('retired options fold onto a current one', () {
      expect(AppConstants.normalizeMaritalStatus('Awaiting Divorce'), 'Divorced');
      expect(AppConstants.normalizeMaritalStatus('Separated'), 'Divorced');
      expect(AppConstants.normalizeMaritalStatus('Unmarried'), 'Never Married');
    });

    test('every alias lands on a real dropdown option', () {
      for (final canonical in AppConstants.legacyMaritalStatusAliases.values) {
        expect(AppConstants.maritalStatusList, contains(canonical),
            reason: '$canonical is not a selectable option');
      }
    });

    test('current values pass through untouched', () {
      for (final v in AppConstants.maritalStatusList) {
        expect(AppConstants.normalizeMaritalStatus(v), v);
      }
    });

    test('empty and unknown values return null, never a wrong guess', () {
      expect(AppConstants.normalizeMaritalStatus(null), isNull);
      expect(AppConstants.normalizeMaritalStatus(''), isNull);
      expect(AppConstants.normalizeMaritalStatus('   '), isNull);
      expect(AppConstants.normalizeMaritalStatus('Engaged'), isNull);
    });

    test('bereaved and divorced members still get the children fields', () {
      for (final v in ['Divorced', 'Widowed', 'Widow', 'Widower']) {
        expect(AppConstants.maritalStatusesWithChildren, contains(v));
      }
      expect(AppConstants.maritalStatusesWithChildren,
          isNot(contains('Never Married')));
    });
  });

  group('Tamil labels', () {
    test('match the agreed wording', () {
      expect(kTamilValueMap['Never Married'], 'திருமணம் ஆகாதவர்');
      expect(kTamilValueMap['Married'], 'திருமணமானவர்');
      expect(kTamilValueMap['Divorced'], 'விவாகரத்து ஆனவர்');
      expect(kTamilValueMap['Widowed'], 'துணையை இழந்தவர்');
    });

    test('legacy stored values read as the neutral wording too', () {
      expect(kTamilValueMap['Widow'], 'துணையை இழந்தவர்');
      expect(kTamilValueMap['Widower'], 'துணையை இழந்தவர்');
    });

    test('every selectable option has a Tamil label', () {
      for (final v in AppConstants.maritalStatusList) {
        expect(kTamilValueMap[v], isNotNull, reason: '$v has no Tamil label');
      }
      for (final v in AppConstants.genderList) {
        expect(kTamilValueMap[v], isNotNull, reason: '$v has no Tamil label');
      }
    });

    test('no gendered bereavement wording survives anywhere in the map', () {
      expect(kTamilValueMap.values, isNot(contains('விதவை')));
      expect(kTamilValueMap.values, isNot(contains('விதவர்')));
      expect(kTamilValueMap.values, isNot(contains('மனைவியை இழந்தவர்')));
      expect(kTamilValueMap.values, isNot(contains('கணவரை இழந்தவர்')));
    });
  });

  group('the children question follows marital status', () {
    test('someone who has never married is never asked', () {
      expect(AppConstants.showsChildrenQuestion('Never Married'), isFalse);
    });

    test('everyone who has been married is asked', () {
      expect(AppConstants.showsChildrenQuestion('Married'), isTrue);
      expect(AppConstants.showsChildrenQuestion('Divorced'), isTrue);
      expect(AppConstants.showsChildrenQuestion('Widowed'), isTrue);
    });

    test('a legacy stored value is judged on what it maps onto', () {
      // 'Unmarried' folds onto Never Married → still not asked…
      expect(AppConstants.showsChildrenQuestion('Unmarried'), isFalse);
      // …while the gendered/retired spellings all fold onto statuses that are.
      expect(AppConstants.showsChildrenQuestion('Widow'), isTrue);
      expect(AppConstants.showsChildrenQuestion('Widower'), isTrue);
      expect(AppConstants.showsChildrenQuestion('Awaiting Divorce'), isTrue);
      expect(AppConstants.showsChildrenQuestion('Separated'), isTrue);
    });

    test('nothing chosen yet asks nothing', () {
      expect(AppConstants.showsChildrenQuestion(null), isFalse);
      expect(AppConstants.showsChildrenQuestion(''), isFalse);
      expect(AppConstants.showsChildrenQuestion('   '), isFalse);
    });

    test('an unrecognised value never opens the question by accident', () {
      expect(AppConstants.showsChildrenQuestion('Complicated'), isFalse);
    });

    test('every option in the list is decided one way or the other', () {
      // The rule must cover the whole dropdown — a new option added to
      // maritalStatusList without a decision here would silently hide the
      // children question for those members.
      for (final v in AppConstants.maritalStatusList) {
        final asked = AppConstants.showsChildrenQuestion(v);
        expect(asked, v != 'Never Married',
            reason: '$v should ${v == 'Never Married' ? 'not ' : ''}be asked');
      }
    });
  });
}
