import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/astrologer_team_member.dart';

/// Firestore CRUD + the smart auto-assignment for the internal astrology TEAM
/// (`astrology_team/{emailKey}`).
///
/// Admins provision members by Gmail; astrologers sign in with Google only.
/// New Horoscope Analysis requests are auto-assigned to the assignable member
/// with the LOWEST open-request count, with a round-robin tie-break — so the
/// workload stays balanced and disabled members are skipped immediately.
class AstrologyTeamService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _team =>
      _db.collection(AppConstants.astrologyTeamCollection);

  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection(AppConstants.astrologerRequestsCollection);

  // ── Admin: registry CRUD ────────────────────────────────────────────────

  /// Registers a new team member by Gmail. Idempotent (merge) so re-adding an
  /// existing Gmail just refreshes the display name and re-enables it.
  Future<void> addMember({required String email, String displayName = ''}) {
    final key = AstrologerTeamMember.keyFor(email);
    return _team.doc(key).set({
      'email': key,
      'displayName': displayName.trim(),
      'active': true,
      'pendingCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Admin enable/disable. Takes effect immediately for the next assignment.
  Future<void> setActive(String emailKey, bool active) =>
      _team.doc(emailKey).update({'active': active});

  Future<void> removeMember(String emailKey) => _team.doc(emailKey).delete();

  /// All team members (admin list), newest first. Single-collection read.
  Stream<List<AstrologerTeamMember>> watchAll() => _team.snapshots().map((s) {
        final list = s.docs.map(AstrologerTeamMember.fromFirestore).toList();
        list.sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0)));
        return list;
      });

  // ── Login lookups ─────────────────────────────────────────────────────────

  /// The registry entry for a Gmail, or null if the admin never registered it.
  Future<AstrologerTeamMember?> getByEmail(String email) async {
    final doc = await _team.doc(AstrologerTeamMember.keyFor(email)).get();
    return doc.exists ? AstrologerTeamMember.fromFirestore(doc) : null;
  }

  /// Live registry entry for a signed-in astrologer, looked up by email so the
  /// dashboard reflects admin enable/disable in real time.
  Stream<AstrologerTeamMember?> watchByEmail(String email) => _team
      .doc(AstrologerTeamMember.keyFor(email))
      .snapshots()
      .map((d) => d.exists ? AstrologerTeamMember.fromFirestore(d) : null);

  /// Links the astrologer's real uid on first sign-in and stamps lastLoginAt.
  Future<void> linkUid(
    String emailKey, {
    required String uid,
    String displayName = '',
    String photoUrl = '',
  }) =>
      _team.doc(emailKey).set({
        'uid': uid,
        'lastLoginAt': FieldValue.serverTimestamp(),
        if (displayName.trim().isNotEmpty) 'displayName': displayName.trim(),
        if (photoUrl.trim().isNotEmpty) 'photoUrl': photoUrl.trim(),
      }, SetOptions(merge: true));

  /// Flags the auth user document with the `astrologer` role so the router gates
  /// them to the astrologer portal (robust on cold start / deep links). Allowed
  /// by a registry-gated rule on `users/{uid}`.
  Future<void> promoteToAstrologerRole(String uid) =>
      _db.collection(AppConstants.usersCollection).doc(uid).set({
        'role': AppConstants.roleAstrologer,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  // ── Smart auto-assignment ───────────────────────────────────────────────

  /// Picks the best assignable member for [requestId] and stamps it onto the
  /// request, bumping that member's pending counter + round-robin cursor.
  ///
  /// Selection: lowest [AstrologerTeamMember.pendingCount]; ties broken by the
  /// oldest [lastAssignedAt] (round-robin). Disabled / not-yet-signed-in members
  /// are never chosen. Returns the chosen member, or null when there is no
  /// assignable astrologer (request stays unassigned for the admin to handle).
  Future<AstrologerTeamMember?> assignRequest(String requestId) async {
    final snap = await _team.where('active', isEqualTo: true).get();
    final members = snap.docs
        .map(AstrologerTeamMember.fromFirestore)
        .where((m) => m.isLinked)
        .toList();
    if (members.isEmpty) {
      debugPrint('[AstrologyTeam] assignRequest($requestId): no assignable '
          'astrologers — leaving unassigned.');
      return null;
    }
    members.sort((a, b) {
      final byPending = a.pendingCount.compareTo(b.pendingCount);
      if (byPending != 0) return byPending;
      final at = a.lastAssignedAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.lastAssignedAt?.millisecondsSinceEpoch ?? 0;
      return at.compareTo(bt); // oldest assigned first (round-robin)
    });
    final chosen = members.first;
    final name =
        chosen.displayName.trim().isEmpty ? chosen.email : chosen.displayName;

    await _db.runTransaction((tx) async {
      final reqRef = _requests.doc(requestId);
      final reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) return;
      // Idempotent: never double-assign if someone already claimed it.
      if ((reqSnap.data()?['astrologerUid'] ?? '').toString().trim().isNotEmpty) {
        return;
      }
      tx.update(_team.doc(chosen.id), {
        'pendingCount': FieldValue.increment(1),
        'lastAssignedAt': FieldValue.serverTimestamp(),
      });
      tx.update(reqRef, {
        'astrologerId': chosen.uid,
        'astrologerUid': chosen.uid,
        'astrologerName': name,
        'history': FieldValue.arrayUnion([
          BookingHistoryEntry.now('Auto-assigned to $name').toMap(),
        ]),
      });
    });
    debugPrint('[AstrologyTeam] assignRequest($requestId) → $name '
        '(${chosen.uid}); pending was ${chosen.pendingCount}.');
    return chosen;
  }

  /// Decrements a member's open-request counter once they submit a report.
  /// Looked up by uid (the member doc is keyed by email). Best-effort.
  Future<void> decrementPendingForUid(String uid) async {
    if (uid.trim().isEmpty) return;
    try {
      final q = await _team.where('uid', isEqualTo: uid).limit(1).get();
      if (q.docs.isEmpty) return;
      await q.docs.first.reference
          .update({'pendingCount': FieldValue.increment(-1)});
    } catch (e) {
      debugPrint('[AstrologyTeam] decrementPendingForUid($uid) failed: $e');
    }
  }
}
