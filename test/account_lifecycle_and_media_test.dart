// The data-lifecycle guarantees this change is judged on:
//
//   • DELETE ACCOUNT → NEW ACCOUNT must never bring the old profile back
//     (spec §4/§23) — the uid→profile lookup is deterministic, a deletion
//     reports what it could not remove, and the one combination that can
//     resurrect a profile is named rather than hidden;
//   • CHAT always shows the member's CURRENT name and photo (spec §2), and
//     never a Google account picture (spec §5);
//   • the login prompt appears on every app OPEN and is never a loop (§14).

import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/providers/chat_provider.dart';
import 'package:jothida_matrimony/providers/guest_login_prompt_provider.dart';
import 'package:jothida_matrimony/repositories/auth_repository.dart';
import 'package:jothida_matrimony/services/firebase/firestore_service.dart';

const _uid = 'uid-1';

ProfileModel _profile({
  required String id,
  required DateTime createdAt,
  DateTime? updatedAt,
  String name = 'Member',
  String? photo,
}) =>
    ProfileModel(
      id: id,
      userId: _uid,
      profileCreatedBy: 'Myself',
      profileCreatedFor: 'Myself',
      fullName: name,
      gender: 'Male',
      dateOfBirth: DateTime(1995, 5, 5),
      age: 30,
      height: '5ft 8in',
      weight: '70',
      maritalStatus: 'Unmarried',
      religion: 'Hindu',
      education: 'B.E.',
      occupation: 'Engineer',
      annualIncome: '5-7 Lakhs',
      country: 'India',
      state: 'Tamil Nadu',
      city: 'Madurai',
      motherTongue: 'Tamil',
      // The nested records are irrelevant here — these tests are about WHICH
      // profile is served and how its identity is rendered.
      horoscope: HoroscopeDetails.fromMap(const {}),
      partnerPreferences: const PartnerPreferences(),
      contact: ContactDetails.fromMap(const {}),
      profilePhotoUrl: photo,
      createdAt: createdAt,
      updatedAt: updatedAt ?? createdAt,
    );

