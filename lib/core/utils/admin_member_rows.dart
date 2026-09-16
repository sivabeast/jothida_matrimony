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
