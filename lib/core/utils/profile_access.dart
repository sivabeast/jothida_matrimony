import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/profile_model.dart';
import '../../providers/interest_provider.dart';

/// **Who may talk to whom** — the one answer the whole app asks before it
/// offers Chat, Contact Details or a Horoscope Compatibility Report.
///
/// The rule has two halves, and both already existed; what was missing was a
/// single place that combined them, so Contact Details enforced one thing while
/// Chat enforced another:
///
///  * a **mutually accepted interest** connects two members, whatever their
///    visibility setting — this is the private-profile path (spec §3);
///  * a **Public** profile is a standing invitation, so the same actions open
///    immediately without an interest round-trip (spec §4).
///
/// Visibility is the member's own `contactPrivacy` choice from the profile
/// wizard — `'public'` or `'private'`, defaulting to private for every legacy
/// profile that predates the setting. There is deliberately no second
/// visibility field: adding one would leave two switches disagreeing about the
/// same question.
///
/// This decides what the UI OFFERS. It is not the security boundary — the
/// Firestore rules enforce exactly the same two conditions on `contacts/`,
/// `chats/` and the request collections, so a tampered client that skips the
/// button gets a permission error rather than a conversation (spec §32).
enum MemberAccess {
  /// A mutually accepted interest exists. Everything a connection unlocks is
  /// available, including the profile download.
  connected,

  /// No accepted interest, but the owner publishes their profile. Chat,
  /// Contact and the report are available; connection-only extras are not.
  publicProfile,

  /// Private, and no accepted interest. Send an interest and wait.
  locked,
}

extension MemberAccessX on MemberAccess {
  /// Whether Chat / Contact / Horoscope Report may be offered at all.
  bool get canCommunicate => this != MemberAccess.locked;

  /// True only for a mutually accepted interest. Guards the extras that are
  /// about a RELATIONSHIP rather than about reachability — chiefly the profile
  /// download, which a public profile does not hand out.
  bool get isConnected => this == MemberAccess.connected;
}

/// Resolves [MemberAccess] between the signed-in member and [profile].
///
/// Call from `build`: it watches the live interest streams, so accepting an
/// interest opens the actions without a manual refresh.
MemberAccess watchMemberAccess(WidgetRef ref, ProfileModel profile) {
  final accepted = ref.watch(interestStatusForProfileProvider(profile.id)) ==
      InterestUiStatus.accepted;
  if (accepted) return MemberAccess.connected;
  return profile.isContactPublic
      ? MemberAccess.publicProfile
      : MemberAccess.locked;
}

/// The non-reactive form, for callbacks and guards that run once (a button
/// handler re-checking before it acts).
MemberAccess readMemberAccess(WidgetRef ref, ProfileModel profile) {
  final accepted = ref.read(interestStatusForProfileProvider(profile.id)) ==
      InterestUiStatus.accepted;
  if (accepted) return MemberAccess.connected;
  return profile.isContactPublic
      ? MemberAccess.publicProfile
      : MemberAccess.locked;
}
