// Privacy settings, admin visibility, Cloudinary mapping, chat sending and the
// shared location search — the logic behind each, tested without Firebase.
//
// Firestore security rules protect whole documents, so field privacy is
// enforced by WHERE a value is stored: a hidden value lives only in a private
// document the member cannot read. The projection that decides that is pure,
// and these tests pin it down, including the spec's acceptance scenarios.

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/utils/admin_member_rows.dart';
import 'package:jothida_matrimony/core/utils/chat_outbox.dart';
import 'package:jothida_matrimony/core/utils/location_search.dart';
import 'package:jothida_matrimony/core/utils/matrimony_photo.dart';
import 'package:jothida_matrimony/core/utils/profile_privacy.dart';
import 'package:jothida_matrimony/models/chat_model.dart';
import 'package:jothida_matrimony/models/location_model.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/models/user_model.dart';
import 'package:jothida_matrimony/services/cloudinary/cloudinary_asset_id.dart';

const _photo =
    'https://res.cloudinary.com/dh8hzjx5q/image/upload/v1/jothida_matrimony/profiles/u1/photos/photo_0_1.jpg';
const _horoImg =
    'https://res.cloudinary.com/dh8hzjx5q/image/upload/v1/jothida_matrimony/profiles/u1/horoscope/img_1.jpg';

Map<String, bool> _privacy({
  bool phone = false,
  bool salary = false,
  bool horoscope = false,
  bool photo = false,
}) =>
    {
      ProfilePrivacy.phone: phone,
      ProfilePrivacy.salary: salary,
      ProfilePrivacy.horoscope: horoscope,
      ProfilePrivacy.photo: photo,
    };

/// A full (owner's) profile document.
Map<String, dynamic> _full(Map<String, bool> privacy,
        {String contactPrivacy = 'private'}) =>
    {
      'userId': 'u1',
      'fullName': 'Anitha',
      'gender': 'Female',
      'age': 26,
      'city': 'Virudhunagar',
      'district': 'Virudhunagar',
      'state': 'Tamil Nadu',
      'education': 'B.E',
      'caste': 'Nadar',
      'religion': 'Hindu',
      'status': 'approved',
      'isActive': true,
      'profilePhotoUrl': _photo,
      'annualIncome': '6-8 Lakhs',
      'horoscope': {
        'rasi': 'Mesham',
        'nakshatra': 'Aswini',
        'birthTime': '06:30',
        'horoscopeImages': [_horoImg],
      },
      'privacySettings': privacy,
      'contactPrivacy': contactPrivacy,
    };

/// What another MEMBER can read: the public document produced by the write
/// path (the private half never reaches them).
ProfileModel _memberView(Map<String, dynamic> full) {
  final privacy = ProfilePrivacy.fromMap(full['privacySettings']);
  final split = splitProfileWrite(full, privacy);
  return ProfileModel.fromData('p1', split.public);
}

/// What the ADMIN (or the owner) reads: public document + private copy.
ProfileModel _adminView(Map<String, dynamic> full) {
  final privacy = ProfilePrivacy.fromMap(full['privacySettings']);
  final split = splitProfileWrite(full, privacy);
  return ProfileModel.fromData(
      'p1', mergePrivateProfileData(split.public, split.private));
}

