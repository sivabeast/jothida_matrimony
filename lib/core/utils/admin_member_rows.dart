/// The rows of the admin All Users page — every registered member, whatever
/// their privacy settings, contact sharing or verification state.
///
/// Two gaps used to hide real members from the admin:
///
///  * rows came ONLY from `users/{uid}` documents, so a profile whose account
///    document is missing (created before accounts were mirrored, or left
///    behind by a partial delete) never appeared at all; and
///  * the account list was cut at a small unordered limit.
///
/// Member privacy is deliberately not consulted here: it decides what OTHER
/// MEMBERS see, never what the admin sees.
library;

import '../../models/profile_model.dart';
import '../../models/user_model.dart';

/// [users] plus a synthesized row for every non-dummy profile in
/// [profilesByUid] that has no account document. Test profiles (`isDummy`)
/// stay in the Test Data tool that manages them.
List<UserModel> adminMemberRows(
  List<UserModel> users,
  Map<String, ProfileModel> profilesByUid,
) {
  final known = {for (final u in users) u.uid};
  return [
    ...users,
    for (final p in profilesByUid.values)
      if (!p.isDummy && p.userId.trim().isNotEmpty && !known.contains(p.userId))
        UserModel(
          uid: p.userId,
          displayName: p.fullName,
          gender: p.gender,
          isProfileComplete: true,
          createdAt: p.createdAt,
          updatedAt: p.updatedAt,
        ),
  ];
}

/// `uid → profile` for the admin lists: every profile under its `userId`
/// (the first seen wins — [profiles] is newest-first), plus a profile whose
/// `userId` is BLANK under the member whose account document points at it
/// (`users/{uid}.profileId`). That is the same linkage the admin Edit Profile
/// lookup follows, so a member the editor can open is never listed as
/// "No profile". A pointer to a profile owned by someone else is ignored.
Map<String, ProfileModel> profilesByMember(
  List<ProfileModel> profiles,
  List<UserModel> users,
) {
  final byUid = <String, ProfileModel>{};
  for (final p in profiles) {
    final owner = p.userId.trim();
    if (owner.isNotEmpty) byUid.putIfAbsent(owner, () => p);
  }
  final byId = {for (final p in profiles) p.id: p};
  for (final u in users) {
    if (byUid.containsKey(u.uid)) continue;
    final linked = byId[(u.profileId ?? '').trim()];
    if (linked != null && linked.userId.trim().isEmpty) byUid[u.uid] = linked;
  }
  return byUid;
}
