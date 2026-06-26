import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../../models/consultation_model.dart';
import '../../models/settlement_model.dart';

/// Thrown when a Direct-Visit slot is already taken by another user.
class ConsultationSlotTakenException implements Exception {
  @override
  String toString() => 'That time slot has just been booked. Please pick another.';
}

/// Firestore CRUD + realtime streams for the consultation booking system
/// (`consultations`). Revenue is subscription-only — there is NO commission, so
/// the booking `amount` is recorded as the astrologer's earning in full.
class ConsultationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppConstants.consultationsCollection);

  DocumentReference<Map<String, dynamic>> _doc(String id) => _col.doc(id);

  /// Public per-(astrologer, date) index of taken slot keys, so a user's slot
  /// picker can grey out booked slots without reading other users' bookings.
  DocumentReference<Map<String, dynamic>> _bookedSlotsDoc(
          String astrologerId, String dateKey) =>
      _db
          .collection(AppConstants.astrologersCollection)
          .doc(astrologerId)
          .collection('booked_slots')
          .doc(dateKey);

  /// Creates a consultation booking.
  ///
  /// Direct-Visit bookings use a DETERMINISTIC doc id and a transaction so a
  /// slot can be held by only one user (a second booking fails). In-App
  /// bookings have no slot and use an auto id. Returns the new booking id.
  Future<String> createBooking(ConsultationBooking b) async {
    String id;
    if (b.isDirectVisit && b.visitDate != null && b.slotStartMinutes != null) {
      id = ConsultationBooking.directVisitDocId(
          b.astrologerId, b.visitDate!, b.slotStartMinutes!);
      final ref = _doc(id);
      final slotsRef = _bookedSlotsDoc(b.astrologerId, b.dateKey);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (snap.exists &&
            ConsultationBooking.fromFirestore(snap).isActive) {
          throw ConsultationSlotTakenException();
        }
        tx.set(ref, b.toFirestore());
        tx.set(
            slotsRef,
            {
              'taken': FieldValue.arrayUnion([b.slotKey])
            },
            SetOptions(merge: true));
      });
    } else {
      final ref = await _col.add(b.toFirestore());
      id = ref.id;
    }
    await _notify(
      b.astrologerId,
      'New consultation request',
      '${b.userName} requested a ${b.mode.label.toLowerCase()}.',
      'consultation_request',
    );
    return id;
  }

  /// Creates an In-App booking that is paid UPFRONT ("Book & Pay"). The payment
  /// is collected into the admin account and held until settlement; the booking
  /// lands at `paid` awaiting the astrologer's Accept / Reject. Returns the id.
  ///
  /// In-App bookings have no slot, so this always uses an auto id (no slot
  /// transaction needed).
  Future<String> bookAndPay(ConsultationBooking b,
      {required String paymentId}) async {
    final paid = b.copyWith(
      status: ConsultationStatus.paid,
      paid: true,
      paymentId: paymentId,
      paidAt: DateTime.now(),
    );
    final ref = await _col.add(paid.toFirestore());
    await _bumpBookingCount(b.astrologerId);
    await _notify(
      b.astrologerId,
      'New paid booking',
      '${b.userName} paid ₹${b.amount} for a consultation. Accept or reject the request.',
      'consultation_request',
    );
    await _notify(
      b.userId,
      'Payment Successful',
      'Your payment of ₹${b.amount} was successful. Waiting for ${b.astrologerName} to accept.',
      'payment_success',
    );
    return ref.id;
  }

  /// Every consultation addressed to an astrologer (no `orderBy` → no composite
  /// index; callers sort client-side).
  Stream<List<ConsultationBooking>> watchForAstrologer(String astrologerId) =>
      _col
          .where('astrologerId', isEqualTo: astrologerId)
          .snapshots()
          .map((s) => s.docs.map(ConsultationBooking.fromFirestore).toList());

  /// Every consultation a user has booked.
  Stream<List<ConsultationBooking>> watchForUser(String userId) => _col
      .where('userId', isEqualTo: userId)
      .snapshots()
      .map((s) => s.docs.map(ConsultationBooking.fromFirestore).toList());

  /// Every consultation on the platform (admin only — settlement/payout
  /// derivation). No `orderBy` → no composite index; callers sort client-side.
  Stream<List<ConsultationBooking>> watchAll() => _col
      .snapshots()
      .map((s) => s.docs.map(ConsultationBooking.fromFirestore).toList());

  /// Live stream of payout settlement-history batches, newest first (client-side
  /// sort to avoid an index). Read by the admin Settlement History.
  Stream<List<Settlement>> watchSettlements() => _db
      .collection(AppConstants.settlementsCollection)
      .snapshots()
      .map((s) {
        final list = s.docs.map(Settlement.fromFirestore).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  /// Live `dateKey → {taken slot keys}` for an astrologer (only dates that have
  /// bookings exist), powering the user's calendar + slot picker.
  Stream<Map<String, Set<String>>> watchBookedSlots(String astrologerId) => _db
      .collection(AppConstants.astrologersCollection)
      .doc(astrologerId)
      .collection('booked_slots')
      .snapshots()
      .map((s) {
        final out = <String, Set<String>>{};
        for (final d in s.docs) {
          final taken = (d.data()['taken'] as List?)?.cast<String>() ?? const [];
          out[d.id] = taken.toSet();
        }
        return out;
      });

  /// Astrologer accepts / rejects.
  ///
  /// In-App bookings are paid UPFRONT, so on accept they move straight to
  /// `analysisInProgress` (the consultation/chat starts immediately); a
  /// Direct-Visit booking is confirmed (`accepted` = "Visit Confirmed", paid in
  /// person at the visit). On reject the booking is `rejected`; a paid In-App
  /// booking then awaits an admin refund.
  Future<void> respond(ConsultationBooking b, bool accept) async {
    final newStatus = !accept
        ? ConsultationStatus.rejected
        : (b.isInApp
            ? ConsultationStatus.analysisInProgress
            : ConsultationStatus.accepted);
    await _doc(b.id).update({
      'status': newStatus.key,
      'respondedAt': FieldValue.serverTimestamp(),
    });
    if (!accept) {
      await _releaseSlot(b);
      final body = b.paid
          ? 'Your ${b.mode.label.toLowerCase()} request was declined. A refund will be processed shortly.'
          : 'Your ${b.mode.label.toLowerCase()} request was declined.';
      await _notify(b.userId, 'Consultation declined', body,
          'consultation_rejected');
    } else {
      final msg = b.isInApp
          ? 'Your consultation was accepted. You can now chat with ${b.astrologerName}.'
          : 'Your visit is confirmed. See you at the scheduled time.';
      await _notify(b.userId, 'Consultation accepted', msg,
          'consultation_accepted');
    }
  }

  /// Records a successful payment (In-App). Status → `paid`.
  Future<void> markPaid(ConsultationBooking b, {String paymentId = ''}) async {
    await _doc(b.id).update({
      'paid': true,
      'paymentId': paymentId,
      'paidAt': FieldValue.serverTimestamp(),
      'status': ConsultationStatus.paid.key,
    });
    await _bumpBookingCount(b.astrologerId);
    await _notify(b.astrologerId, 'Payment received',
        '${b.userName} paid ₹${b.amount}. You can start the analysis.',
        'consultation_paid');
    // Confirm to the user that payment succeeded and the booking is confirmed.
    await _notify(b.userId, 'Payment Successful',
        'Your payment of ₹${b.amount} was successful. Your consultation is confirmed.',
        'payment_success');
  }

  /// Best-effort adjust of an astrologer's confirmed-booking counter (drives the
  /// "Most Booked Astrologers" section). +1 on a paid booking, -1 on a refund.
  /// Never throws.
  Future<void> _bumpBookingCount(String astrologerId, {int by = 1}) async {
    if (astrologerId.trim().isEmpty) return;
    try {
      await _db
          .collection(AppConstants.astrologersCollection)
          .doc(astrologerId)
          .update({'bookingCount': FieldValue.increment(by)});
    } catch (_) {
      // Non-fatal — a counter hiccup must not fail the payment.
    }
  }

  /// Astrologer begins the deep analysis. Status → `analysisInProgress`.
  Future<void> startAnalysis(String id) =>
      _doc(id).update({'status': ConsultationStatus.analysisInProgress.key});

  /// Astrologer submits the report. Status → `reportSubmitted`.
  Future<void> submitReport(
    ConsultationBooking b, {
    required String text,
    required List<String> images,
    required List<String> pdfs,
  }) async {
    await _doc(b.id).update({
      'reportText': text,
      'reportImages': images,
      'reportPdfs': pdfs,
      'status': ConsultationStatus.reportSubmitted.key,
    });
    await _notify(b.userId, 'Your report is ready',
        '${b.astrologerName} submitted your consultation report.',
        'consultation_report');
  }

  /// Marks the consultation completed. A Direct-Visit booking is also flagged
  /// paid (cash collected at the visit) so it counts toward completed earnings.
  Future<void> complete(ConsultationBooking b) async {
    await _doc(b.id).update({
      'status': ConsultationStatus.completed.key,
      'completedAt': FieldValue.serverTimestamp(),
      if (b.isDirectVisit) ...{
        'paid': true,
        if (b.paidAt == null) 'paidAt': FieldValue.serverTimestamp(),
      },
    });
    await _notify(b.userId, 'Consultation completed',
        'Your consultation with ${b.astrologerName} is complete.',
        'consultation_completed');
  }

  /// User cancels a not-yet-accepted booking (frees the slot).
  Future<void> cancel(ConsultationBooking b) async {
    await _doc(b.id).update({'status': ConsultationStatus.cancelled.key});
    await _releaseSlot(b);
  }

  /// Admin refunds a paid booking the astrologer rejected. Status → `refunded`;
  /// the booking drops out of the astrologer's settleable amount. Best-effort
  /// decrement of the booking counter (the booking never went ahead).
  Future<void> refund(ConsultationBooking b) async {
    await _doc(b.id).update({
      'status': ConsultationStatus.refunded.key,
      'refundedAt': FieldValue.serverTimestamp(),
    });
    await _bumpBookingCount(b.astrologerId, by: -1);
    await _notify(b.userId, 'Refund Processed',
        'Your ₹${b.amount} payment has been refunded.', 'consultation_refunded');
  }

  /// Admin pays out (settles) a set of delivered bookings to an astrologer —
  /// 100%, no commission. Flags each booking `settled` with a shared
  /// `settlementId`, writes one `settlements/{id}` history doc, and notifies the
  /// astrologer. Only settleable bookings are touched. Returns the settlement id
  /// (empty if nothing was due).
  Future<String> settleAstrologer({
    required String astrologerId,
    required String astrologerName,
    required List<ConsultationBooking> bookings,
    String note = '',
  }) async {
    final due = bookings.where((b) => b.isSettleable).toList();
    if (due.isEmpty) return '';

    final settlementRef =
        _db.collection(AppConstants.settlementsCollection).doc();
    final amount = due.fold<int>(0, (acc, b) => acc + b.amount);
    final settlement = Settlement(
      id: settlementRef.id,
      astrologerId: astrologerId,
      astrologerName: astrologerName,
      amount: amount,
      bookingCount: due.length,
      bookingIds: due.map((b) => b.id).toList(),
      note: note,
      createdAt: DateTime.now(),
    );

    final batch = _db.batch();
    batch.set(settlementRef, settlement.toFirestore());
    for (final b in due) {
      batch.update(_doc(b.id), {
        'settled': true,
        'settledAt': FieldValue.serverTimestamp(),
        'settlementId': settlementRef.id,
      });
    }
    await batch.commit();

    await _notify(
      astrologerId,
      'Payout Settled',
      '₹$amount has been settled to your account for ${due.length} '
          'consultation${due.length == 1 ? '' : 's'}.',
      'payout_settled',
    );
    return settlementRef.id;
  }

  /// Frees a Direct-Visit slot in the public index when a booking is
  /// rejected / cancelled.
  Future<void> _releaseSlot(ConsultationBooking b) async {
    if (!b.isDirectVisit || b.dateKey.isEmpty || b.slotKey.isEmpty) return;
    try {
      await _bookedSlotsDoc(b.astrologerId, b.dateKey).set({
        'taken': FieldValue.arrayRemove([b.slotKey])
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[ConsultationService] releaseSlot failed (non-fatal): $e');
    }
  }

  /// Best-effort in-app notification (never throws).
  Future<void> _notify(
      String uid, String title, String body, String type) async {
    try {
      await _db.collection(AppConstants.notificationsCollection).add({
        'userId': uid,
        'title': title,
        'body': body,
        'type': type,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[ConsultationService] notify($uid) failed (non-fatal): $e');
    }
  }
}
