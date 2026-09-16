// The profile photo, end to end: the value the wizard uploads is the value
// Firestore stores, the value every read returns (owner, admin, edit), and the
// value every avatar renders — with a placeholder, never an empty circle, when
// it cannot load. Admin visibility never depends on member privacy.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/utils/matrimony_photo.dart';
import 'package:jothida_matrimony/core/utils/profile_privacy.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/widgets/common/network_photo.dart';

const _url =
    'https://res.cloudinary.com/dh8hzjx5q/image/upload/v1726000000/jothida_matrimony/profiles/u1/photos/photo_0_1726000000000.jpg';

void main() {
  group('the uploaded URL survives every hop', () {
    test('wizard data → Firestore document → read back', () {
      // What submitProfile builds after the upload returned `secure_url`.
      final created = ProfileModel.fromMap({
        'userId': 'u1',
        'name': 'Anitha',
        'photos': [_url],
      });
      expect(created.profilePhotoUrl, _url);

      final stored = created.toFirestore();
      expect(stored['profilePhotoUrl'], _url,
          reason: 'the one field every screen reads');

      final reread = ProfileModel.fromData('p1', stored);
      expect(reread.profilePhotoUrl, _url);
      expect(reread.photos, [_url]);
    });

    test('an edit seeded from the stored profile keeps the photo', () {
      final stored = ProfileModel.fromMap({
        'userId': 'u1',
        'photos': [_url],
      }).toFirestore();
      final seeded = ProfileModel.fromData('p1', stored).toWizardData();
      expect(seeded['photos'], [_url],
          reason: 'saving another section must not blank the photo');
      expect(ProfileModel.fromMap(seeded).toFirestore()['profilePhotoUrl'],
          _url);
    });

    test('an existing profile whose URL sits in a legacy field still shows it',
        () {
      final legacy = ProfileModel.fromData('p1', {
        'userId': 'u1',
        'profilePhotoUrl': null,
        'photos': [_url],
      });
      expect(legacy.profilePhotoUrl, _url);
    });

    test('a Google account picture is never taken for the profile photo', () {
      final p = ProfileModel.fromData('p1', {
        'userId': 'u1',
        'profilePhotoUrl': 'https://lh3.googleusercontent.com/a/abc=s96-c',
      });
      expect(p.profilePhotoUrl, isNull);
    });
  });

  group('admin visibility is independent of member privacy', () {
    Map<String, dynamic> doc({required bool hidePhoto}) => {
          'userId': 'u1',
          'fullName': 'Anitha',
          'profilePhotoUrl': _url,
          'contactPrivacy': 'private', // contact visibility: Hidden
          'privacySettings': {ProfilePrivacy.photo: hidePhoto},
        };

    test('contact sharing Private never touches the photo', () {
      final split = splitProfileWrite(
          doc(hidePhoto: false), ProfilePrivacy.fromMap(const {}));
      expect(split.public['profilePhotoUrl'], _url);
    });

    test('even a HIDDEN photo is in what the admin reads', () {
      final full = doc(hidePhoto: true);
      final privacy = ProfilePrivacy.fromMap(full['privacySettings']);
      final split = splitProfileWrite(full, privacy);
      // Other members: nothing to read.
      expect(split.public['profilePhotoUrl'], isNull);
      // Admin (and owner): public document + private copy.
      final admin = ProfileModel.fromData(
          'p1', mergePrivateProfileData(split.public, split.private));
      expect(admin.profilePhotoUrl, _url);
      expect(admin.contactPrivacy, 'private');
    });

    test('a photo recovered from the account mirror must be an app upload', () {
      expect(isAppCloudinaryImage(_url), isTrue);
      expect(isAppCloudinaryImage('https://lh3.googleusercontent.com/a/x'),
          isFalse);
      expect(
          isAppCloudinaryImage(
              'https://res.cloudinary.com/someoneelse/image/upload/v1/x.jpg'),
          isFalse);
      final plan = planPrivacyReconcile(
        publicData: {'userId': 'u1', 'profilePhotoUrl': null},
        privateData: null,
        recoveredPhoto: _url,
      );
      expect(plan.publicUpdate['profilePhotoUrl'], _url);
    });
  });

  group('avatars never render an empty circle', () {
    Future<void> pump(WidgetTester tester, String url) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: PhotoAvatar(
                url: url,
                radius: 24,
                placeholder: const Text('A'),
              ),
            ),
          ),
        ));

    testWidgets('no photo → the placeholder', (tester) async {
      await pump(tester, '');
      expect(find.text('A'), findsOneWidget);
      expect(find.byType(NetworkPhoto), findsNothing);
    });

    testWidgets('a photo → cached NetworkPhoto with the SAME placeholder as '
        'its failure fallback', (tester) async {
      await pump(tester, _url);
      final photo = tester.widget<NetworkPhoto>(find.byType(NetworkPhoto));
      expect(photo.url, _url);
      expect(photo.width, 48);
      expect(photo.height, 48);
      expect(photo.fallback, isNotNull);
    });
  });

  group('source guards', () {
    String read(String path) => File(path).readAsStringSync();

    test('profile-photo avatars do not use a bare NetworkImage', () {
      for (final path in [
        'lib/widgets/profile/editable_profile_photo.dart',
        'lib/screens/admin/admin_approvals_screen.dart',
        'lib/screens/admin/admin_users_page.dart',
        'lib/screens/home/tabs/home_dashboard_tab.dart',
        'lib/screens/chat/chat_screen.dart',
        'lib/screens/chat/chat_list_screen.dart',
      ]) {
        expect(read(path).contains('NetworkImage('), isFalse, reason: path);
      }
    });

    test('an ImageProvider (no fallback) always loads the original URL', () {
      final src = read('lib/widgets/common/network_photo.dart');
      final start = src.indexOf('ImageProvider? cachedPhotoProvider(');
      final body = src.substring(start, src.indexOf('}', start));
      expect(body.contains('cloudinaryDisplayUrl'), isFalse);
    });

    test('a photo save does not restart the live profile stream', () {
      final src = read('lib/providers/profile_edit_provider.dart');
      expect(src.contains('ref.invalidate(myProfileProvider)'), isFalse);
    });

    test('split writes are only sent once the private storage is known to '
        'work', () {
      final src = read('lib/services/firebase/firestore_service.dart');
      final create = src.substring(src.indexOf('Future<String> createProfile('),
          src.indexOf('// ── Field privacy (server-side)'));
      expect(create.indexOf('_useSplitWrites'),
          lessThan(create.indexOf('_commitPrivacyBatch')));
      expect(src.contains('_canWritePrivate'), isFalse,
          reason: 'the old probe WROTE a stub document to find out');
    });
  });
}
