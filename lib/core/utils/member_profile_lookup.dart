/// Finding a member's matrimony profile FOR AN ADMIN, from the member's uid —
/// the one lookup behind Admin → Users → Edit Profile and User Details.
///
/// WHY "This account has not created a matrimony profile yet" appeared for
/// members who had one:
///
///  * The screen treated the FIRST answer of a live `profiles where userId ==
///    uid` query as the truth. With Firestore's offline cache that first
///    answer can be an EMPTY result from the local cache (no connection yet,
///    a flaky one, or a cache that has not seen the document) — and "the
///    cache holds nothing" was rendered as "the member has no profile".
///  * It looked in exactly one place. A profile document whose `userId` field
///    is blank (written by an older build or an interrupted save) is still
///    linked to its member by the pointers the app keeps — `users/{uid}`
///    .profileId, `contacts/{uid}`.profileId and `profile_private/{uid}`
///    .profileId — but none of them was consulted.
///
/// Now "no profile" is only concluded after the SERVER confirms that nothing
/// is filed under the uid AND no pointer leads to one. A network or permission
/// failure is an error (with a retry), never "no profile". A pointer that
/// leads to a profile owned by a DIFFERENT uid is refused, so an admin can
/// never be shown — or save over — another member's profile.
library;

import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/profile_model.dart';
import '../../services/firebase/firestore_service.dart';

/// One read of the profiles filed under a uid.
typedef ProfilesByUserIdRead = ({List<ProfileModel> profiles, bool fromCache});

/// Resolves the matrimony profile of member [uid].
///
/// * [byUserId] reads `profiles where userId == uid`; `serverOnly` forces a
///   server read (it throws when the server cannot be reached).
/// * [pointerProfileIds] lists the profile ids the member's own records point
///   at, in order of trust.
/// * [profileById] reads one profile document (null when it does not exist).
///
/// Returns null ONLY when the database confirms there is no profile. Every
/// read failure propagates to the caller.
Future<ProfileModel?> resolveMemberProfile({
  required String uid,
  required Future<ProfilesByUserIdRead> Function({required bool serverOnly})
  byUserId,
  required Future<List<String>> Function() pointerProfileIds,
  required Future<ProfileModel?> Function(String profileId) profileById,
}) async {
  final member = uid.trim();
  if (member.isEmpty) {
    throw ArgumentError.value(uid, 'uid', 'A member uid is required');
  }

  ProfileModel? owned(List<ProfileModel> list) =>
      FirestoreService.newestProfile([
        for (final p in list)
          if (p.userId.trim() == member) p,
      ]);

  // 1) The profile filed under the uid — the normal case.
  var read = await byUserId(serverOnly: false);
  final found = owned(read.profiles);
  if (found != null) return found;

  // 2) An empty CACHE answer proves nothing: ask the server.
  if (read.fromCache) {
    read = await byUserId(serverOnly: true);
    final confirmed = owned(read.profiles);
    if (confirmed != null) return confirmed;
  }

  // 3) Nothing under the uid. Follow the member's own pointers.
  final seen = <String>{};
  for (final raw in await pointerProfileIds()) {
    final id = raw.trim();
    if (id.isEmpty || !seen.add(id)) continue;
    final profile = await profileById(id);
    if (profile == null) continue;
    final owner = profile.userId.trim();
    if (owner == member || owner.isEmpty) {
      debugPrint(
        '[MemberProfileLookup] $member: profile $id found through a '
        'pointer (userId on the document: "${profile.userId}").',
      );
      return profile;
    }
    debugPrint(
      '[MemberProfileLookup] $member: pointer to profile $id '
      'ignored — it belongs to $owner.',
    );
  }

  // 4) Confirmed: this member has no matrimony profile.
  return null;
}
