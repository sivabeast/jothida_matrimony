import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/config/admin_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/working_hours.dart';
import '../../models/astrologer_account_model.dart';
import '../../models/astrologer_model.dart' as model;
import '../../models/astrologer_request_model.dart';
import '../../models/astrologer_review_model.dart';

/// Thrown when an in-person appointment slot is already taken by another user.
class AppointmentSlotTakenException implements Exception {
  @override
  String toString() =>
      'That time slot has just been booked. Please pick another.';
}

/// Firestore CRUD + realtime streams for the astrologer side of the app:
/// `astrologers/{uid}` accounts and `astrologer_requests` (consultations,
/// inquiries, horoscope-matching requests).
class AstrologerService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Public per-date index of taken appointment slot keys for the internal
  /// astrology service (`astrology_booked_slots/{dateKey}` → `{taken: [...]}`).
  /// Holds no PII, so any signed-in user may read it to grey out booked slots
  /// without reading other users' requests. The authoritative one-per-slot lock
  /// is the deterministic appointment doc id.
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
        'astrologer_verified');
  }

  /// Reject an astrologer's application (optionally with a reason) and notify
  /// them so they can update their details and reapply.
  Future<void> rejectAstrologer(String uid, {String reason = ''}) async {
    await setVerificationStatus(uid, VerificationStatus.rejected,
        rejectionReason: reason);
    final body = reason.trim().isEmpty
        ? 'Your astrologer verification request was rejected. Please update your details and submit again.'
        : 'Your astrologer verification request was rejected: ${reason.trim()}';
    await _notify(uid, 'Verification Rejected', body, 'astrologer_rejected');
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
  Future<void> _notify(
      String uid, String title, String body, String type,
      {Map<String, dynamic>? data}) async {
    try {
      await _db.collection(AppConstants.notificationsCollection).add({
        'userId': uid,
        'title': title,
        'body': body,
        'type': type,
        if (data != null) 'data': data,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
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
  Future<void> createRequest(AstrologerRequestModel request) async {
    final doc = await _db
        .collection(AppConstants.astrologerRequestsCollection)
        .add(request.toFirestore());
    // Notify the astrologer of the new (already-paid) request. The notification
    // data carries the booking id + a deep-link route so the FCM tap handler
    // and the in-app inbox can open the exact booking (spec §8).
    await _notify(
      request.astrologerId,
      'New ${request.type.label} Request',
      request.isMatchAnalysis
          ? '${request.userName} paid for a match analysis. Accept within 12 '
              'working hours.'
          : '${request.userName} has requested a ${request.type.label}.',
      'new_match_analysis',
      data: {
        'requestId': doc.id,
        'route': '/match-workspace/${doc.id}',
        'tab': 'matchAnalysis',
      },
    );
    // Confirm to the user that payment succeeded and the booking is on its way
    // (spec §4: pay online → booking created → reaches astrologer).
    if (request.userId.trim().isNotEmpty) {
      await _notify(
        request.userId,
        request.paid ? 'Payment Successful' : 'Booking Submitted',
        request.paid
            ? 'Your payment was received and your match-analysis booking has '
                'been sent to ${request.astrologerName.isEmpty ? 'the astrologer' : request.astrologerName}.'
            : 'Your ${request.type.label} request has been sent to '
                '${request.astrologerName.isEmpty ? 'the astrologer' : request.astrologerName}.',
        'booking_submitted',
        data: {'requestId': doc.id, 'route': '/my-analysis'},
      );
    }
  }

  /// Creates an in-person **appointment** request for the internal astrology
  /// service (Horoscope Compatibility Report). Uses a DETERMINISTIC doc id +
  /// transaction so a single slot can be held by only ONE user — a second
  /// booking of the same slot throws [AppointmentSlotTakenException]. Also drops
  /// the slot into the public booked-slots index and notifies both parties.
  /// Returns the new request id (used as the user-facing Booking ID).
  Future<String> createAppointmentRequest(
      AstrologerRequestModel request) async {
    if (request.visitDate == null || request.slotStartMinutes == null) {
      throw ArgumentError('Appointment request needs a visitDate + slot.');
    }
    final id = AstrologerRequestModel.appointmentDocId(
        request.astrologerId, request.visitDate!, request.slotStartMinutes!);
    final ref = _db
        .collection(AppConstants.astrologerRequestsCollection)
        .doc(id);
    final slotsRef = _appointmentSlotsDoc(request.visitDateKey);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) throw AppointmentSlotTakenException();
      tx.set(ref, request.toFirestore());
      tx.set(
          slotsRef,
          {
            'taken': FieldValue.arrayUnion([request.slotKey])
          },
          SetOptions(merge: true));
    });
    // Notify the internal astrology team of the new (already-paid) request.
    await _notify(
      request.astrologerId,
      'New Horoscope Report Booking',
      '${request.userName} booked a horoscope compatibility report '
          '(appointment ${request.visitDateKey}).',
      'new_match_analysis',
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
        'Your horoscope compatibility report appointment is confirmed. '
            'Booking ID: $id.',
        'booking_submitted',
        data: {'requestId': id, 'route': '/my-analysis'},
      );
    }
    return id;
  }

  /// Live `dateKey → {taken slot keys}` for the internal astrology service,
  /// powering the appointment date/slot picker. Single-collection read (doc id =
  /// dateKey), so no composite index is needed.
  Stream<Map<String, Set<String>>> watchInternalBookedSlots() => _db
      .collection('astrology_booked_slots')
      .snapshots()
      .map((s) {
        final out = <String, Set<String>>{};
        for (final d in s.docs) {
          final taken =
              (d.data()['taken'] as List?)?.cast<String>() ?? const [];
          out[d.id] = taken.toSet();
        }
        return out;
      });

  /// Astrologer begins working on an accepted booking (spec §11:
  /// Accepted → Analysis In Progress). Sets the `inProgress` flag + audit trail
  /// and notifies the user. The addressed-astrologer update rule permits this.
  Future<void> startAnalysis(String requestId, {String userId = ''}) async {
    await _db
        .collection(AppConstants.astrologerRequestsCollection)
        .doc(requestId)
        .update({
      'inProgress': true,
      'startedAt': FieldValue.serverTimestamp(),
      'history': FieldValue.arrayUnion(
          [BookingHistoryEntry.now('Analysis in progress').toMap()]),
    });
    if (userId.trim().isNotEmpty) {
      await _notify(userId, 'Analysis In Progress',
          'The astrologer has started your match analysis.', 'analysis_started',
          data: {'requestId': requestId, 'route': '/my-analysis'});
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
    // rejected). Best-effort.
    if (userId.trim().isEmpty) return;
    switch (status) {
      case AstrologerRequestStatus.accepted:
        await _notify(
            userId,
            'Booking Accepted',
            amount > 0
                ? '$who accepted your request. Please pay ₹$amount to confirm.'
                : '$who accepted your request.',
            'booking_accepted');
        break;
      case AstrologerRequestStatus.rejected:
        await _notify(userId, 'Booking Declined',
            '$who is unable to take your request right now.', 'booking_rejected');
        break;
      case AstrologerRequestStatus.completed:
        await _notify(userId, 'Report Ready',
            'Your analysis report from $who is ready to view.', 'porutham_ready');
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
      if (r.reassignMode == BookingReassignMode.chooseLater) {
        await _notify(
          r.userId,
          'Astrologer did not respond',
          'The selected astrologer did not respond within the required time. '
              'Please choose another astrologer.',
          'booking_expired',
        );
      } else if (r.reassignMode == BookingReassignMode.allowAdmin) {
        await _notify(
          r.userId,
          'Astrologer did not respond',
          'The selected astrologer did not respond in time. An admin will '
              'assign another astrologer to your booking.',
          'booking_expired',
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
        'request_reassigned');
    if (userId.trim().isNotEmpty) {
      await _notify(
          userId,
          'Booking reassigned',
          'Your booking has been assigned to $astrologerName, who now has '
              '24 hours to respond.',
          'booking_reassigned');
    }
  }

  /// Admin nudge to an astrologer who hasn't acted on a pending request.
  Future<void> sendRequestReminder(
    String astrologerId, {
    String message =
        'You have a pending horoscope request. Please accept or decline.',
  }) =>
      _notify(astrologerId, 'Pending Request Reminder', message,
          'request_reminder');

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
        'completedAt': FieldValue.serverTimestamp(),
        'respondedAt': FieldValue.serverTimestamp(),
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
          'payment_success');
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
