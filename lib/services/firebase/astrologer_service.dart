import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/config/admin_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/working_hours.dart';
import '../../models/astrologer_account_model.dart';
import '../../models/astrologer_model.dart' as model;
import '../../models/astrologer_request_model.dart';
import '../../models/astrologer_review_model.dart';

/// Thrown when the chosen in-person appointment SESSION is already full (its
/// booking capacity has been reached).
class AppointmentSlotTakenException implements Exception {
  @override
  String toString() =>
      'That session has just filled up. Please pick another.';
}

/// Thrown when the admin tries to claim / analyze an `astrologer_requests`
/// document that is already completed, or that someone ELSE is mid-analysis on
/// (`workflowStatus == 'in_progress'` under a different astrologer).
class RequestClaimException implements Exception {
  /// Display name / email of whoever currently holds the request ('' when
  /// unknown).
  final String holder;

  /// True when the claim failed because the request is already completed.
  final bool alreadyCompleted;

  const RequestClaimException({this.holder = '', this.alreadyCompleted = false});

  @override
  String toString() => alreadyCompleted
      ? 'This request is already completed.'
      : 'Already being analyzed by '
          '${holder.isEmpty ? 'another astrologer' : holder}.';
}

/// Firestore CRUD + realtime streams for the astrologer side of the app:
/// `astrologers/{uid}` accounts and `astrologer_requests` (consultations,
/// inquiries, horoscope-matching requests).
class AstrologerService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Public per-date index of appointment SESSION booking counts for the
  /// internal astrology service
  /// (`astrology_booked_slots/{dateKey}` → `{morning: n, afternoon: n}`).
  /// Holds no PII, so any signed-in user may read it to see how full each
  /// session is (and hide full ones) without reading other users' requests.
  /// The count is updated in the same transaction that creates a booking, so it
  /// atomically enforces each session's capacity.
  DocumentReference<Map<String, dynamic>> _appointmentSlotsDoc(String dateKey) =>
      _db.collection('astrology_booked_slots').doc(dateKey);

  // ── Accounts ────────────────────────────────────────────────────────────
  /// Creates (or overwrites) the astrologer account document and marks the
  /// auth user's role as `astrologer`.
  Future<void> createAccount(String uid, AstrologerAccount account) async {
    final batch = _db.batch();
    batch.set(
      _db.collection(AppConstants.astrologersCollection).doc(uid),
      {
        ...account.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    batch.set(
      _db.collection(AppConstants.usersCollection).doc(uid),
      {
        'role': AppConstants.roleAstrologer,
        'displayName': account.fullName,
        'phone': account.mobile,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<AstrologerAccount?> getAccount(String uid) async {
    final doc = await _db
        .collection(AppConstants.astrologersCollection)
        .doc(uid)
        .get();
    if (!doc.exists) return null;
    return AstrologerAccount.fromFirestore(doc);
  }

  Stream<AstrologerAccount?> watchAccount(String uid) => _db
      .collection(AppConstants.astrologersCollection)
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? AstrologerAccount.fromFirestore(doc) : null);

  Future<void> updateAccount(String uid, Map<String, dynamic> data) => _db
      .collection(AppConstants.astrologersCollection)
      .doc(uid)
      .update({...data, 'updatedAt': FieldValue.serverTimestamp()});

  // ── Certificate upload (Cloudinary unsigned) ──────────────────────────────
  // Cloud name / preset are public client config (never the API secret).
  static const String _cloudName = 'dh8hzjx5q';
  static const String _uploadPreset = 'matrimony_profiles';

  /// Uploads a certificate file and returns its public URL. PDFs use the `raw`
  /// delivery type; images use `image`. Each upload gets a unique public_id so
  /// multiple certificates never overwrite one another.
  Future<String> uploadCertificate({
    required String uid,
    required File file,
    required String fileType,
  }) async {
    final resourceType = fileType.toLowerCase() == 'pdf' ? 'raw' : 'image';
    final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = 'jothida_matrimony/astrologers/$uid/certificates'
      ..fields['public_id'] = 'cert_${DateTime.now().millisecondsSinceEpoch}'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode == 200) {
      final url = (jsonDecode(response.body) as Map<String, dynamic>)['secure_url']
          as String?;
      if (url != null && url.isNotEmpty) return url;
    }
    throw Exception('Certificate upload failed (HTTP ${response.statusCode})');
  }

  // ── Admin verification actions ─────────────────────────────────────────────
  // Each method updates `astrologers/{uid}.status`. They log the attempt and
  // any failure so the cause (permission denied, missing doc, offline) is
  // visible in the console instead of surfacing as a vague "backend" error.

  /// Sets an astrologer's verification status. [uid] is the astrologer's
  /// Firestore document id (== their auth uid).
  Future<void> setVerificationStatus(
    String uid,
    VerificationStatus status, {
    String? rejectionReason,
  }) async {
    debugPrint('[AstrologerService] ✏️  setVerificationStatus('
        'uid=$uid, status=${status.name}) → astrologers/$uid');
    try {
      await updateAccount(uid, {
        'status': status.name,
        if (status == VerificationStatus.approved)
          'verifiedAt': FieldValue.serverTimestamp(),
        if (status == VerificationStatus.rejected && rejectionReason != null)
          'rejectionReason': rejectionReason,
      });
      debugPrint('[AstrologerService] ✅ status updated to ${status.name} for $uid');
    } on FirebaseException catch (e) {
      debugPrint('[AstrologerService] ❌ Firestore write failed '
          '(code=${e.code}): ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[AstrologerService] ❌ unexpected write failure: $e');
      rethrow;
    }
  }

  /// Approve a pending astrologer → they become visible to users and their
  /// dashboard verification banner clears on next load. Also notifies them.
  Future<void> approveAstrologer(String uid) async {
    await setVerificationStatus(uid, VerificationStatus.approved);
    await _notify(uid, 'Verification Approved',
        'Your astrologer profile has been verified successfully.',
        'astrologer_verified',
        id: 'astrologer_verified_$uid',
        data: {'route': '/astrologer-dashboard'});
  }

  /// Reject an astrologer's application (optionally with a reason) and notify
  /// them so they can update their details and reapply.
  Future<void> rejectAstrologer(String uid, {String reason = ''}) async {
    await setVerificationStatus(uid, VerificationStatus.rejected,
        rejectionReason: reason);
    final body = reason.trim().isEmpty
        ? 'Your astrologer verification request was rejected. Please update your details and submit again.'
        : 'Your astrologer verification request was rejected: ${reason.trim()}';
    await _notify(uid, 'Verification Rejected', body, 'astrologer_rejected',
        id: 'astrologer_rejected_$uid',
        data: {'route': '/astrologer-dashboard'});
  }

  /// Suspend a previously-approved astrologer → moves them back to
  /// "under review" (pending) so they lose live visibility without being
  /// permanently rejected.
  Future<void> suspendAstrologer(String uid) =>
      setVerificationStatus(uid, VerificationStatus.pending);

  /// Astrologer-initiated re-application after a rejection: status returns to
  /// `pending`, the rejection reason is cleared, and the account re-enters the
  /// admin verification queue.
  Future<void> reapplyForVerification(String uid) async {
    await _db
        .collection(AppConstants.astrologersCollection)
        .doc(uid)
        .set({
      'status': VerificationStatus.pending.name,
      'rejectionReason': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Best-effort in-app notification to a user/astrologer. Admins may create
  /// notifications (security rules), and the recipient reads their own. Never
  /// throws — a notification hiccup must not fail the verification action.
  ///
  /// [id] is a DETERMINISTIC doc id derived from the triggering doc + event,
  /// so a retried action rewrites the SAME document instead of adding a
  /// duplicate — and the `notifications`-onCreate push gate fires at most
  /// once per event.
  Future<void> _notify(
      String uid, String title, String body, String type,
      {String id = '', Map<String, dynamic>? data}) async {
    try {
      final doc = <String, dynamic>{
        'userId': uid,
        'title': title,
        'body': body,
        'type': type,
        if (data != null) 'data': data,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      final col = _db.collection(AppConstants.notificationsCollection);
      await (id.isEmpty ? col.add(doc) : col.doc(id).set(doc));
    } catch (e) {
      debugPrint('[AstrologerService] notify($uid) failed (non-fatal): $e');
    }
  }

  /// Replaces the embedded services list on the astrologer's account doc.
  Future<void> updateServices(
          String uid, List<model.AstrologerService> services) =>
      updateAccount(
          uid, {'services': services.map((s) => s.toMap()).toList()});

  /// Approved astrologers visible to matrimony users.
  Stream<List<AstrologerAccount>> watchApprovedAstrologers() => _db
      .collection(AppConstants.astrologersCollection)
      .where('status', isEqualTo: 'approved')
      .snapshots()
      .map((s) => s.docs.map(AstrologerAccount.fromFirestore).toList());

  /// Every astrologer account (any status). The directory filters out rejected
  /// accounts client-side so newly signed-up (pending) astrologers also appear,
  /// and no composite index is needed.
  Stream<List<AstrologerAccount>> watchAllAstrologers() => _db
      .collection(AppConstants.astrologersCollection)
      .snapshots()
      .map((s) => s.docs.map(AstrologerAccount.fromFirestore).toList());

  // ── Requests (consultations / inquiries / horoscope matching) ──────────
  /// Creates a request and returns its new doc id (so an auto-assigner can stamp
  /// the chosen astrologer onto it). When [request] is still UNASSIGNED
  /// (`astrologerId` empty), the astrologer notification is skipped — assignment
  /// notifies the chosen astrologer instead.
  Future<String> createRequest(AstrologerRequestModel request) async {
    final doc = await _db
        .collection(AppConstants.astrologerRequestsCollection)
        .add(request.toFirestore());
    // Notify the addressed astrologer (skipped for unassigned auto-assign
    // requests). The notification data carries the booking id + a deep-link
    // route so the FCM tap handler and the in-app inbox can open it (spec §8).
    if (request.astrologerId.trim().isNotEmpty) {
      await _notify(
        request.astrologerId,
        'New ${request.type.label} Request',
        request.isMatchAnalysis
            ? '${request.userName} paid for a match analysis. Accept within 12 '
                'working hours.'
            : '${request.userName} has requested a ${request.type.label}.',
        'new_match_analysis',
        id: 'new_match_analysis_${doc.id}',
        data: {
          'requestId': doc.id,
          'route': '/match-workspace/${doc.id}',
          'tab': 'matchAnalysis',
        },
      );
    }
    // Confirm to the user that payment succeeded and the booking is on its way
    // (spec §4: pay online → booking created → reaches astrologer).
    // Single-company service: user-facing copy never names the individual
    // employee, and report notifications open the bottom-nav Reports tab.
    if (request.userId.trim().isNotEmpty) {
      await _notify(
        request.userId,
        request.paid ? 'Payment Successful' : 'Booking Submitted',
        request.paid
            ? 'Your payment was received and your match-analysis request is '
                'now with our astrology team.'
            : 'Your ${request.type.label} request has been received by our '
                'astrology team.',
        'booking_submitted',
        id: 'booking_submitted_${doc.id}',
        data: {'requestId': doc.id, 'route': '/reports'},
      );
    }
    return doc.id;
  }

  /// Creates an in-person **appointment** request for the internal astrology
  /// service. Bookings are grouped into two daily SESSIONS (Morning /
  /// Afternoon), each with an admin-set [capacity]. The per-date session counts
  /// live in the public `astrology_booked_slots/{dateKey}` index and are read +
  /// incremented in the SAME transaction that creates the booking, so a session
  /// that is already full atomically throws [AppointmentSlotTakenException].
  /// Passing a null [capacity] skips the limit. Returns the new request id.
  Future<String> createAppointmentRequest(
    AstrologerRequestModel request, {
    int? capacity,
  }) async {
    if (request.visitDate == null || request.session.isEmpty) {
      throw ArgumentError('Appointment request needs a visitDate + session.');
    }
    // Auto-id document — many bookings share a session (unlike the old one-slot
    // lock), so the id can't be deterministic.
    final ref =
        _db.collection(AppConstants.astrologerRequestsCollection).doc();
    final slotsRef = _appointmentSlotsDoc(request.visitDateKey);
    final session = request.session;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(slotsRef);
      final current = (snap.data()?[session] as num?)?.toInt() ?? 0;
      if (capacity != null && current >= capacity) {
        throw AppointmentSlotTakenException();
      }
      tx.set(ref, request.toFirestore());
      tx.set(slotsRef, {session: current + 1}, SetOptions(merge: true));
    });
    final id = ref.id;
    // Notify the internal astrology team of the new appointment booking.
    await _notify(
      request.astrologerId,
      'New Appointment Booking',
      '${request.userName} booked a ${AppointmentSession.shortLabel(session)} '
          'appointment for ${request.visitDateKey}.',
      'new_match_analysis',
      id: 'new_match_analysis_$id',
      data: {
        'requestId': id,
        'route': '/match-workspace/$id',
        'tab': 'matchAnalysis',
      },
    );
    if (request.userId.trim().isNotEmpty) {
      await _notify(
        request.userId,
        'Appointment Confirmed',
        'Your appointment is confirmed. Booking ID: $id.',
        'booking_submitted',
        id: 'booking_submitted_$id',
        data: {'requestId': id, 'route': '/my-appointments'},
      );
    }
    return id;
  }

  /// Live `dateKey → {morning: count, afternoon: count}` for the internal
  /// astrology service, powering the appointment date/session picker so a full
  /// session greys out. Single-collection read (doc id = dateKey), no composite
  /// index needed.
  Stream<Map<String, Map<String, int>>> watchInternalSessionCounts() => _db
      .collection('astrology_booked_slots')
      .snapshots()
      .map((s) {
        final out = <String, Map<String, int>>{};
        for (final d in s.docs) {
          final data = d.data();
          out[d.id] = {
            AppointmentSession.morning:
                (data[AppointmentSession.morning] as num?)?.toInt() ?? 0,
            AppointmentSession.afternoon:
                (data[AppointmentSession.afternoon] as num?)?.toInt() ?? 0,
          };
        }
        return out;
      });

  /// EVERY in-person appointment booking (standalone consultations and
  /// horoscope-report visits alike), newest first. Powers the admin Appointment
  /// Management page.
  ///
  /// The filter is the booking's own `visitDateKey` — which is written for
  /// every appointment and left `''` for everything else — NOT the astrologer
  /// it happens to be addressed to. That distinction matters: assigning a
  /// booking to an employee overwrites `astrologerId` with their uid, so the
  /// previous `astrologerId == internal_astrology` query silently dropped every
  /// assigned booking off the admin's list.
  ///
  /// Single-field range query (automatic index, no composite index needed); the
  /// `hasAppointment` re-check and the sort stay client-side.
  Stream<List<AstrologerRequestModel>> watchAllAppointments() => _db
      .collection(AppConstants.astrologerRequestsCollection)
      .where('visitDateKey', isGreaterThan: '')
      .snapshots()
      .map((s) {
        final list = s.docs
            .map(AstrologerRequestModel.fromFirestore)
            .where((r) => r.hasAppointment)
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  /// Admin sets an appointment's status (Pending / Confirmed=accepted /
  /// Completed / Cancelled=rejected). Writes `updatedAt` + an audit entry and
  /// notifies the booking user so their Astrology page reflects it live. When an
  /// appointment is CANCELLED its slot is freed (removed from the booked-slots
  /// index) so it becomes bookable again.
  Future<void> setAppointmentStatus(
    AstrologerRequestModel r,
    AstrologerRequestStatus status,
  ) async {
    final label = switch (status) {
      AstrologerRequestStatus.pending => 'Marked as pending',
      AstrologerRequestStatus.accepted => 'Appointment confirmed',
      AstrologerRequestStatus.completed => 'Appointment completed',
      AstrologerRequestStatus.rejected => 'Appointment cancelled',
    };
    await _db
        .collection(AppConstants.astrologerRequestsCollection)
        .doc(r.id)
        .update({
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
      'respondedAt': FieldValue.serverTimestamp(),
      'history': FieldValue.arrayUnion([BookingHistoryEntry.now(label).toMap()]),
    });
    // Cancelling frees the slot for everyone else.
    if (status == AstrologerRequestStatus.rejected && r.hasAppointment) {
      await _freeSlot(r);
    }
    if (r.userId.trim().isNotEmpty) {
      await _notify(
        r.userId,
        'Appointment Update',
        '$label for ${r.visitDateKey}.',
        'appointment_status',
        // Status is part of the id: each distinct transition (confirmed,
        // completed, cancelled…) notifies once; retries of the SAME
        // transition collapse.
        id: 'appointment_status_${r.id}_${status.name}',
        data: {'requestId': r.id, 'route': '/my-appointments'},
      );
    }
  }

  /// Admin RESCHEDULES an appointment to a new day / session.
  ///
  /// The old session's capacity is released and the new one taken, so the
  /// booked-slots index stays honest for everyone else's date picker. The
  /// booking keeps its id, its payment and its history — only the visit moves —
  /// and the member is notified with the new date.
  Future<void> rescheduleAppointment(
    AstrologerRequestModel r, {
    required DateTime visitDate,
    required String session,
  }) async {
    final dateKey = '${visitDate.year.toString().padLeft(4, '0')}-'
        '${visitDate.month.toString().padLeft(2, '0')}-'
        '${visitDate.day.toString().padLeft(2, '0')}';
    if (dateKey == r.visitDateKey && session == r.session) return; // no-op

    final start = AppointmentSession.startMinutes(session);
    final label = '${AppointmentSession.shortLabel(session)} · $dateKey';
    await _db
        .collection(AppConstants.astrologerRequestsCollection)
        .doc(r.id)
        .update({
      'visitDate': Timestamp.fromDate(DateTime(
          visitDate.year, visitDate.month, visitDate.day)),
      'visitDateKey': dateKey,
      'session': session,
      'slotStartMinutes': start,
      'slotKey': '${(start ~/ 60).toString().padLeft(2, '0')}'
          '${(start % 60).toString().padLeft(2, '0')}',
      'updatedAt': FieldValue.serverTimestamp(),
      'history': FieldValue.arrayUnion(
          [BookingHistoryEntry.now('Rescheduled to $label').toMap()]),
    });

    // Move the capacity: free the old session, take the new one. Both are
    // best-effort merges — a failed index write must never undo the reschedule.
    await _freeSlot(r);
    try {
      await _appointmentSlotsDoc(dateKey)
          .set({session: FieldValue.increment(1)}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AstrologerService] reschedule slot claim skipped: $e');
    }

    if (r.userId.trim().isNotEmpty) {
      await _notify(
        r.userId,
        'Appointment Rescheduled',
        'Your appointment has been moved to $label.',
        'appointment_status',
        id: 'appointment_rescheduled_${r.id}_${dateKey}_$session',
        data: {'requestId': r.id, 'route': '/my-appointments'},
      );
    }
  }

  /// Hard-deletes an appointment and frees its slot.
  Future<void> deleteAppointment(AstrologerRequestModel r) async {
    await _db
        .collection(AppConstants.astrologerRequestsCollection)
        .doc(r.id)
        .delete();
    if (r.hasAppointment) await _freeSlot(r);
  }

  /// Decrements an appointment's session count in the public booked-slots index
  /// so the freed capacity becomes bookable again (used on cancel / delete).
  Future<void> _freeSlot(AstrologerRequestModel r) async {
    if (r.visitDateKey.isEmpty || r.session.isEmpty) return;
    await _appointmentSlotsDoc(r.visitDateKey).set(
      {r.session: FieldValue.increment(-1)},
      SetOptions(merge: true),
    );
  }

  /// Astrologer begins working on an accepted booking (spec §11:
  /// Accepted → Analysis In Progress). Sets the `inProgress` flag + audit trail
  /// and notifies the user. The addressed-astrologer update rule permits this.
  Future<void> startAnalysis(String requestId, {String userId = ''}) async {
    await _db
        .collection(AppConstants.astrologerRequestsCollection)
        .doc(requestId)
        .update({
      'inProgress': true,
      'workflowStatus': 'in_progress',
      'startedAt': FieldValue.serverTimestamp(),
      'history': FieldValue.arrayUnion(
          [BookingHistoryEntry.now('Analysis in progress').toMap()]),
    });
    if (userId.trim().isNotEmpty) {
      await _notify(userId, 'Analysis In Progress',
          'Our astrology team has started your match analysis.',
          'analysis_started',
          id: 'analysis_started_$requestId',
          data: {'requestId': requestId, 'route': '/reports'});
    }
  }

  /// Realtime stream of every request addressed to this astrologer.
  ///
  /// NOTE: intentionally a single-field equality query with NO `orderBy` — that
  /// combination would require a composite Firestore index and, until it was
  /// created, the stream would error (and every astrologer tab would show the
  /// "Try Again" state). The astrologer tabs already sort by `createdAt`
  /// client-side, so ordering here is unnecessary.
  Stream<List<AstrologerRequestModel>> watchRequestsForAstrologer(
          String astrologerId) =>
      _db
          .collection(AppConstants.astrologerRequestsCollection)
          .where('astrologerId', isEqualTo: astrologerId)
          .snapshots()
          .map((s) =>
              s.docs.map(AstrologerRequestModel.fromFirestore).toList());

  /// Realtime stream of every request assigned to the astrologer with this
  /// Gmail. This is the AUTHORITATIVE astrologer-dashboard query — it keys on
  /// the stable `astrologerEmail` stamped at assignment time, so requests show
  /// up even for an astrologer who was assigned work before their first login.
  /// Single-field equality (no composite index); callers sort client-side.
  Stream<List<AstrologerRequestModel>> watchRequestsForAstrologerEmail(
          String email) =>
      _db
          .collection(AppConstants.astrologerRequestsCollection)
          .where('astrologerEmail', isEqualTo: email)
          .snapshots()
          .map((s) =>
              s.docs.map(AstrologerRequestModel.fromFirestore).toList());

  /// Realtime stream of EVERY Match Analysis request addressed to the single
  /// internal astrology service ([kInternalAstrologyId]). Powers the internal
  /// Astrology Dashboard. Single-field equality query (no composite index);
  /// match-analysis filtering + newest-first sort are done client-side.
  Stream<List<AstrologerRequestModel>> watchAllMatchRequests() => _db
      .collection(AppConstants.astrologerRequestsCollection)
      .where('astrologerId', isEqualTo: kInternalAstrologyId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map(AstrologerRequestModel.fromFirestore)
            .where((r) => r.isMatchAnalysis)
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  /// Requests this matrimony user has sent (to track status).
  ///
  /// Single-field equality query with NO server-side `orderBy` (which would
  /// force a composite index and break the stream until it exists) — sorted
  /// newest-first client-side instead, mirroring [watchRequestsForAstrologer].
  Stream<List<AstrologerRequestModel>> watchRequestsByUser(String userId) =>
      _db
          .collection(AppConstants.astrologerRequestsCollection)
          .where('userId', isEqualTo: userId)
          .snapshots()
          .map((s) {
        final list =
            s.docs.map(AstrologerRequestModel.fromFirestore).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  Future<void> updateRequestStatus(
    String requestId,
    AstrologerRequestStatus status, {
    String astrologerName = '',
    String userId = '',
    int amount = 0,
    // The REAL Firebase uid of the responder (the internal astrology account).
    // Requests are addressed to the synthetic `internal_astrology` id, so we
    // stamp the responder's actual uid on accept — that's what the USER side
    // uses to open the same chat thread the internal account created.
    String responderUid = '',
  }) async {
    final who =
        astrologerName.trim().isEmpty ? 'the astrologer' : astrologerName.trim();
    String? label;
    switch (status) {
      case AstrologerRequestStatus.accepted:
        label = 'Accepted by $who';
        break;
      case AstrologerRequestStatus.rejected:
        label = 'Declined by $who';
        break;
      case AstrologerRequestStatus.completed:
        label = 'Report submitted';
        break;
      case AstrologerRequestStatus.pending:
        label = null;
        break;
    }
    await _db
        .collection(AppConstants.astrologerRequestsCollection)
        .doc(requestId)
        .update({
      'status': status.name,
      'respondedAt': FieldValue.serverTimestamp(),
      if (status == AstrologerRequestStatus.accepted && responderUid.isNotEmpty)
        'astrologerUid': responderUid,
      if (label != null)
        'history':
            FieldValue.arrayUnion([BookingHistoryEntry.now(label).toMap()]),
    });
    // Notify the user of the outcome (spec: Booking Accepted / Payment Pending /
    // rejected). Best-effort. Single-company service: the user-facing copy
    // NEVER names the individual employee — only "our astrology team" — and
    // report updates deep-link to the bottom-nav Reports tab.
    if (userId.trim().isEmpty) return;
    switch (status) {
      case AstrologerRequestStatus.accepted:
        await _notify(
            userId,
            'Booking Accepted',
            amount > 0
                ? 'Our astrology team accepted your request. Please pay '
                    '₹$amount to confirm.'
                : 'Our astrology team accepted your request.',
            'booking_accepted',
            id: 'booking_accepted_$requestId',
            data: {'requestId': requestId, 'route': '/reports'});
        break;
      case AstrologerRequestStatus.rejected:
        await _notify(
            userId,
            'Booking Declined',
            'Our astrology team is unable to take your request right now.',
            'booking_rejected',
            id: 'booking_rejected_$requestId',
            data: {'requestId': requestId, 'route': '/reports'});
        break;
      case AstrologerRequestStatus.completed:
        await _notify(userId, 'Report Ready',
            'Your analysis report is ready to view.', 'porutham_ready',
            id: 'porutham_ready_$requestId',
            data: {'requestId': requestId, 'route': '/reports'});
        break;
      case AstrologerRequestStatus.pending:
        break;
    }
  }

  /// Client-side expiry sweep (there is NO Cloud Functions backend): if [r] is
  /// still pending and past its [expiresAt], atomically flag it Expired, append
  /// the audit trail and notify the user according to the booking's reassign
  /// mode. The transaction guard means concurrent viewers never double-notify.
  ///
  /// Returns true if THIS call performed the expiry (so callers can avoid
  /// duplicate side-effects). Safe to call on every list refresh.
  Future<bool> expireRequestIfDue(AstrologerRequestModel r) async {
    if (!r.isExpiredByTime || r.expired) return false;
    final ref = _db
        .collection(AppConstants.astrologerRequestsCollection)
        .doc(r.id);
    bool flipped = false;
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final d = snap.data() as Map<String, dynamic>;
        if (d['status'] != 'pending' || d['expired'] == true) return;
        tx.update(ref, {
          'expired': true,
          'expiredAt': FieldValue.serverTimestamp(),
          'history': FieldValue.arrayUnion([
            BookingHistoryEntry.now('No response').toMap(),
            BookingHistoryEntry.now('Expired').toMap(),
          ]),
        });
        flipped = true;
      });
    } on FirebaseException catch (e) {
      // A user without write permission (rules) still sees the booking as
      // expired via the live time check — the flag write is best-effort.
      debugPrint('[AstrologerService] expire(${r.id}) skipped: ${e.code}');
      return false;
    }
    if (flipped) {
      // The deadline epoch keys the id: a booking reassigned after an expiry
      // gets a FRESH expiresAt, so a later second expiry still notifies —
      // while concurrent viewers of the SAME expiry collapse to one doc.
      final expiryId =
          'booking_expired_${r.id}_${r.expiresAt?.millisecondsSinceEpoch ?? 0}';
      if (r.reassignMode == BookingReassignMode.chooseLater) {
        await _notify(
          r.userId,
          'Astrologer did not respond',
          'The selected astrologer did not respond within the required time. '
              'Please choose another astrologer.',
          'booking_expired',
          id: expiryId,
          data: {'requestId': r.id, 'route': '/reports'},
        );
      } else if (r.reassignMode == BookingReassignMode.allowAdmin) {
        await _notify(
          r.userId,
          'Astrologer did not respond',
          'The selected astrologer did not respond in time. An admin will '
              'assign another astrologer to your booking.',
          'booking_expired',
          id: expiryId,
          data: {'requestId': r.id, 'route': '/reports'},
        );
      }
    }
    return flipped;
  }

  // ── Admin: full request queue + reassign / reminder ────────────────────────
  /// Realtime stream of EVERY astrologer request (admin Horoscope Requests
  /// page). Single-collection read with no `orderBy` (avoids a composite
  /// index); callers sort client-side.
  Stream<List<AstrologerRequestModel>> watchAllRequests() => _db
      .collection(AppConstants.astrologerRequestsCollection)
      .snapshots()
      .map((s) => s.docs.map(AstrologerRequestModel.fromFirestore).toList());

  /// Reassigns a request to a DIFFERENT astrologer (admin from Expired Bookings,
  /// or the user themselves in "choose another later" mode). Re-points the
  /// request, gives the new astrologer a fresh response window, clears the
  /// Expired flag, resets it to `pending` (the new astrologer must accept),
  /// records the audit trail and notifies both the new astrologer and the user.
  ///
  /// SPEC RULE: a booking belongs to exactly one astrologer — this MOVES it, it
  /// never duplicates it.
  Future<void> reassignRequest(
    String requestId, {
    required String astrologerId,
    required String astrologerName,
    bool byAdmin = true,
    String userId = '',
  }) async {
    final assignedLabel = byAdmin
        ? 'Assigned by Admin to $astrologerName'
        : 'Reassigned by you to $astrologerName';
    // Fresh 12 WORKING-hour window for the newly-assigned astrologer (spec §6).
    final expiresAt = matchAnalysisDeadline(DateTime.now());
    await _db
        .collection(AppConstants.astrologerRequestsCollection)
        .doc(requestId)
        .update({
      'astrologerId': astrologerId,
      'astrologerName': astrologerName,
      // The request now belongs to an astrologer again — never the admin.
      'assignedToAdmin': false,
      'status': AstrologerRequestStatus.pending.name,
      'respondedAt': null,
      'reassigned': true,
      'reassignedAt': FieldValue.serverTimestamp(),
      'expired': false,
      'expiredAt': null,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'history': FieldValue.arrayUnion([
        BookingHistoryEntry.now(assignedLabel).toMap(),
        BookingHistoryEntry.now('Waiting for response').toMap(),
      ]),
    });
    await _notify(
        astrologerId,
        'New Request Assigned',
        byAdmin
            ? 'A horoscope request has been assigned to you by the admin.'
            : 'A horoscope request has been assigned to you.',
        'request_reassigned',
        // Keyed per (request, assignee): a retry collapses, while a later
        // reassignment to a DIFFERENT astrologer still notifies them.
        id: 'request_reassigned_${requestId}_$astrologerId',
        data: {
          'requestId': requestId,
          'route': '/match-workspace/$requestId',
          'tab': 'matchAnalysis',
        });
    if (userId.trim().isNotEmpty) {
      // Single-company service: the user never learns which team member the
      // booking moved to.
      await _notify(
          userId,
          'Booking reassigned',
          'Your booking has been reassigned within our astrology team and '
              'will be handled shortly.',
          'booking_reassigned',
          id: 'booking_reassigned_${requestId}_$astrologerId',
          data: {'requestId': requestId, 'route': '/reports'});
    }
  }

  /// Admin nudge to an astrologer who hasn't acted on a pending request.
  /// Day-scoped deterministic id: a double-tapped "remind" can't duplicate,
  /// but the admin can still send a fresh reminder tomorrow.
  Future<void> sendRequestReminder(
    String astrologerId, {
    String message =
        'You have a pending horoscope request. Please accept or decline.',
  }) {
    final now = DateTime.now();
    final day = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return _notify(astrologerId, 'Pending Request Reminder', message,
        'request_reminder',
        id: 'request_reminder_${astrologerId}_$day',
        data: {'route': '/astrologer-dashboard'});
  }

  /// ADMIN claims a request to analyze it personally (spec §11 "Assign to Me" /
  /// "Analyze as Admin"). Runs as a TRANSACTION so two people can never hold
  /// the same request: it throws [RequestClaimException] when the request is
  /// already completed, or when someone ELSE is mid-analysis
  /// (`workflowStatus == 'in_progress'` under a different astrologer).
  /// Re-claiming a request the admin already holds is a harmless refresh, so
  /// "Analyze" keeps working after "Assign to Me".
  ///
  /// On success the request is stamped: astrologerId/Uid = [adminUid],
  /// astrologerEmail = lowercased [adminEmail], `assignedToAdmin: true`,
  /// status `accepted`, `assignedAt`, plus an 'Assigned to Admin' audit entry.
  /// With [startAnalysis] the same guarded write also moves the workflow to
  /// `in_progress` (used right before opening the analysis form).
  Future<void> claimRequestForAdmin({
    required String requestId,
    required String adminUid,
    required String adminEmail,
    bool startAnalysis = false,
  }) async {
    final email = adminEmail.trim().toLowerCase();
    final ref = _db
        .collection(AppConstants.astrologerRequestsCollection)
        .doc(requestId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw Exception('Request no longer exists.');
      }
      final d = snap.data() as Map<String, dynamic>;
      if (d['status'] == AstrologerRequestStatus.completed.name) {
        throw const RequestClaimException(alreadyCompleted: true);
      }
      final holderId = (d['astrologerId'] ?? '').toString();
      final holderEmail =
          (d['astrologerEmail'] ?? '').toString().trim().toLowerCase();
      final isMine = holderId == adminUid ||
          (holderEmail.isNotEmpty && holderEmail == email);
      final alreadyInProgress = d['workflowStatus'] == 'in_progress';
      if (alreadyInProgress && !isMine) {
        final holderName = (d['astrologerName'] ?? '').toString().trim();
        throw RequestClaimException(
            holder: holderName.isNotEmpty ? holderName : holderEmail);
      }
      final alreadyMine = isMine && d['assignedToAdmin'] == true;
      final entries = <Map<String, dynamic>>[
        if (!alreadyMine) BookingHistoryEntry.now('Assigned to Admin').toMap(),
        if (startAnalysis && !alreadyInProgress)
          BookingHistoryEntry.now('Analysis in progress').toMap(),
      ];
      tx.update(ref, {
        'astrologerId': adminUid,
        'astrologerUid': adminUid,
        'astrologerName': 'Admin',
        'astrologerEmail': email,
        'assignedToAdmin': true,
        'assignedAt': FieldValue.serverTimestamp(),
        'assignedBy': 'admin',
        'assignmentStatus': 'assigned',
        'status': AstrologerRequestStatus.accepted.name,
        'respondedAt': FieldValue.serverTimestamp(),
        // The admin holds it now — a lapsed acceptance window is moot.
        'expired': false,
        'expiredAt': null,
        if (startAnalysis) ...{
          'inProgress': true,
          'workflowStatus': 'in_progress',
          if (!alreadyInProgress) 'startedAt': FieldValue.serverTimestamp(),
        } else if (!alreadyInProgress)
          'workflowStatus': 'new',
        if (entries.isNotEmpty) 'history': FieldValue.arrayUnion(entries),
      });
    });
  }

  /// Uploads an analysis result file (image or PDF) for a match-analysis
  /// request and returns its public URL. PDFs use Cloudinary's `raw` delivery
  /// type; images use `image`. Each file gets a unique public_id so multiple
  /// files never overwrite one another.
  Future<String> uploadAnalysisFile({
    required String requestId,
    required File file,
    required String fileType,
  }) async {
    final resourceType = fileType.toLowerCase() == 'pdf' ? 'raw' : 'image';
    final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = 'jothida_matrimony/analysis/$requestId'
      ..fields['public_id'] =
          'analysis_${DateTime.now().millisecondsSinceEpoch}'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode == 200) {
      final url =
          (jsonDecode(response.body) as Map<String, dynamic>)['secure_url']
              as String?;
      if (url != null && url.isNotEmpty) return url;
    }
    throw Exception('Analysis file upload failed (HTTP ${response.statusCode})');
  }

  /// Saves an in-progress report WITHOUT completing it (spec §11 "Save Draft").
  /// The request stays `pending`, so it never reaches the user's Reports page;
  /// the astrologer can re-open and continue editing later.
  Future<void> saveDraft({
    required String requestId,
    required String text,
    required List<String> images,
    required List<String> pdfs,
  }) =>
      _db
          .collection(AppConstants.astrologerRequestsCollection)
          .doc(requestId)
          .update({
        'analysisText': text,
        'analysisImages': images,
        'analysisPdfs': pdfs,
        'draftSavedAt': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion(
            [BookingHistoryEntry.now('Draft saved').toMap()]),
      });

  /// Saves the structured Marriage Compatibility Report as a DRAFT — the
  /// request stays `pending`, so it never reaches the user's Reports page.
  Future<void> saveCompatReport({
    required String requestId,
    required Map<String, dynamic> data,
  }) =>
      _db
          .collection(AppConstants.astrologerRequestsCollection)
          .doc(requestId)
          .update({
        'compatReport': data,
        'draftSavedAt': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion(
            [BookingHistoryEntry.now('Compatibility report draft saved').toMap()]),
      });

  /// WHO-completed stamp added to every report submission (spec §11): the
  /// signed-in submitter's uid + LOWERCASED email, with role 'admin' for the
  /// privileged admin accounts and 'employee' for astrology-team members.
  Map<String, dynamic> _completionStamp() {
    final user = FirebaseAuth.instance.currentUser;
    final email = (user?.email ?? '').trim().toLowerCase();
    return {
      'completedBy': user?.uid ?? '',
      'completedByEmail': email,
      'completedByRole':
          AdminConfig.isPrivilegedEmail(email) ? 'admin' : 'employee',
    };
  }

  /// Stores the finished structured Marriage Compatibility Report and flips the
  /// request to `completed` (same completion stamps as [submitAnalysis]).
  Future<void> submitCompatReport({
    required String requestId,
    required Map<String, dynamic> data,
  }) =>
      _db
          .collection(AppConstants.astrologerRequestsCollection)
          .doc(requestId)
          .update({
        'compatReport': data,
        'status': AstrologerRequestStatus.completed.name,
        'workflowStatus': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'respondedAt': FieldValue.serverTimestamp(),
        ..._completionStamp(),
        'history': FieldValue.arrayUnion(
            [BookingHistoryEntry.now('Compatibility report submitted').toMap()]),
      });

  /// One-shot fetch of a single request (e.g. to resolve its owner for the
  /// "report ready" notification). Null when the doc doesn't exist.
  Future<AstrologerRequestModel?> getRequestById(String requestId) async {
    final d = await _db
        .collection(AppConstants.astrologerRequestsCollection)
        .doc(requestId)
        .get();
    return d.exists ? AstrologerRequestModel.fromFirestore(d) : null;
  }

  /// Submits the astrologer's completed analysis for [requestId]: stores the
  /// report text + already-uploaded file URLs and flips the request to
  /// `completed`. The astrologer-update rule on `astrologer_requests` permits
  /// this write for the addressed astrologer.
  Future<void> submitAnalysis({
    required String requestId,
    required String text,
    required List<String> images,
    required List<String> pdfs,
  }) =>
      _db
          .collection(AppConstants.astrologerRequestsCollection)
          .doc(requestId)
          .update({
        'analysisText': text,
        'analysisImages': images,
        'analysisPdfs': pdfs,
        'status': AstrologerRequestStatus.completed.name,
        'workflowStatus': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'respondedAt': FieldValue.serverTimestamp(),
        ..._completionStamp(),
        'history': FieldValue.arrayUnion(
            [BookingHistoryEntry.now('Report submitted').toMap()]),
      });

  /// Marks a match-analysis booking paid (dev-mode: no real gateway). Records
  /// the demo transaction id + audit trail and notifies the user that payment
  /// succeeded and the booking is confirmed. Mirrors the consultation
  /// pay-after-accept flow. The booking OWNER performs this write (the rules
  /// allow the owner to update `paid`/`paidAt`/`paymentId`/`history`).
  Future<void> markAnalysisPaid(
    String requestId, {
    required String paymentId,
    String userId = '',
    String astrologerId = '',
  }) async {
    await _db
        .collection(AppConstants.astrologerRequestsCollection)
        .doc(requestId)
        .update({
      'paid': true,
      'paidAt': FieldValue.serverTimestamp(),
      'paymentId': paymentId,
      'history': FieldValue.arrayUnion([
        BookingHistoryEntry.now('Payment received ($paymentId)').toMap(),
      ]),
    });
    await _bumpBookingCount(astrologerId);
    if (userId.trim().isNotEmpty) {
      await _notify(userId, 'Payment Successful',
          'Your payment was successful. Your booking is confirmed.',
          'payment_success',
          id: 'payment_success_$requestId',
          data: {'requestId': requestId, 'route': '/reports'});
    }
  }

  /// Best-effort +1 to an astrologer's confirmed-booking counter (drives the
  /// "Most Booked Astrologers" directory section). Never throws — a counter
  /// hiccup must not fail the payment.
  Future<void> _bumpBookingCount(String astrologerId) async {
    if (astrologerId.trim().isEmpty) return;
    try {
      await _db
          .collection(AppConstants.astrologersCollection)
          .doc(astrologerId)
          .update({'bookingCount': FieldValue.increment(1)});
    } catch (e) {
      debugPrint('[AstrologerService] bumpBookingCount failed (non-fatal): $e');
    }
  }

  // ── Ratings & reviews (astrologers/{id}/reviews subcollection) ─────────────
  // Reviews live in a subcollection of the astrologer document:
  //   astrologers/{astrologerId}/reviews/{userId}
  // The doc id is the rating user's uid, which enforces one review per user per
  // astrologer (a re-submit edits the same doc, never a duplicate) and lets the
  // security rule check ownership directly from the path. The astrologer
  // document's `rating` / `reviewCount` / `ratingBreakdown` are kept as a
  // denormalised aggregate so directory cards and the Top-Rated section can
  // sort/show without reading every review.

  /// The `astrologers/{astrologerId}/reviews` subcollection reference.
  CollectionReference<Map<String, dynamic>> _reviewsCol(String astrologerId) =>
      _db
          .collection(AppConstants.astrologersCollection)
          .doc(astrologerId)
          .collection(AppConstants.astrologerReviewsSubcollection);

  /// Live reviews for an astrologer, newest first. The subcollection is already
  /// scoped to one astrologer, so no `where`/composite index is needed; sorted
  /// client-side by recency.
  Stream<List<AstrologerReviewModel>> watchReviews(String astrologerId) =>
      _reviewsCol(astrologerId).snapshots().map((s) {
        final list = s.docs
            .map((d) =>
                AstrologerReviewModel.fromFirestore(d, astrologerId: astrologerId))
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  /// The signed-in user's own review of [astrologerId], or null if none.
  Future<AstrologerReviewModel?> getMyReview(
      String astrologerId, String userId) async {
    final doc = await _reviewsCol(astrologerId).doc(userId).get();
    return doc.exists
        ? AstrologerReviewModel.fromFirestore(doc, astrologerId: astrologerId)
        : null;
  }

  /// Creates or edits the user's single review, then refreshes the astrologer's
  /// aggregate rating. The doc id (= [userId]) makes a re-submit an edit, never
  /// a duplicate.
  Future<void> submitReview({
    required String astrologerId,
    required String userId,
    required String userName,
    required int rating,
    String review = '',
  }) async {
    final ref = _reviewsCol(astrologerId).doc(userId);
    final existing = await ref.get();
    await ref.set({
      'astrologerId': astrologerId,
      'userId': userId,
      'userName': userName,
      'rating': rating,
      'review': review,
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _recomputeAstrologerRating(astrologerId);
  }

  /// Recomputes `rating` (mean), `reviewCount` and `ratingBreakdown` on the
  /// astrologer document from all of its reviews. Updates only those aggregate
  /// fields (a write the security rules allow any signed-in user to make).
  Future<void> _recomputeAstrologerRating(String astrologerId) async {
    final snap = await _reviewsCol(astrologerId).get();
    final ratings = snap.docs
        .map((d) => (d.data()['rating'] as num?)?.toInt() ?? 0)
        .where((r) => r >= 1 && r <= 5)
        .toList();
    final count = ratings.length;
    final avg =
        count == 0 ? 0.0 : ratings.reduce((a, b) => a + b) / count;
    final breakdown = <String, int>{};
    for (final r in ratings) {
      breakdown['$r'] = (breakdown['$r'] ?? 0) + 1;
    }
    await _db
        .collection(AppConstants.astrologersCollection)
        .doc(astrologerId)
        .set({
      'rating': double.parse(avg.toStringAsFixed(2)),
      'reviewCount': count,
      'ratingBreakdown': breakdown,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Sum of completed-request amounts → earnings shown on the dashboard.
  ///
  /// Filters by `astrologerId` only (single-field index, always available) and
  /// applies the `status == completed` filter client-side. Two equality `where`
  /// clauses on different fields would otherwise require a composite index, and
  /// `amount` is read through `num` so a value stored as a double (e.g. 199.0)
  /// can never crash the stream with a bad `as int` cast.
  Stream<int> watchEarnings(String astrologerId) => _db
      .collection(AppConstants.astrologerRequestsCollection)
      .where('astrologerId', isEqualTo: astrologerId)
      .snapshots()
      .map((s) => s.docs.where((d) => d.data()['status'] == 'completed').fold<int>(
          0, (sum, d) => sum + ((d.data()['amount'] ?? 0) as num).toInt()));
}
