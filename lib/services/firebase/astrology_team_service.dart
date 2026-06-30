import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/astrologer_team_member.dart';

/// Thrown by [AstrologyTeamService.addMember] when the Gmail is already a
/// registered astrologer, so the admin sees a clear "already exists" message.
class AstrologerExistsException implements Exception {
  final String email;
  const AstrologerExistsException(this.email);
  @override
  String toString() => 'Astrologer $email is already registered.';
}

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

  /// Registers a new team member by Gmail. Rejects a duplicate Gmail with
  /// [AstrologerExistsException]; any Firestore failure (e.g. permissions)
  /// propagates so the caller can show the real reason.
  Future<void> addMember({required String email, String displayName = ''}) async {
    final key = AstrologerTeamMember.keyFor(email);
    final existing = await _team.doc(key).get();
    if (existing.exists) {
      throw AstrologerExistsException(key);
    }
    await _team.doc(key).set({
      'email': key,
      'displayName': displayName.trim(),
      'active': true,
      'uid': '',
      'pendingCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Admin enable/disable. Takes effect immediately for the next assignment.
  Future<void> setActive(String emailKey, bool active) =>
      _team.doc(emailKey).update({'active': active});

  /// Admin edits an astrologer's editable details (e.g. display name, photo).
  Future<void> updateMember(String emailKey, Map<String, dynamic> data) =>
      _team.doc(emailKey).update(data);

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

  /// Round-robin assigns [requestId] to the next ACTIVE astrologer and stamps
  /// the assignment onto the request.
  ///
  /// Selection is pure ROUND ROBIN: the active astrologer assigned least
  /// recently wins (oldest [lastAssignedAt] first; never-assigned members go
  /// first), with createdAt as a stable tie-break — so with astrologers A, B
  /// the sequence is A, B, A, B … Disabled (admin) astrologers are skipped.
  ///
  /// IMPORTANT: a not-yet-signed-in ("Awaiting sign-in") astrologer is STILL
  /// eligible — the request is stamped with their stable Gmail
  /// ([AstrologerRequestModel.astrologerEmail]); it appears on their dashboard
  /// the moment they first log in. Returns the chosen member, or null when no
  /// active astrologer exists (the request stays unassigned for the admin).
  Future<AstrologerTeamMember?> assignRequest(String requestId) async {
    final snap = await _team.where('active', isEqualTo: true).get();
    final members =
        snap.docs.map(AstrologerTeamMember.fromFirestore).toList();
    if (members.isEmpty) {
      debugPrint('[AstrologyTeam] assignRequest($requestId): no active '
          'astrologers — leaving unassigned.');
      return null;
    }
    members.sort((a, b) {
      final at = a.lastAssignedAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.lastAssignedAt?.millisecondsSinceEpoch ?? 0;
      if (at != bt) return at.compareTo(bt); // least-recently assigned first
      final ac = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bc = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return ac.compareTo(bc); // stable order for the first round
    });
    final chosen = members.first;
    final name =
        chosen.displayName.trim().isEmpty ? chosen.email : chosen.displayName;

    await _db.runTransaction((tx) async {
      final reqRef = _requests.doc(requestId);
      final reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) return;
      // Idempotent: never double-assign if it already has an astrologer.
      if ((reqSnap.data()?['astrologerEmail'] ?? '')
          .toString()
          .trim()
          .isNotEmpty) {
        return;
      }
      tx.update(_team.doc(chosen.id), {
        'pendingCount': FieldValue.increment(1),
        'lastAssignedAt': FieldValue.serverTimestamp(),
      });
      tx.update(reqRef, {
        // astrologerId carries the uid once linked, else the registry key — but
        // astrologerEmail is the stable dashboard/isolation key.
        'astrologerId': chosen.uid.isNotEmpty ? chosen.uid : chosen.id,
        'astrologerUid': chosen.uid,
        'astrologerEmail': chosen.email,
        'astrologerName': name,
        'assignedAt': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([
          BookingHistoryEntry.now('Auto-assigned to $name').toMap(),
        ]),
      });
    });
    debugPrint('[AstrologyTeam] assignRequest($requestId) → $name '
        '(${chosen.email}).');
    return chosen;
  }

  /// Admin reassigns [requestId] to a specific team member: stamps the new
  /// astrologer (id/uid/email/name + assignedAt), resets it to pending/not-
  /// started, and bumps the new member's workload. Admin-only (rules).
  Future<void> reassignTo(String requestId, AstrologerTeamMember m) async {
    final name = m.displayName.trim().isEmpty ? m.email : m.displayName;
    await _requests.doc(requestId).update({
      'astrologerId': m.uid.isNotEmpty ? m.uid : m.id,
      'astrologerUid': m.uid,
      'astrologerEmail': m.email,
      'astrologerName': name,
      'assignedAt': FieldValue.serverTimestamp(),
      'status': AstrologerRequestStatus.pending.name,
      'inProgress': false,
      'reassigned': true,
      'reassignedAt': FieldValue.serverTimestamp(),
      'history': FieldValue.arrayUnion([
        BookingHistoryEntry.now('Reassigned by admin to $name').toMap(),
      ]),
    });
    await _team.doc(m.id).update({
      'pendingCount': FieldValue.increment(1),
      'lastAssignedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Decrements a member's open-request counter once they submit a report.
  /// Keyed by the member's Gmail (the doc id), so it works regardless of uid.
  /// Best-effort — a counter hiccup must never fail the report submission.
  Future<void> decrementPendingForEmail(String email) async {
    if (email.trim().isEmpty) return;
    try {
      await _team
          .doc(AstrologerTeamMember.keyFor(email))
          .update({'pendingCount': FieldValue.increment(-1)});
    } catch (e) {
      debugPrint('[AstrologyTeam] decrementPendingForEmail($email) failed: $e');
    }
  }
}
