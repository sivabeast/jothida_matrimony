import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/admin_config.dart';
import '../core/config/dev_config.dart';
import '../core/utils/working_hours.dart';
import '../models/astrologer_request_model.dart';
import '../models/astrology_service_config.dart';
import '../models/profile_model.dart';
import 'astrologer_session_provider.dart';
import 'auth_provider.dart';
import 'chat_provider.dart';
import 'interest_provider.dart';
import 'locale_provider.dart';
import 'notification_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';

/// Profiles the signed-in user may pick when booking a match analysis.
///
/// SPEC RULE: only profiles with an ACCEPTED interest may appear — never
/// pending, rejected, or random profiles. The user's OWN profile is also
/// included because a porutham is always *their* horoscope against a match's.
/// The booking screen then splits these into Groom (male) / Bride (female).
final matchAnalysisCandidatesProvider =
    FutureProvider.autoDispose<List<ProfileModel>>((ref) async {
  final me = ref.watch(myProfileProvider).valueOrNull;
  final myUid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  final sent =
      ref.watch(sentInterestsProvider).valueOrNull ?? const <dynamic>[];
  final received =
      ref.watch(receivedInterestsProvider).valueOrNull ?? const <dynamic>[];

  // The OTHER party's USER id for every ACCEPTED interest, in either direction.
  final otherUids = <String>{};
  for (final i in sent) {
    if (i.isAccepted) otherUids.add(i.receiverId);
  }
  for (final i in received) {
    if (i.isAccepted) otherUids.add(i.senderId);
  }
  otherUids.remove(myUid);

  // Resolve each match to its public profile (handles demo + real via the
  // existing by-user-id provider, which mirrors the public read rule).
  final matches = <ProfileModel>[];
  for (final uid in otherUids) {
    final p = await ref.watch(profileByUserIdProvider(uid).future);
    if (p != null) matches.add(p);
  }

  return [if (me != null) me, ...matches];
});

/// The signed-in user's match-analysis bookings (type == matching), newest
/// first. Powers the "My Match Analysis" page (Pending / Accepted / Completed).
final myMatchAnalysisRequestsProvider =
    StreamProvider.autoDispose<List<AstrologerRequestModel>>((ref) {
  if (kBypassAuth) {
    final all = ref.watch(demoAstrologerRequestsProvider);
    return Stream.value(
        all.where((r) => r.type == AstrologerRequestType.matching).toList());
  }
  final uid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.read(astrologerServiceProvider).watchRequestsByUser(uid).map(
      (list) => list
          .where((r) => r.type == AstrologerRequestType.matching)
          .toList());
});

/// DEPRECATED (legacy per-astrologer inbox). Retained only so the now-unwired
/// astrologer screens still analyse; the live app routes match analysis through
/// the single internal service ([internalAstrologyRequestsProvider]).
final astrologerMatchRequestsProvider =
    Provider.autoDispose<AsyncValue<List<AstrologerRequestModel>>>((ref) {
  return ref
      .watch(astrologerRequestsProvider)
      .whenData((list) => list.where((r) => r.isMatchAnalysis).toList());
});

/// Every Match Analysis request addressed to the official consultation
/// service ([kInternalAstrologyId]). Admin-only read (per rules) — powers the
/// legacy match-workspace screen. Newest-first, real-time.
final internalAstrologyRequestsProvider =
    StreamProvider.autoDispose<List<AstrologerRequestModel>>((ref) {
  if (kBypassAuth) {
    final all = ref.watch(demoAstrologerRequestsProvider);
    final list = all
        .where((r) => r.type == AstrologerRequestType.matching)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Stream.value(list);
  }
  return ref.read(astrologerServiceProvider).watchAllMatchRequests();
});

