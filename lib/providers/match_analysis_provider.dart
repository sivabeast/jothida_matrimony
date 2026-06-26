import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/dev_config.dart';
import '../core/utils/working_hours.dart';
import '../models/astrologer_request_model.dart';
import '../models/profile_model.dart';
import 'astrologer_session_provider.dart';
import 'auth_provider.dart';
import 'chat_provider.dart';
import 'interest_provider.dart';
import 'locale_provider.dart';
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

/// All match-analysis requests addressed to the signed-in astrologer
/// (type == matching), powering the dashboard's dedicated module.
final astrologerMatchRequestsProvider =
    Provider.autoDispose<AsyncValue<List<AstrologerRequestModel>>>((ref) {
  return ref
      .watch(astrologerRequestsProvider)
      .whenData((list) => list.where((r) => r.isMatchAnalysis).toList());
});

/// A single astrologer request by id, kept live from the astrologer's request
/// stream — so the workspace reflects accept / reject / complete immediately,
/// without re-opening the screen.
final astrologerRequestByIdProvider =
    Provider.autoDispose.family<AstrologerRequestModel?, String>((ref, id) {
  final list = ref.watch(astrologerRequestsProvider).valueOrNull ?? const [];
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
      final paymentId = kSubscriptionTestMode
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
      final paymentId = kSubscriptionTestMode
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
        await ref.read(astrologerServiceProvider).updateRequestStatus(
              request.id,
              status,
              astrologerName: request.astrologerName,
              userId: request.userId,
              amount: request.amount,
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
