// §13–§15 — the profile-creation structure is the SINGLE source of truth.
//
// Create, Edit, Admin-Create and Admin-Edit must all be the same form. These
// tests guard the two ways that could silently regress:
//
//   • a section editor pointing at some other screen instead of the wizard
//     step that produced it; and
//   • the admin editor writing a member's profile under the wrong uid.

import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/utils/profile_completion.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/screens/profile/profile_creation_screen.dart';

ProfileModel _profile({String id = 'p1', String userId = 'member-uid'}) =>
    ProfileModel.fromMap({
      'id': id,
      'userId': userId,
      'fullName': 'Test Member',
      'city': 'Madurai',
      'state': 'Tamil Nadu',
    });

void main() {
  group('every completable section opens a wizard step', () {
    test('section routes are wizard section-edit routes, not bespoke forms',
        () {
      final sections = profileSections(_profile());
      // Education & Career · Location · Community · Horoscope — the four field
      // sections. Photos and Partner Preferences keep their own dedicated
      // editors (upload/crop/delete and the preference sliders), which are
      // single-purpose screens rather than rival profile forms.
      const expected = {
        'education': '/profile/p1/edit-section/2',
        'location': '/profile/p1/edit-section/1',
        'religious': '/profile/p1/edit-section/3',
        'astrology': '/profile/p1/edit-section/4',
      };
      for (final entry in expected.entries) {
        final section = sections.firstWhere((s) => s.id == entry.key);
        expect(section.route, entry.value,
            reason: '"${entry.key}" must open the creation wizard step');
      }
    });

    test('no section still points at a removed standalone editor', () {
      final routes = profileSections(_profile()).map((s) => s.route).toList();
      for (final gone in const [
        '/edit/education',
        '/edit/location',
        '/edit/religious',
        '/edit/about',
        '/edit/lifestyle',
        '/personal-details',
      ]) {
        expect(routes, isNot(contains(gone)));
      }
    });

    test('with no profile yet, every section points at creation', () {
      for (final section in profileSections(null)) {
        if (section.route.startsWith('/profile/')) {
          expect(section.route, '/profile/create');
        }
      }
    });
  });

  group('the admin editor is the member wizard', () {
    test('it carries the MEMBER uid, so the save stays on their account', () {
      const screen = ProfileCreationScreen(
        editProfileId: 'p1',
        ownerUserId: 'member-uid',
      );
      expect(screen.ownerUserId, 'member-uid');
      expect(screen.editProfileId, 'p1');
      // Admin EDIT is never admin CREATE mode — no Login Credentials step.
      expect(screen.adminMode, isFalse);
    });

    test('a member editing their own profile has no owner override', () {
      const screen = ProfileCreationScreen(editProfileId: 'p1');
      expect(screen.ownerUserId, isNull);
    });

    test('admin CREATE is the same wizard plus the credentials step', () {
      const screen = ProfileCreationScreen(adminMode: true);
      expect(screen.adminMode, isTrue);
      expect(screen.editProfileId, isNull);
    });
  });
}