void main() {
  group('which profile belongs to a uid', () {
    test('no profile at all resolves to null', () {
      expect(FirestoreService.newestProfile(const []), isNull);
    });

    test('the single profile is served as-is', () {
      final only = _profile(id: 'p1', createdAt: DateTime(2026, 1, 1));
      expect(FirestoreService.newestProfile([only])?.id, 'p1');
    });

    test('a NEW profile always beats a stale one under the same uid', () {
      // THE regression (spec §4). Deleting an account whose Firebase Auth
      // record survives (`requires-recent-login`, a refused re-authentication)
      // gives the member back the SAME uid. If any part of the old profile
      // delete did not land, the new profile is written beside it — and the old
      // query took `limit(1)` off an UNORDERED result, so Firestore was free to
      // hand back the deleted one. It did, and the old profile "came back".
      final stale = _profile(
          id: 'aaa-old', createdAt: DateTime(2026, 1, 1), name: 'Old Name');
      final fresh = _profile(
          id: 'zzz-new', createdAt: DateTime(2026, 9, 1), name: 'New Name');

      // Whatever order the backend returns them in.
      expect(FirestoreService.newestProfile([stale, fresh])?.fullName,
          'New Name');
      expect(FirestoreService.newestProfile([fresh, stale])?.fullName,
          'New Name');
    });

    test('equal createdAt falls back to the most recently updated', () {
      final sameDay = DateTime(2026, 3, 3);
      final older = _profile(
          id: 'p1',
          createdAt: sameDay,
          updatedAt: DateTime(2026, 3, 3),
          name: 'Older');
      final newer = _profile(
          id: 'p2',
          createdAt: sameDay,
          updatedAt: DateTime(2026, 6, 6),
          name: 'Newer');
      expect(FirestoreService.newestProfile([older, newer])?.fullName, 'Newer');
    });

    test('the choice is STABLE, not dependent on result ordering', () {
      // Identical timestamps: the document id breaks the tie, so the same set
      // always resolves to the same profile however it arrives.
      final at = DateTime(2026, 4, 4);
      final a = _profile(id: 'aaa', createdAt: at);
      final b = _profile(id: 'bbb', createdAt: at);
      expect(FirestoreService.newestProfile([a, b])?.id,
          FirestoreService.newestProfile([b, a])?.id);
    });
  });

  group('what an account deletion reports', () {
    test('a clean deletion is complete and cannot resurrect', () {
      const clean = AccountDeletionResult(authDeleted: true);
      expect(clean.isComplete, isTrue);
      expect(clean.mayResurrect, isFalse);
    });

    test('a surviving auth record alone is incomplete but harmless', () {
      // Re-authentication was refused, so the uid lives on — but its data is
      // gone, so signing in again starts a genuinely clean profile.
      const authOnly = AccountDeletionResult(authDeleted: false);
      expect(authOnly.isComplete, isFalse);
      expect(authOnly.mayResurrect, isFalse);
    });

    test('surviving DATA alone is incomplete but harmless', () {
      // The uid can never come back, so leftover documents are unreachable
      // orphans rather than a profile waiting to reappear.
      const dataOnly =
          AccountDeletionResult(authDeleted: true, residualData: true);
      expect(dataOnly.isComplete, isFalse);
      expect(dataOnly.mayResurrect, isFalse);
    });

    test('a surviving auth record AND surviving data is the dangerous one', () {
      // Same uid signs in again + data still stored under it = the deleted
      // profile reappears. This is the combination worth naming.
      const bad = AccountDeletionResult(
          authDeleted: false, residualData: true, failedSteps: ['profiles']);
      expect(bad.isComplete, isFalse);
      expect(bad.mayResurrect, isTrue);
    });

    test('a failed step counts even before the verification read', () {
      const partial =
          AccountDeletionResult(authDeleted: false, failedSteps: ['contacts']);
      expect(partial.isComplete, isFalse);
      expect(partial.mayResurrect, isTrue);
    });
  });

  group('who a conversation says you are talking to', () {
    const snapshotName = 'Ravi';
    const snapshotPhoto = 'https://res.cloudinary.com/x/image/upload/old.jpg';
    const newPhoto = 'https://res.cloudinary.com/x/image/upload/new.jpg';

    test('the CURRENT profile wins over the thread snapshot (spec §2)', () {
      // Renaming yourself and changing your photo must reach conversations
      // that already exist — the stored copy is a cache, not the truth.
      final identity = resolveChatIdentity(
        profile: _profile(
            id: 'p1',
            createdAt: DateTime(2026, 1, 1),
            name: 'Arun',
            photo: newPhoto),
        isTamil: false,
        snapshotName: snapshotName,
        snapshotPhoto: snapshotPhoto,
      );
      expect(identity.name, 'Arun');
      expect(identity.photoUrl, newPhoto);
    });

    test('the snapshot is the fallback while the profile has not loaded', () {
      final identity = resolveChatIdentity(
        profile: null,
        isTamil: false,
        snapshotName: snapshotName,
        snapshotPhoto: snapshotPhoto,
      );
      expect(identity.name, snapshotName);
      expect(identity.photoUrl, snapshotPhoto);
    });

    test('a REMOVED photo is not put back by the stale snapshot', () {
      final identity = resolveChatIdentity(
        profile: _profile(
            id: 'p1', createdAt: DateTime(2026, 1, 1), name: 'Arun'),
        isTamil: false,
        snapshotName: snapshotName,
        snapshotPhoto: snapshotPhoto,
      );
      expect(identity.photoUrl, isEmpty);
    });

    test('a Google account picture never reaches a chat (spec §5)', () {
      const googleAvatar = 'https://lh3.googleusercontent.com/a/abc123';
      // ...neither from the profile...
      expect(
        resolveChatIdentity(
          profile: _profile(
              id: 'p1',
              createdAt: DateTime(2026, 1, 1),
              photo: googleAvatar),
          isTamil: false,
          snapshotName: snapshotName,
          snapshotPhoto: '',
        ).photoUrl,
        isEmpty,
      );
      // ...nor from a thread snapshot written before that rule existed.
      expect(
        resolveChatIdentity(
          profile: null,
          isTamil: false,
          snapshotName: snapshotName,
          snapshotPhoto: googleAvatar,
        ).photoUrl,
        isEmpty,
      );
    });

    test('an empty live name does not blank the header', () {
      final identity = resolveChatIdentity(
        profile: _profile(
            id: 'p1', createdAt: DateTime(2026, 1, 1), name: '   '),
        isTamil: false,
        snapshotName: snapshotName,
        snapshotPhoto: '',
      );
      expect(identity.name, snapshotName);
    });
  });

  group('the guest login prompt', () {
    final now = DateTime(2026, 9, 16, 10, 0);

    test('an app OPEN always prompts, whatever the interval says (§14)', () {
      expect(
        shouldShowGuestLoginPrompt(
          isGuest: true,
          // Prompted one minute ago, in the PREVIOUS session.
          lastShownMs:
              now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
          now: now,
          promptedThisLaunch: false,
        ),
        isTrue,
      );
    });

    test('a member is never prompted, not even on open', () {
      expect(
        shouldShowGuestLoginPrompt(
          isGuest: false,
          lastShownMs: null,
          now: now,
          promptedThisLaunch: false,
        ),
        isFalse,
      );
    });

    test('once shown this launch, the interval takes over again', () {
      // No loop: closing it does not immediately re-open it.
      expect(
        shouldShowGuestLoginPrompt(
          isGuest: true,
          lastShownMs: now.millisecondsSinceEpoch,
          now: now,
          promptedThisLaunch: true,
        ),
        isFalse,
      );
      expect(
        shouldShowGuestLoginPrompt(
          isGuest: true,
          lastShownMs: now
              .subtract(const Duration(minutes: 11))
              .millisecondsSinceEpoch,
          now: now,
          promptedThisLaunch: true,
        ),
        isTrue,
      );
    });
  });
}