/// Live `dateKey → {morning: count, afternoon: count}` of booked appointment
/// SESSIONS for the internal astrology service — powers the appointment
/// date/session picker so a session that has reached its capacity greys out.
final internalSessionCountsProvider =
    StreamProvider.autoDispose<Map<String, Map<String, int>>>((ref) {
  if (kBypassAuth) {
    // Derive session counts from the in-memory demo requests so the picker
    // still enforces capacity in demo mode.
    final all = ref.watch(demoAstrologerRequestsProvider);
    final out = <String, Map<String, int>>{};
    for (final r in all) {
      if (!r.hasAppointment || r.session.isEmpty) continue;
      if (r.status == AstrologerRequestStatus.rejected) continue;
      final day = out.putIfAbsent(r.visitDateKey,
          () => {AppointmentSession.morning: 0, AppointmentSession.afternoon: 0});
      day[r.session] = (day[r.session] ?? 0) + 1;
    }
    return Stream.value(out);
  }
  return ref.read(astrologerServiceProvider).watchInternalSessionCounts();
});

/// A single match-analysis request by id, kept live from the internal service
/// stream — so the workspace reflects accept / reject / complete immediately,
/// without re-opening the screen.
final astrologerRequestByIdProvider =
    Provider.autoDispose.family<AstrologerRequestModel?, String>((ref, id) {
  final list =
      ref.watch(internalAstrologyRequestsProvider).valueOrNull ?? const [];
  for (final r in list) {
    if (r.id == id) return r;
  }
  return null;
});

