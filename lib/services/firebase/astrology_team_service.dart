import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
  Future<void> addMember({
    required String email,
    String displayName = '',
    String mobile = '',
    int weeklySalary = 0,
  }) async {
    final key = AstrologerTeamMember.keyFor(email);
    final existing = await _team.doc(key).get();
    if (existing.exists) {
      throw AstrologerExistsException(key);
    }
    await _team.doc(key).set({
      'email': key,
      'displayName': displayName.trim(),
      'mobile': mobile.trim(),
      'active': true,
      'available': true,
      'weeklySalary': weeklySalary,
      'salaryStatus': 'pending',
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

  /// The astrologer sets their own Available / Unavailable status (spec §6).
  Future<void> setAvailable(String emailKey, bool available) =>
      _team.doc(emailKey).update({'available': available});

  /// The astrologer deletes their OWN registration (spec §5). Permitted by the
  /// email-gated delete rule; the caller signs out afterwards.
  Future<void> deleteSelf(String emailKey) => _team.doc(emailKey).delete();

  // Cloudinary unsigned upload (cloud name / preset are public client config).
  static const String _cloudName = 'dh8hzjx5q';
  static const String _uploadPreset = 'matrimony_profiles';

  /// Uploads an astrologer's profile photo to Cloudinary and returns the URL.
  Future<String> uploadPhoto(File file) async {
    final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = 'jothida_matrimony/astrology_team'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));
    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode == 200) {
      final url = (jsonDecode(response.body) as Map<String, dynamic>)['secure_url']
          as String?;
      if (url != null && url.isNotEmpty) return url;
    }
    throw Exception('Photo upload failed (HTTP ${response.statusCode})');
  }

  Future<void> removeMember(String emailKey) => _team.doc(emailKey).delete();

  /// Admin deletes an astrologer and SAFELY reassigns their unfinished requests
  /// to another active astrologer (spec §2). Deletes the member first, then
  /// clears each unfinished request's assignment and re-runs round-robin
  /// assignment (which now excludes the deleted member).
  Future<void> deleteMemberAndReassign(AstrologerTeamMember m) async {
    final q = await _requests.where('astrologerEmail', isEqualTo: m.email).get();
    final unfinished =
        q.docs.where((d) => (d.data()['status'] ?? '') != 'completed').toList();
    await _team.doc(m.id).delete();
    for (final d in unfinished) {
      // Clear the old assignment so the round-robin assigner re-picks.
      await d.reference.update({
        'astrologerEmail': '',
        'astrologerUid': '',
        'astrologerId': '',
        'astrologerName': '',
        'assignedAt': null,
      });
      await assignRequest(d.id);
    }
  }

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
    final members = snap.docs
        .map(AstrologerTeamMember.fromFirestore)
        // Skip astrologers who have marked themselves Unavailable (spec §6).
        .where((m) => m.available)
        .toList();
    if (members.isEmpty) {
      debugPrint('[AstrologyTeam] assignRequest($requestId): no active + '
          'available astrologers — leaving unassigned.');
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

  /// Called when an astrologer submits a completed report: decrements their open
  /// counter and stamps `lastSubmittedAt` (admin performance view). Keyed by the
  /// member's Gmail so it works regardless of uid. Best-effort.
  Future<void> markReportSubmitted(String email) async {
    if (email.trim().isEmpty) return;
    try {
      await _team.doc(AstrologerTeamMember.keyFor(email)).update({
        'pendingCount': FieldValue.increment(-1),
        'lastSubmittedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[AstrologyTeam] markReportSubmitted($email) failed: $e');
    }
  }

  /// Admin sets an astrologer's weekly salary + payment status (spec §13).
  Future<void> setSalary(String emailKey,
          {int? weeklySalary, String? salaryStatus, bool markPaid = false}) =>
      _team.doc(emailKey).update({
        if (weeklySalary != null) 'weeklySalary': weeklySalary,
        if (salaryStatus != null) 'salaryStatus': salaryStatus,
        if (markPaid) 'lastPaidDate': FieldValue.serverTimestamp(),
        if (markPaid) 'salaryStatus': 'paid',
      });
}
