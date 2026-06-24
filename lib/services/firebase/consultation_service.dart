import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../../models/consultation_model.dart';

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

  /// Astrologer accepts / rejects. On accept an In-App booking moves to
  /// `waitingForPayment` (the user must pay); a Direct-Visit booking is
  /// confirmed (`accepted` = "Visit Confirmed"). Payment is never taken before
  /// this point.
  Future<void> respond(ConsultationBooking b, bool accept) async {
    final newStatus = !accept
        ? ConsultationStatus.rejected
        : (b.isInApp
            ? ConsultationStatus.waitingForPayment
            : ConsultationStatus.accepted);
    await _doc(b.id).update({
      'status': newStatus.key,
      'respondedAt': FieldValue.serverTimestamp(),
    });
    if (!accept) {
      await _releaseSlot(b);
      await _notify(b.userId, 'Consultation declined',
          'Your ${b.mode.label.toLowerCase()} request was declined.',
          'consultation_rejected');
    } else {
      final msg = b.isInApp
          ? 'Your consultation was accepted. Complete the payment to confirm.'
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

  /// Best-effort +1 to an astrologer's confirmed-booking counter (drives the
  /// "Most Booked Astrologers" section). Never throws.
  Future<void> _bumpBookingCount(String astrologerId) async {
    if (astrologerId.trim().isEmpty) return;
    try {
      await _db
          .collection(AppConstants.astrologersCollection)
          .doc(astrologerId)
          .update({'bookingCount': FieldValue.increment(1)});
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