/// Booking + analysis-submission actions for the match-analysis pipeline.
/// State is an [AsyncValue] so callers can show inline loading/error if needed;
/// the methods also rethrow so a screen's try/catch can surface a SnackBar.
class MatchAnalysisController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Runs the smart auto-assignment for [requestId] with ONE retry on a
  /// transient failure, then notifies the assigned employee's account
  /// (best-effort, when their uid is linked). Failures are logged LOUDLY —
  /// never swallowed silently — but never thrown: an already-paid booking
  /// must never fail because of an assignment hiccup (the admin's manual
  /// assignment and the Reports-tab self-heal both cover it).
  /// Returns true when the request ended up assigned.
  Future<bool> _tryAssign(String requestId, {bool resetStatus = true}) async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final chosen = await ref
            .read(astrologyTeamServiceProvider)
            .assignRequest(requestId, resetStatus: resetStatus);
        if (chosen == null) {
          debugPrint('[MatchAnalysis] assign($requestId): no active+available '
              'employee — left unassigned for the admin.');
          return false;
        }
        debugPrint(
            '[MatchAnalysis] assign($requestId) → ${chosen.email} (ok).');
        // In-app notification to the employee so the new report shows up on
        // their account immediately (best-effort).
        if (chosen.uid.isNotEmpty) {
          await ref.read(notificationNotifierProvider.notifier).notify(
                toUid: chosen.uid,
                event: AppNotificationEvent.reportAssigned,
                route: '/astrologer-dashboard',
              );
        }
        return true;
      } catch (e, st) {
        debugPrint('[MatchAnalysis] assign($requestId) attempt $attempt '
            'FAILED: $e\n$st');
        if (attempt == 1) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    }
    return false;
  }

  /// Self-healing hook (used by the Reports tab): re-runs the auto-assignment
  /// for a request that is still without an assignee. Safe to call repeatedly —
  /// [AstrologyTeamService.assignRequest] is idempotent (its transaction skips
  /// a request that already has an astrologerEmail).
  Future<void> retryAssignment(String requestId) => _tryAssign(requestId);

  /// Pays online FIRST, then creates the match-analysis booking (spec §3/§4:
  /// online payment is mandatory and the booking reaches the astrologer only
  /// after successful payment). The booking is created already `paid` and
  /// `pending` — the astrologer never sees an unpaid request.
  ///
  /// Payment is simulated in test mode (no real gateway); otherwise this is
  /// where the Razorpay checkout would run before the booking is written. The
  /// money is collected to the platform/admin account, never the astrologer —
  /// the admin settles astrologers weekly (spec §4).
  ///
  /// [reassignMode] decides what happens if the astrologer doesn't accept within
  /// the 12 WORKING-hour window. The booking is captured with the user's
  /// preferred language so the astrologer's report is written in it.
  Future<void> bookAndPay({
    required String astrologerId,
    required String astrologerName,
    required int amount,
    required ProfileModel groom,
    required ProfileModel bride,
    required String note,
    String astrologerPhoto = '',
    BookingReassignMode reassignMode = BookingReassignMode.waitOnly,
  }) async {
    state = const AsyncLoading();
    try {
      final me = ref.read(myProfileProvider).valueOrNull;
      final user = ref.read(currentUserProvider).valueOrNull;
      final uid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ??
          user?.uid ??
          '';
      final location = me == null
          ? ''
          : [me.city, me.state].where((s) => s.trim().isNotEmpty).join(', ');
      final lang = ref.read(localeProvider)?.languageCode ?? 'en';
      final now = DateTime.now();
      // Simulated payment (collected to the admin account). A real gateway
      // would run here and only on success would the booking be created.
      final paymentId = kPaymentTestMode
          ? 'demo_${now.millisecondsSinceEpoch}'
          : 'razorpay_${now.millisecondsSinceEpoch}';

      final request = AstrologerRequestModel(
        id: 'new',
        astrologerId: astrologerId,
        astrologerName: astrologerName,
        userId: uid,
        userName: me?.fullName ?? user?.displayName ?? 'User',
        userPhotoUrl: me?.profilePhotoUrl ?? '',
        userLocation: location,
        type: AstrologerRequestType.matching,
        status: AstrologerRequestStatus.pending,
        message: note.trim(),
        amount: amount,
        profileAId: groom.id,
        profileAName: groom.fullName,
        profileBId: bride.id,
        profileBName: bride.fullName,
        createdAt: now,
        reassignMode: reassignMode,
        // 12 WORKING hours (excludes 00:00–07:00) to accept (spec §6).
        expiresAt: matchAnalysisDeadline(now),
        userLanguage: lang,
        // Paid upfront — the booking is created already confirmed.
        paid: amount > 0,
        paidAt: amount > 0 ? now : null,
        paymentId: amount > 0 ? paymentId : '',
        history: [
          BookingHistoryEntry(at: now, label: 'Booking created'),
          if (amount > 0)
            BookingHistoryEntry(at: now, label: 'Payment received ($paymentId)'),
          BookingHistoryEntry(at: now, label: 'Sent to $astrologerName'),
        ],
      );

      if (kBypassAuth) {
        ref.read(demoAstrologerRequestsProvider.notifier).add(request);
      } else {
        await ref.read(astrologerServiceProvider).createRequest(request);
      }
      // Pre-create the chat thread NOW (user-initiated → always allowed by the
      // chat rules) so the astrologer can drop the automatic "booking accepted"
      // message straight into the existing thread on accept — without needing
      // thread-CREATE permission. The thread stays empty (and hidden from the
      // Chats list) until that first message arrives on accept. Best-effort:
      // never let a chat hiccup fail the booking.
      try {
        await ref.read(chatControllerProvider).openChatWith(
              otherUid: astrologerId,
              otherName: astrologerName,
              otherPhoto: astrologerPhoto,
            );
      } catch (_) {}
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Spec §4 — the user requests a **Horoscope Compatibility Report** for an
  /// accepted match. Pays online (real Razorpay, or simulated in test mode),
  /// creates a PAID matching request, then immediately AUTO-ASSIGNS it to the
  /// employee with the fewest pending reports (round-robin tie-break). The user
  /// NEVER selects an employee and no admin action is required.
  /// Returns the new request id.
  Future<String> requestAndAssignAnalysis({
    required ProfileModel groom,
    required ProfileModel bride,
    required int amount,
    String note = '',
    String? paymentId,
  }) async {
    state = const AsyncLoading();
    try {
      final me = ref.read(myProfileProvider).valueOrNull;
      final user = ref.read(currentUserProvider).valueOrNull;
      final uid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ??
          user?.uid ??
          '';
      final location = me == null
          ? ''
          : [me.city, me.state].where((s) => s.trim().isNotEmpty).join(', ');
      final lang = ref.read(localeProvider)?.languageCode ?? 'en';
      final now = DateTime.now();
      // Use the REAL Razorpay payment id when supplied; otherwise fall back to a
      // simulated id (demo / no-gateway path).
      final txnId = paymentId ??
          (kPaymentTestMode
              ? 'demo_${now.millisecondsSinceEpoch}'
              : 'razorpay_${now.millisecondsSinceEpoch}');

      final request = AstrologerRequestModel(
        id: 'new',
        // Unassigned — auto-assignment stamps the chosen astrologer.
        astrologerId: '',
        astrologerName: '',
        userId: uid,
        userName: me?.fullName ?? user?.displayName ?? 'User',
        userPhotoUrl: me?.profilePhotoUrl ?? '',
        userLocation: location,
        type: AstrologerRequestType.matching,
        status: AstrologerRequestStatus.pending,
        message: note.trim(),
        amount: amount,
        profileAId: groom.id,
        profileAName: groom.fullName,
        profileBId: bride.id,
        profileBName: bride.fullName,
        createdAt: now,
        userLanguage: lang,
        paid: amount > 0,
        paidAt: amount > 0 ? now : null,
        paymentId: amount > 0 ? txnId : '',
        history: [
          BookingHistoryEntry(at: now, label: 'Booking created'),
          if (amount > 0)
            BookingHistoryEntry(at: now, label: 'Payment received ($txnId)'),
        ],
      );

      String id;
      if (kBypassAuth) {
        id = 'demo_${now.millisecondsSinceEpoch}';
        ref.read(demoAstrologerRequestsProvider.notifier).add(request);
      } else {
        // Create the paid request, then immediately auto-assign it to the
        // employee with the fewest pending reports — no admin action needed.
        // _tryAssign logs failures, retries once and notifies the employee;
        // an unassigned request stays visible to the admin and self-heals
        // from the user's Reports tab.
        id = await ref.read(astrologerServiceProvider).createRequest(request);
        await _tryAssign(id);
      }
      state = const AsyncData(null);
      return id;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Books an in-person **Horoscope Compatibility Report** appointment after a
  /// successful (real Razorpay) payment. Creates ONE paid match-analysis request
  /// addressed to the internal astrology service — carrying the chosen
  /// [date]/[slotMinutes] and an office-details snapshot — using the
  /// slot-locking deterministic-id create (throws [AppointmentSlotTakenException]
  /// if the slot was just taken). It then **pre-creates the Astrology Analysis
  /// Chat** thread to the internal account so the user can open it immediately
  /// (spec §12). Returns the new request id (the user-facing Booking ID).
  Future<String> bookAppointment({
    required ProfileModel groom,
    required ProfileModel bride,
    required DateTime date,
    required int slotMinutes,
    required int amount,
    required String paymentId,
    required AstrologyServiceConfig config,
    String note = '',
  }) async {
    state = const AsyncLoading();
    try {
      final me = ref.read(myProfileProvider).valueOrNull;
      final user = ref.read(currentUserProvider).valueOrNull;
      final uid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ??
          user?.uid ??
          '';
      final location = me == null
          ? ''
          : [me.city, me.state].where((s) => s.trim().isNotEmpty).join(', ');
      final lang = ref.read(localeProvider)?.languageCode ?? 'en';
      final now = DateTime.now();
      final visitDay = DateTime(date.year, date.month, date.day);

      final request = AstrologerRequestModel(
        id: 'new',
        astrologerId: kInternalAstrologyId,
        astrologerName: kInternalAstrologyName,
        userId: uid,
        userName: me?.fullName ?? user?.displayName ?? 'User',
        userPhotoUrl: me?.profilePhotoUrl ?? '',
        userLocation: location,
        type: AstrologerRequestType.matching,
        status: AstrologerRequestStatus.pending,
        message: note.trim(),
        amount: amount,
        profileAId: groom.id,
        profileAName: groom.fullName,
        profileBId: bride.id,
        profileBName: bride.fullName,
        createdAt: now,
        userLanguage: lang,
        // Paid upfront via Razorpay — the report is never payment-locked.
        paid: true,
        paidAt: now,
        paymentId: paymentId,
        visitDate: visitDay,
        session: slotMinutes < AppointmentSession.afternoonStart
            ? AppointmentSession.morning
            : AppointmentSession.afternoon,
        slotStartMinutes: slotMinutes,
        officeAddress: config.officeAddress,
        officeContact: config.officeContactNumber,
        history: [
          BookingHistoryEntry(at: now, label: 'Appointment booked'),
          BookingHistoryEntry(
              at: now, label: 'Payment received ($paymentId)'),
        ],
      );

      final session = slotMinutes < AppointmentSession.afternoonStart
          ? AppointmentSession.morning
          : AppointmentSession.afternoon;
      final String id;
      if (kBypassAuth) {
        id = 'appt_${now.millisecondsSinceEpoch}';
        ref.read(demoAstrologerRequestsProvider.notifier).add(request);
      } else {
        id = await ref.read(astrologerServiceProvider).createAppointmentRequest(
            request,
            capacity: config.capacityForSession(session));
      }

      // Pre-create the Astrology Analysis Chat to the internal account's real
      // uid so the user can open it immediately and the team shares one thread
      // (idempotent → no duplicate). Best-effort: a chat hiccup never fails the
      // booking. If internalUid isn't known yet, the thread is created when the
      // team accepts (existing astrologerUid path).
      if (config.internalUid.isNotEmpty) {
        try {
          await ref.read(chatControllerProvider).openChatWith(
                otherUid: config.internalUid,
                otherName: config.expertName.trim().isEmpty
                    ? kInternalAstrologyName
                    : config.expertName.trim(),
                otherPhoto: config.expertPhotoUrl,
              );
        } catch (_) {}
      }

      // In-app "Appointment Confirmed" notification (best-effort).
      final myUid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
      if (myUid != null) {
        await ref.read(notificationNotifierProvider.notifier).notify(
              toUid: myUid,
              event: AppNotificationEvent.appointmentConfirmed,
              route: '/my-appointments',
            );
      }

      state = const AsyncData(null);
      return id;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Books a standalone **in-person Astrology appointment** from the Astrology
  /// page's "Book Your Appointment" flow. Writes ONE appointment request to the
  /// internal astrology service for the chosen [session] (Morning / Afternoon).
  /// The session's admin-configured capacity is enforced atomically at the
  /// backend — a session that is already full throws
  /// [AppointmentSlotTakenException]. Returns the new booking id.
  Future<String> bookServiceAppointment({
    required DateTime date,
    required String session,
    required AstrologyServiceConfig config,
    String category = '',
    String note = '',
    int amount = 0,
    String? paymentId,
  }) async {
    state = const AsyncLoading();
    try {
      final me = ref.read(myProfileProvider).valueOrNull;
      final user = ref.read(currentUserProvider).valueOrNull;
      final uid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ??
          user?.uid ??
          '';
      final location = me == null
          ? ''
          : [me.city, me.state].where((s) => s.trim().isNotEmpty).join(', ');
      final lang = ref.read(localeProvider)?.languageCode ?? 'en';
      final now = DateTime.now();
      final visitDay = DateTime(date.year, date.month, date.day);
      final userName = me?.fullName ?? user?.displayName ?? 'User';
      final userPhone = (me?.contact.mobileNumber.trim().isNotEmpty ?? false)
          ? me!.contact.mobileNumber.trim()
          : (user?.phone ?? '');

      final request = AstrologerRequestModel(
        id: 'new',
        astrologerId: kInternalAstrologyId,
        astrologerName: kInternalAstrologyName,
        userId: uid,
        userName: userName,
        userPhotoUrl: me?.profilePhotoUrl ?? '',
        userLocation: location,
        userPhone: userPhone,
        // Standalone office-visit appointment — independent of the online
        // Horoscope Analysis report.
        type: AstrologerRequestType.consultation,
        // Payment already succeeded when this runs → the booking is CONFIRMED
        // immediately. The admin never manually confirms; their only actions
        // are Complete / Cancel.
        status: AstrologerRequestStatus.accepted,
        message: note.trim(),
        category: category.trim(),
        // ₹50 booking charge collected up front to confirm the slot.
        amount: amount,
        paid: amount > 0,
        paidAt: amount > 0 ? now : null,
        paymentId: amount > 0 ? (paymentId ?? '') : '',
        // The booking is the user's own visit — store them as profile A so the
        // workspace/admin can identify who is coming in.
        profileAId: me?.id,
        profileAName: userName,
        createdAt: now,
        userLanguage: lang,
        visitDate: visitDay,
        session: session,
        slotStartMinutes: AppointmentSession.startMinutes(session),
        officeAddress: config.officeAddress,
        officeContact: config.officeContactNumber,
        history: [
          BookingHistoryEntry(at: now, label: 'Appointment booked'),
          if (amount > 0)
            BookingHistoryEntry(
                at: now, label: 'Payment received (${paymentId ?? ''})'),
          BookingHistoryEntry(
              at: now, label: 'Appointment confirmed (paid booking)'),
        ],
      );

      final String id;
      if (kBypassAuth) {
        id = 'appt_${now.millisecondsSinceEpoch}';
        ref.read(demoAstrologerRequestsProvider.notifier).add(request);
      } else {
        id = await ref.read(astrologerServiceProvider).createAppointmentRequest(
            request,
            capacity: config.capacityForSession(session));
        // Auto-assign the confirmed appointment to the employee with the
        // fewest open requests — that employee contacts the user personally
        // with the exact timing (no fixed time slots). Best-effort (logged +
        // retried): an unassigned booking stays visible to the admin either way.
        await _tryAssign(id, resetStatus: false);
      }
      // In-app "Appointment Confirmed" notification (best-effort).
      if (uid.isNotEmpty) {
        await ref.read(notificationNotifierProvider.notifier).notify(
              toUid: uid,
              event: AppNotificationEvent.appointmentConfirmed,
              route: '/my-appointments',
            );
      }
      state = const AsyncData(null);
      return id;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Best-effort: flag this user's OWN booking Expired once the 24-hour window
  /// lapses (security rules permit the owner this limited update; there is no
  /// Cloud Functions backend to do it server-side). Safe to call repeatedly.
  Future<void> expireIfDue(AstrologerRequestModel r) async {
    if (kBypassAuth) {
      if (r.isExpiredByTime && !r.expired) {
        ref.read(demoAstrologerRequestsProvider.notifier).markExpired(r.id);
      }
      return;
    }
    await ref.read(astrologerServiceProvider).expireRequestIfDue(r);
  }

  /// Pays the analysis fee for an accepted booking. Development mode only — the
  /// payment is simulated (no real gateway) and a demo transaction id is
  /// generated, exactly like the consultation flow. On success the booking is
  /// flagged paid (→ "Booking Confirmed") and the user is notified.
  Future<void> pay(AstrologerRequestModel r) async {
    state = const AsyncLoading();
    try {
      final paymentId = kPaymentTestMode
          ? 'demo_${DateTime.now().millisecondsSinceEpoch}'
          : 'razorpay_${DateTime.now().millisecondsSinceEpoch}';
      if (kBypassAuth) {
        ref
            .read(demoAstrologerRequestsProvider.notifier)
            .markPaid(r.id, paymentId: paymentId);
      } else {
        await ref.read(astrologerServiceProvider).markAnalysisPaid(r.id,
            paymentId: paymentId,
            userId: r.userId,
            astrologerId: r.astrologerId);
      }
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Option 2 ("let me choose another astrologer later"): the user re-points an
  /// expired booking to a new astrologer themselves. MOVES the booking to the
  /// new astrologer with a fresh window — never duplicates it.
  Future<void> chooseAnotherAstrologer(
    AstrologerRequestModel r, {
    required String astrologerId,
    required String astrologerName,
  }) async {
    state = const AsyncLoading();
    try {
      if (kBypassAuth) {
        ref.read(demoAstrologerRequestsProvider.notifier).reassign(r.id,
            astrologerId: astrologerId,
            astrologerName: astrologerName,
            byAdmin: false);
      } else {
        await ref.read(astrologerServiceProvider).reassignRequest(r.id,
            astrologerId: astrologerId,
            astrologerName: astrologerName,
            byAdmin: false,
            userId: r.userId);
      }
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Accept / reject a pending match-analysis request (the spec's
  /// Pending → Accepted transition). Centralised here so BOTH the dashboard's
  /// inline Accept button and the workspace use the exact same path: write the
  /// new status to the database, then (on accept) drop the automatic
  /// booking-accepted message into the user's chat thread. Rethrows so the
  /// caller can surface a SnackBar; the chat message is best-effort and never
  /// blocks the accept.
  Future<void> setStatus(
    AstrologerRequestModel request,
    AstrologerRequestStatus status,
  ) async {
    state = const AsyncLoading();
    try {
      if (kBypassAuth) {
        ref
            .read(demoAstrologerRequestsProvider.notifier)
            .setStatus(request.id, status);
      } else {
        // Stamp the responder's REAL uid (the internal astrology account) on
        // accept so the user can open the same chat thread it creates.
        final responderUid =
            ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ?? '';
        await ref.read(astrologerServiceProvider).updateRequestStatus(
              request.id,
              status,
              astrologerName: request.astrologerName,
              userId: request.userId,
              amount: request.amount,
              responderUid: responderUid,
            );
      }
      // On ACCEPT the booking is "In Progress" and chat opens for both sides —
      // auto-send the booking-accepted system message to the user.
      if (status == AstrologerRequestStatus.accepted) {
        await ref.read(chatControllerProvider).sendBookingAcceptedMessage(
              userUid: request.userId,
              userName: request.userName,
              userPhoto: request.userPhotoUrl,
              groomName: request.groomName,
              brideName: request.brideName,
            );
      }
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Astrologer begins working on an accepted booking (spec §11:
  /// Accepted → Analysis In Progress). Sets the `inProgress` flag so the booking
  /// moves to the "In Progress" bucket on the Requests page and the user is
  /// notified. Rethrows so callers can surface a SnackBar.
  Future<void> startAnalysis(AstrologerRequestModel request) async {
    state = const AsyncLoading();
    try {
      if (kBypassAuth) {
        ref
            .read(demoAstrologerRequestsProvider.notifier)
            .markInProgress(request.id);
      } else {
        await ref
            .read(astrologerServiceProvider)
            .startAnalysis(request.id, userId: request.userId);
      }
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Uploads newly-picked files and SAVES a draft (spec §11) without completing
  /// the request — it stays `pending` and never appears on the user's Reports
  /// page. Returns the uploaded URLs so the editor can swap its picked files for
  /// their persisted URLs.
  Future<({List<String> images, List<String> pdfs})> saveDraft({
    required String requestId,
    required String text,
    List<File> newImages = const [],
    List<File> newPdfs = const [],
    List<String> existingImages = const [],
    List<String> existingPdfs = const [],
  }) async {
    state = const AsyncLoading();
    try {
      final svc = ref.read(astrologerServiceProvider);
      final images = [...existingImages];
      final pdfs = [...existingPdfs];
      if (!kBypassAuth) {
        for (final f in newImages) {
          images.add(await svc.uploadAnalysisFile(
              requestId: requestId, file: f, fileType: 'image'));
        }
        for (final f in newPdfs) {
          pdfs.add(await svc.uploadAnalysisFile(
              requestId: requestId, file: f, fileType: 'pdf'));
        }
        await svc.saveDraft(
            requestId: requestId, text: text.trim(), images: images, pdfs: pdfs);
      }
      state = const AsyncData(null);
      return (images: images, pdfs: pdfs);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Saves the structured Marriage Compatibility Report as a draft — the
  /// request stays `pending` and the employee can continue editing later.
  Future<void> saveCompatReportDraft({
    required String requestId,
    required Map<String, dynamic> data,
  }) async {
    state = const AsyncLoading();
    try {
      if (!kBypassAuth) {
        await ref
            .read(astrologerServiceProvider)
            .saveCompatReport(requestId: requestId, data: data);
      }
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Submits the finished structured Marriage Compatibility Report: stores it,
  /// marks the request completed, notifies the owner and releases the
  /// employee's workload counter (mirrors [submitAnalysis]).
  Future<void> submitCompatReport({
    required String requestId,
    required Map<String, dynamic> data,
    String explanation = '',
  }) async {
    state = const AsyncLoading();
    try {
      if (kBypassAuth) {
        ref.read(demoAstrologerRequestsProvider.notifier).submitAnalysis(
              requestId,
              text: explanation.trim(),
              images: const [],
              pdfs: const [],
            );
        state = const AsyncData(null);
        return;
      }

      final svc = ref.read(astrologerServiceProvider);
      await svc.submitCompatReport(requestId: requestId, data: data);
      // In-app "Horoscope Report Ready" notification for the request owner
      // (best-effort — the submission must never fail because of it).
      try {
        final req = await svc.getRequestById(requestId);
        if (req != null && req.userId.isNotEmpty) {
          await ref.read(notificationNotifierProvider.notifier).notify(
                toUid: req.userId,
                event: AppNotificationEvent.reportReady,
                route: '/reports',
              );
        }
      } catch (e) {
        debugPrint('[MatchAnalysis] report-ready notification failed: $e');
      }
      // Free up the astrologer's workload counter so auto-assignment rebalances.
      final myEmail = ref.read(currentUserProvider).valueOrNull?.email ?? '';
      if (myEmail.isNotEmpty) {
        await ref
            .read(astrologyTeamServiceProvider)
            .markReportSubmitted(myEmail);
      }
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Uploads any newly-picked files, then stores the report and marks the
  /// request completed. [existingImages]/[existingPdfs] are kept (already
  /// uploaded URLs) so re-submitting an edit doesn't re-upload everything.
  Future<void> submitAnalysis({
    required String requestId,
    required String text,
    List<File> newImages = const [],
    List<File> newPdfs = const [],
    List<String> existingImages = const [],
    List<String> existingPdfs = const [],
  }) async {
    state = const AsyncLoading();
    try {
      if (kBypassAuth) {
        ref.read(demoAstrologerRequestsProvider.notifier).submitAnalysis(
              requestId,
              text: text.trim(),
              images: existingImages,
              pdfs: existingPdfs,
            );
        state = const AsyncData(null);
        return;
      }

      final svc = ref.read(astrologerServiceProvider);
      final images = [...existingImages];
      for (final f in newImages) {
        images.add(await svc.uploadAnalysisFile(
            requestId: requestId, file: f, fileType: 'image'));
      }
      final pdfs = [...existingPdfs];
      for (final f in newPdfs) {
        pdfs.add(await svc.uploadAnalysisFile(
            requestId: requestId, file: f, fileType: 'pdf'));
      }
      await svc.submitAnalysis(
        requestId: requestId,
        text: text.trim(),
        images: images,
        pdfs: pdfs,
      );
      // In-app "Horoscope Report Ready" notification for the request owner
      // (best-effort — the submission must never fail because of it).
      try {
        final req = await svc.getRequestById(requestId);
        if (req != null && req.userId.isNotEmpty) {
          await ref.read(notificationNotifierProvider.notifier).notify(
                toUid: req.userId,
                event: AppNotificationEvent.reportReady,
                route: '/reports',
              );
        }
      } catch (e) {
        debugPrint('[MatchAnalysis] report-ready notification failed: $e');
      }
      // Free up the astrologer's workload counter so auto-assignment rebalances.
      final myEmail = ref.read(currentUserProvider).valueOrNull?.email ?? '';
      if (myEmail.isNotEmpty) {
        await ref
            .read(astrologyTeamServiceProvider)
            .markReportSubmitted(myEmail);
      }
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final matchAnalysisControllerProvider =
    NotifierProvider<MatchAnalysisController, AsyncValue<void>>(
        MatchAnalysisController.new);
