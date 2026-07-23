import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/astrologer_team_member.dart';
import '../../models/payroll_payment.dart';

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

  /// Automatically assigns [requestId] to the ACTIVE, available employee who
  /// currently has the FEWEST pending (open, not-yet-completed) reports and
  /// stamps the assignment onto the request.
  ///
  /// Selection: lowest [pendingCount] wins; ties break by least-recently
  /// assigned ([lastAssignedAt], round-robin) then [createdAt] for a stable
  /// first round. Disabled (admin) or Unavailable employees are skipped. This
  /// keeps the workload balanced with no admin action.
  ///
  /// IMPORTANT: a not-yet-signed-in ("Awaiting sign-in") employee is STILL
  /// eligible — the request is stamped with their stable Gmail
  /// ([AstrologerRequestModel.astrologerEmail]); it appears on their dashboard
  /// the moment they first log in. Returns the chosen member, or null when no
  /// active employee exists (the request stays unassigned for the admin).
  /// [resetStatus] (default true) stamps the workflow back to Pending — right
  /// for horoscope reports. Pass FALSE for paid appointments, which are already
  /// CONFIRMED at creation and must never fall back to a pending state.
  Future<AstrologerTeamMember?> assignRequest(String requestId,
      {bool resetStatus = true}) async {
    final snap = await _team.where('active', isEqualTo: true).get();
    final active = snap.docs.map(AstrologerTeamMember.fromFirestore).toList();
    if (active.isEmpty) {
      debugPrint('[AstrologyTeam] assignRequest($requestId): NO ACTIVE '
          'EMPLOYEES registered — the request cannot be assigned. Register a '
          'Gmail under Admin > Employees.');
      return null;
    }
    // Prefer employees who have marked themselves Available (spec §6). If every
    // active employee is Unavailable we still assign to one of them rather than
    // orphan a PAID report: an unassigned request is invisible on every Pending
    // Reports page, which is exactly the failure this method exists to prevent.
    var members = active.where((m) => m.available).toList();
    if (members.isEmpty) {
      debugPrint('[AstrologyTeam] assignRequest($requestId): every active '
          'employee is Unavailable — assigning anyway so the paid report is '
          'not orphaned.');
      members = active;
    }
    members.sort((a, b) {
      // 1) Fewest pending reports first (the balancing signal).
      if (a.pendingCount != b.pendingCount) {
        return a.pendingCount.compareTo(b.pendingCount);
      }
      // 2) Tie-break: least-recently assigned (round robin).
      final at = a.lastAssignedAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.lastAssignedAt?.millisecondsSinceEpoch ?? 0;
      if (at != bt) return at.compareTo(bt);
      // 3) Stable order for the very first round.
      final ac = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bc = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return ac.compareTo(bc);
    });
    final chosen = members.first;

    // ── The assignment write, ALONE in its transaction. ────────────────────
    //
    // This used to also bump the chosen employee's workload counters in the
    // same transaction. That coupled the thing that matters (stamping the
    // assignment onto the request, which is what puts it on the employee's
    // Pending Reports page) to a purely advisory counter on a DIFFERENT
    // document with DIFFERENT security rules — so a single rejected counter
    // write silently rolled back the assignment and the paid report never
    // reached anyone.
    // Email of whoever the request ends up assigned to — `chosen` when we wrote
    // the assignment, or the pre-existing assignee when someone beat us to it.
    String? assignedEmail;
    var wroteAssignment = false;
    await _db.runTransaction((tx) async {
      final reqRef = _requests.doc(requestId);
      final reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) {
        debugPrint('[AstrologyTeam] assignRequest($requestId): request no '
            'longer exists.');
        return;
      }
      // Idempotent — never double-assign if it already has an astrologer.
      final existing =
          (reqSnap.data()?['astrologerEmail'] ?? '').toString().trim();
      if (existing.isNotEmpty) {
        debugPrint('[AstrologyTeam] assignRequest($requestId): already '
            'assigned to $existing — no-op.');
        assignedEmail = existing;
        return;
      }
      tx.update(reqRef,
          _assignmentData(chosen, assignedBy: 'auto', resetStatus: resetStatus));
      assignedEmail = chosen.email;
      wroteAssignment = true;
    });

    if (assignedEmail == null) return null;

    if (wroteAssignment) {
      // Workload counters — BEST EFFORT and deliberately after the fact. A
      // failure here only skews round-robin balancing for one request; it must
      // never undo an assignment that already succeeded. Only bumped when WE
      // wrote the assignment, so a retry can't inflate someone's count.
      try {
        await _team.doc(chosen.id).update({
          'pendingCount': FieldValue.increment(1),
          'lastAssignedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('[AstrologyTeam] assignRequest($requestId): workload counter '
            'update failed (assignment kept): $e');
      }
      debugPrint('[AstrologyTeam] assignRequest($requestId) → ${chosen.email}.');
      return chosen;
    }

    // Someone else assigned it first — report the REAL assignee so the caller
    // notifies the right employee.
    return active.firstWhere((m) => m.email == assignedEmail,
        orElse: () => chosen);
  }

  /// Flags a request whose auto-assignment could not complete, so it is
  /// VISIBLE rather than silently stuck. The admin's Horoscope Requests page
  /// filters on `assignmentStatus` and can assign it manually; the user's
  /// Reports tab self-heal retries it. Restricted to `assignmentStatus` +
  /// `history`, both of which the request owner is allowed to write.
  Future<void> markAssignmentFailed(String requestId, String reason) async {
    try {
      await _requests.doc(requestId).update({
        'assignmentStatus': 'unassigned',
        'history': FieldValue.arrayUnion([
          BookingHistoryEntry.now('Auto-assignment failed: $reason').toMap(),
        ]),
      });
    } catch (e) {
      debugPrint('[AstrologyTeam] markAssignmentFailed($requestId) failed: $e');
    }
  }

  /// The canonical assignment payload written onto a request. Emails are always
  /// stored LOWERCASED so the astrologer-dashboard query + security rule match
  /// reliably, and every workflow field the app relies on is set in one place.
  static Map<String, dynamic> _assignmentData(
    AstrologerTeamMember m, {
    required String assignedBy,
    bool resetStatus = true,
  }) {
    final name = m.displayName.trim().isEmpty ? m.email : m.displayName;
    return {
      // assignedAstrologerId = the real uid once linked, else the registry key.
      'astrologerId': m.uid.isNotEmpty ? m.uid : m.id,
      'astrologerUid': m.uid,
      'astrologerEmail': m.email.trim().toLowerCase(),
      'astrologerName': name,
      'assignedAt': FieldValue.serverTimestamp(),
      'assignedBy': assignedBy,
      'assignmentStatus': 'assigned',
      if (resetStatus) 'workflowStatus': 'new',
      if (resetStatus) 'status': AstrologerRequestStatus.pending.name,
      if (resetStatus) 'inProgress': false,
      'history': FieldValue.arrayUnion([
        BookingHistoryEntry.now(
                'Assigned to $name (${assignedBy == 'auto' ? 'round robin' : 'admin'})')
            .toMap(),
      ]),
    };
  }

  /// Assigns [requestId] to a SPECIFIC team member (manual assignment, spec).
  /// Writes every assignment field + bumps the member's workload counters.
  /// Admin-only per rules.
  Future<void> assignToAstrologer(
    String requestId,
    AstrologerTeamMember m, {
    String assignedBy = 'admin',
  }) async {
    await _requests
        .doc(requestId)
        .update(_assignmentData(m, assignedBy: assignedBy));
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

  /// Admin sets the exact total commission already paid to an employee (used by
  /// the employee details screen's editable field). Stamps `lastPaidDate`.
  Future<void> setPaidCommission(String emailKey, int paidCommission) =>
      _team.doc(emailKey).update({
        'paidCommission': paidCommission,
        'lastPaidDate': FieldValue.serverTimestamp(),
      });

  // ── Weekly payroll ("Mark As Paid") ────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _payroll =>
      _db.collection(AppConstants.payrollPaymentsCollection);

  /// Closes the employee's CURRENT payroll cycle: records one payout document
  /// in `payroll_payments` (the weekly payment history) and stamps
  /// `lastPaidDate` on the registry entry — which is the cycle cut-off, so the
  /// next week's commission starts again from ₹0 instead of accumulating.
  /// [amount] = cycle commission being paid; [reportsCount] = completed reports
  /// covered; [periodStart] = the previous cut-off (null for the first payout).
  Future<void> markPayrollPaid(
    AstrologerTeamMember m, {
    required int amount,
    required int reportsCount,
    required int ratePerReport,
  }) async {
    final batch = _db.batch();
    batch.set(_payroll.doc(), {
      'employeeId': m.id,
      'employeeEmail': m.email,
      'employeeName': m.displayName.trim().isEmpty ? m.email : m.displayName,
      'amount': amount,
      'reportsCount': reportsCount,
      'ratePerReport': ratePerReport,
      'periodStart':
          m.lastPaidDate == null ? null : Timestamp.fromDate(m.lastPaidDate!),
      'paidAt': FieldValue.serverTimestamp(),
    });
    batch.update(_team.doc(m.id), {
      'lastPaidDate': FieldValue.serverTimestamp(), // new cycle cut-off
      'paidCommission': FieldValue.increment(amount),
      'salaryStatus': 'paid',
    });
    await batch.commit();
  }

  /// Payment history for ONE employee, newest first (admin history view and the
  /// employee's own earnings page). Single-field filter — no composite index;
  /// sorted client-side.
  Stream<List<PayrollPayment>> watchPayrollHistory(String emailKey) =>
      _payroll.where('employeeId', isEqualTo: emailKey).snapshots().map((s) {
        final list = s.docs.map(PayrollPayment.fromFirestore).toList();
        list.sort((a, b) => b.paidAt.compareTo(a.paidAt));
        return list;
      });
}