void main() {
  group('privacy settings are enforced by what the member document holds', () {
    test('TEST 1 — everything off: the member sees the full profile', () {
      final m = _memberView(_full(_privacy()));
      expect(m.profilePhotoUrl, _photo);
      expect(m.annualIncome, '6-8 Lakhs');
      expect(m.horoscope.rasi, 'Mesham');
      expect(m.horoscope.horoscopeImages, [_horoImg]);
    });

    test('TEST 3 — hide photo: only the photo is gone, the profile stays', () {
      final m = _memberView(_full(_privacy(photo: true)));
      expect(m.profilePhotoUrl, isNull);
      expect(m.fullName, 'Anitha');
      expect(m.age, 26);
      expect(m.city, 'Virudhunagar');
      expect(m.education, 'B.E');
      expect(m.caste, 'Nadar');
      expect(m.religion, 'Hindu');
      expect(m.annualIncome, '6-8 Lakhs');
      expect(m.horoscope.rasi, 'Mesham');
    });

    test('TEST 4 — hide salary + horoscope: only those two are hidden', () {
      final m = _memberView(_full(_privacy(salary: true, horoscope: true)));
      expect(m.annualIncome, isEmpty);
      expect(m.horoscope.rasi, isEmpty);
      expect(m.horoscope.horoscopeImages, isEmpty,
          reason: 'uploaded horoscope images are horoscope details too');
      expect(m.profilePhotoUrl, _photo);
      expect(m.fullName, 'Anitha');
    });

    test('TEST 8 — admin sees everything with every switch on', () {
      final full = _full(
          _privacy(phone: true, salary: true, horoscope: true, photo: true));
      final a = _adminView(full);
      expect(a.profilePhotoUrl, _photo);
      expect(a.annualIncome, '6-8 Lakhs');
      expect(a.horoscope.birthTime, '06:30');
      expect(a.horoscope.horoscopeImages, [_horoImg]);
      // ...while the member document carries none of it, and the stored
      // switches themselves are untouched.
      final m = _memberView(full);
      expect(m.profilePhotoUrl, isNull);
      expect(m.annualIncome, isEmpty);
      expect(m.horoscope.horoscopeImages, isEmpty);
      expect(a.hidesPhoto && a.hidesSalary && a.hidesHoroscope && a.hidesPhone,
          isTrue);
    });

    test('a hidden photo cannot be read back out of a legacy photo array', () {
      final split = splitProfileWrite(
          {'profilePhotoUrl': _photo, 'photos': [_photo]},
          _privacy(photo: true));
      expect(split.public['profilePhotoUrl'], isNull);
      expect(split.public['photos'], isEmpty);
      expect(split.public['additionalPhotos'], isEmpty);
      expect(split.private['profilePhotoUrl'], _photo);
    });

    test('a single horoscope key written while hidden blanks the whole map',
        () {
      final split = splitProfileWrite(
          {'horoscope.birthTime': '07:00'}, _privacy(horoscope: true));
      expect(split.public, {'horoscope': <String, dynamic>{}});
      expect(split.private, {'horoscope.birthTime': '07:00'});
    });

    test('a field write is applied onto the full data with update semantics',
        () {
      final truth = applyProfileWrite(
          _full(_privacy()), {'horoscope.birthTime': '07:00', 'age': 27});
      final h = truth['horoscope'] as Map;
      expect(h['birthTime'], '07:00');
      expect(h['rasi'], 'Mesham', reason: 'sibling keys survive');
      expect(truth['age'], 27);
      expect(nestFieldPaths({'horoscope.birthTime': 'x'}), {
        'horoscope': {'birthTime': 'x'}
      });
    });

    test('turning a switch off restores the value; on blanks it', () {
      final truth = _full(_privacy());
      final on = projectPublicPrivateFields(truth, _privacy(salary: true));
      expect(on['annualIncome'], '');
      final off = projectPublicPrivateFields(truth, _privacy());
      expect(off['annualIncome'], '6-8 Lakhs');
      expect(off['profilePhotoUrl'], _photo);
    });

    test('Hide Phone Number blanks only the numbers on the shared record', () {
      final split = splitContactWrite({
        'contactPersonName': 'Father',
        'mobileNumber': '9876543210',
        'whatsappNumber': '9876543210',
        'email': 'a@b.com',
      }, hidePhone: true);
      expect(split.public['mobileNumber'], '');
      expect(split.public['whatsappNumber'], '');
      expect(split.public['email'], 'a@b.com');
      expect(split.public['contactPersonName'], 'Father');
      expect(split.private['mobileNumber'], '9876543210');
      // The owner / admin read merges them back.
      final merged = mergePrivateContactData(split.public, split.private);
      expect(merged['mobileNumber'], '9876543210');
    });

    test('an old build writing a newer value to the public doc is not lost',
        () {
      final merged = mergePrivateProfileData(
        {
          'annualIncome': '10+ Lakhs',
          'updatedAt': Timestamp.fromMillisecondsSinceEpoch(2000),
        },
        {
          'annualIncome': '6-8 Lakhs',
          'updatedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
        },
      );
      expect(merged['annualIncome'], '10+ Lakhs');
      // Otherwise the private copy is authoritative.
      final normal = mergePrivateProfileData(
        {'annualIncome': ''},
        {'annualIncome': '6-8 Lakhs'},
      );
      expect(normal['annualIncome'], '6-8 Lakhs');
    });
  });

  group('reconcile — existing members and the Cloudinary photo mapping', () {
    test('a legacy member with hidden fields gets a private copy, then blanks',
        () {
      final legacy = _full(_privacy(photo: true, salary: true));
      final plan =
          planPrivacyReconcile(publicData: legacy, privateData: null);
      expect(plan.privateWrite!['profilePhotoUrl'], _photo);
      expect(plan.privateWrite!['annualIncome'], '6-8 Lakhs');
      expect(plan.publicUpdate['profilePhotoUrl'], isNull);
      expect(plan.publicUpdate['annualIncome'], '');
      expect(plan.publicUpdate.containsKey('horoscope'), isFalse,
          reason: 'visible fields are not rewritten');
    });

    test('an already-consistent member needs no write', () {
      final full = _full(_privacy(photo: true));
      final split = splitProfileWrite(full, _privacy(photo: true));
      final plan = planPrivacyReconcile(
          publicData: split.public, privateData: privateSnapshotOf(full));
      expect(plan.isNoop, isTrue);
    });

    test('a photo only referenced from the legacy `photos` array is restored',
        () {
      // The old admin editor uploaded to Cloudinary and saved the URL into
      // `photos`, a field the model never read.
      final doc = {
        'userId': 'u1',
        'fullName': 'Anitha',
        'profilePhotoUrl': null,
        'photos': [_photo],
      };
      expect(ProfileModel.fromData('p1', doc).profilePhotoUrl, _photo);
      final plan = planPrivacyReconcile(
          publicData: doc,
          privateData: null,
          recoveredPhoto: legacyProfilePhoto(doc));
      expect(plan.recoveredPhoto, _photo);
      expect(plan.privateWrite!['profilePhotoUrl'], _photo);
      expect(plan.publicUpdate['profilePhotoUrl'], _photo);
    });

    test('recovery only accepts an upload inside the member\'s own folder', () {
      expect(isMemberCloudinaryAsset(_photo, 'u1'), isTrue);
      expect(isMemberCloudinaryAsset(_photo, 'u2'), isFalse);
      expect(
          isMemberCloudinaryAsset(
              'https://lh3.googleusercontent.com/a/x', 'u1'),
          isFalse);
    });

    test('contact details embedded in an old public profile are removed', () {
      final doc = {
        ..._full(_privacy()),
        'contact': {'mobileNumber': '9876543210'},
      };
      final plan = planPrivacyReconcile(publicData: doc, privateData: null);
      expect(plan.publicUpdate['contact'], isEmpty);
    });

    test('a photo copied into shared documents honours Hide Profile Photo', () {
      final hidden = ProfileModel.fromData('p1', _full(_privacy(photo: true)));
      final shown = ProfileModel.fromData('p1', _full(_privacy()));
      expect(hidden.sharedPhotoUrl, isEmpty);
      expect(shown.sharedPhotoUrl, _photo);
    });
  });

  group('admin All Users', () {
    ProfileModel profile(String uid, {bool dummy = false}) =>
        ProfileModel.fromData('p_$uid', {
          ..._full(_privacy(photo: true, phone: true)),
          'userId': uid,
          'isDummy': dummy,
        });

    test('lists a member whose account document is missing', () {
      final users = [
        UserModel(uid: 'u1', createdAt: DateTime(2026), updatedAt: DateTime(2026)),
      ];
      final rows = adminMemberRows(users, {
        'u1': profile('u1'),
        'orphan': profile('orphan'),
        'seed': profile('seed', dummy: true),
      });
      expect(rows.map((u) => u.uid), containsAll(['u1', 'orphan']));
      expect(rows.map((u) => u.uid), isNot(contains('seed')));
    });
  });

  group('chat outbox — sending never spins forever', () {
    ChatMessage stored(String id, {bool pending = false}) => ChatMessage(
        id: id,
        senderId: 'me',
        text: 'hi',
        sentAt: DateTime(2026, 1, 1, 10),
        isPending: pending);
    OutgoingMessage out(String id, OutgoingStatus s) => OutgoingMessage(
        id: id, text: 'hi', createdAt: DateTime(2026, 1, 1, 11), status: s);

    test('a message shows immediately, before the stream has it', () {
      final list = mergeOutbox(
          stored: const [],
          outbox: [out('m1', OutgoingStatus.sending)],
          myUid: 'me');
      expect(list.single.id, 'm1');
      expect(list.single.isPending, isTrue);
    });

    test('a failed send is shown as failed, even over a pending local copy',
        () {
      final list = mergeOutbox(
          stored: [stored('m1', pending: true)],
          outbox: [out('m1', OutgoingStatus.failed)],
          myUid: 'me');
      expect(list.single.isFailed, isTrue);
      expect(list.single.isPending, isFalse);
    });

    test('an acknowledged message replaces its outbox entry — no duplicate',
        () {
      final outbox = [out('m1', OutgoingStatus.failed)];
      final storedList = [stored('m1')];
      final list =
          mergeOutbox(stored: storedList, outbox: outbox, myUid: 'me');
      expect(list, hasLength(1));
      expect(list.single.isFailed, isFalse);
      expect(confirmedOutboxIds(storedList, outbox), {'m1'});
    });

    test('the send path is a batch, never a server-only transaction', () {
      final src = File('lib/services/firebase/chat_service.dart')
          .readAsStringSync();
      final send = src.substring(src.indexOf('Future<void> sendMessage('));
      final body = send.substring(0, send.indexOf('String newMessageId('));
      expect(body.contains('runTransaction'), isFalse);
      expect(body.contains('_db.batch()'), isTrue);
    });
  });

  group('location search (bundled JSON)', () {
    late PlaceSearchIndex index;
    late List<TnDistrict> districts;

    setUpAll(() {
      List<dynamic> read(String name) => jsonDecode(
          File('assets/master_data/location/$name.json').readAsStringSync());
      final dTa = {for (final r in read('districts_ta')) r['id']: r['name']};
      final cTa = {for (final r in read('cities_ta')) r['id']: r['name']};
      districts = [
        for (final r in read('districts_en'))
          TnDistrict(
              id: r['id'], nameEn: r['name'], nameTa: '${dTa[r['id']]}'),
      ];
      final cities = [
        for (final r in read('cities_en'))
          TnCity(
              id: r['id'],
              districtId: r['districtId'],
              nameEn: r['name'],
              nameTa: '${cTa[r['id']]}'),
      ];
      index = PlaceSearchIndex.build(districts: districts, cities: cities);
    });

    PlaceSearchHit first(String q) => index.search(q).hits.first;

    test('Virudhunagar returns the town, in Virudhunagar District', () {
      final hit = first('Virudhunagar');
      expect(hit.option.city.nameEn, 'Virudhunagar');
      expect(hit.option.district.nameEn, 'Virudhunagar');
      // District and town are different hierarchy levels with their own ids.
      expect(hit.option.city.id, isNot(hit.option.district.id));
    });

    test('a district spelt differently from its town still finds the town', () {
      expect(first('Kancheepuram').option.city.nameEn, 'Kanchipuram');
      expect(first('Viluppuram').option.city.nameEn, 'Villupuram');
      expect(first('Kanniyakumari').option.city.nameEn, 'Kanyakumari');
      expect(first('Thoothukudi').option.city.nameEn, 'Thoothukkudi');
    });

    test('every district has a selectable head-quarters town', () {
      for (final d in districts) {
        expect(index.headquartersOf(d.id), isNotNull,
            reason: '${d.nameEn} has no main town to select');
      }
      expect(first('Tirunelveli').option.city.nameEn, 'Tirunelveli');
      expect(first('Tiruvannamalai').option.city.nameEn, 'Tiruvannamalai');
    });

    test('towns, nicknames, Tamil and loose spellings', () {
      expect(first('Rajapalayam').option.city.nameEn, 'Rajapalayam');
      expect(first('rajapal').option.city.nameEn, 'Rajapalayam');
      expect(first('nellai').option.city.nameEn, 'Tirunelveli');
      expect(first('விருதுநகர்').option.city.nameEn, 'Virudhunagar');
      expect(first('Viruthunagar').option.district.nameEn, 'Virudhunagar');
    });

    test('a district query also lists the other towns of that district', () {
      final towns = index
          .search('Virudhunagar')
          .hits
          .where((h) => h.option.district.nameEn == 'Virudhunagar')
          .map((h) => h.option.city.nameEn);
      expect(towns, containsAll(['Virudhunagar', 'Rajapalayam', 'Sivakasi']));
    });

    test('an unlisted locality falls back to the nearest recognised towns', () {
      final r = index.search('Rajapalayem');
      expect(r.hits.map((h) => h.option.city.nameEn), contains('Rajapalayam'));
    });

    test('a free-typed place outside Tamil Nadu keeps its state', () {
      expect(stateNamedIn('Kochi, Kerala'), 'Kerala');
      expect(stateNamedIn('Somewhere'), isNull);
      expect(placeKey('Kallakurichi'), placeKey('Kallakkurichi'));
    });
  });

  group('Cloudinary delivery size', () {
    test('images are fetched display-sized; everything else is untouched', () {
      final sized = cloudinaryDisplayUrl(_photo, width: 300);
      expect(sized, contains('/image/upload/c_limit,w_400,q_auto/v1/'));
      // Deleting still resolves the same asset from either URL.
      expect(cloudinaryRefFromUrl(sized), cloudinaryRefFromUrl(_photo));
      const pdf =
          'https://res.cloudinary.com/dh8hzjx5q/raw/upload/v1/x/horoscope.pdf';
      expect(cloudinaryDisplayUrl(pdf, width: 300), pdf);
      expect(cloudinaryDisplayUrl('https://example.com/a.jpg', width: 300),
          'https://example.com/a.jpg');
      expect(cloudinaryDisplayUrl(sized, width: 900), sized,
          reason: 'never transformed twice');
    });
  });

  group('security rules', () {
    final rules = File('firestore.rules').readAsStringSync();

    test('public contact sharing no longer looks up profiles/{uid}', () {
      // Profile ids are auto-generated, so that lookup never matched and
      // PUBLIC behaved like PRIVATE.
      expect(rules.contains(r'profiles/$(ownerId)'), isFalse);
      expect(rules.contains(r'profiles/$(otherUid)'), isFalse);
      expect(RegExp(r'match /contacts/\{ownerId\}[\s\S]*?isPublicContactOf')
              .hasMatch(rules),
          isTrue);
      expect(RegExp(r'function mayOpenChatWith[\s\S]*?isPublicContactOf')
              .hasMatch(rules),
          isTrue);
    });

    test('private copies are readable only by owner, admin (and staff)', () {
      expect(rules.contains('match /profile_private/{uid}'), isTrue);
      expect(rules.contains('match /contact_private/{uid}'), isTrue);
      final contactPrivate = rules.substring(
          rules.indexOf('match /contact_private/{uid}'),
          rules.indexOf('match /contact_private/{uid}') + 400);
      expect(contactPrivate.contains('isAstrologer'), isFalse,
          reason: 'phone numbers stay owner + admin only');
    });
  });
}
