import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/dev_config.dart';
import '../models/astrologer_request_model.dart';
import '../models/profile_model.dart';
import 'astrologer_session_provider.dart';
import 'auth_provider.dart';
import 'interest_provider.dart';
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

/// Booking + analysis-submission actions for the match-analysis pipeline.
/// State is an [AsyncValue] so callers can show inline loading/error if needed;
/// the methods also rethrow so a screen's try/catch can surface a SnackBar.
class MatchAnalysisController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Creates a pending "Book Match Analysis" request for [groom] × [bride].
  Future<void> book({
    required String astrologerId,
    required String astrologerName,
    required int amount,
    required ProfileModel groom,
    required ProfileModel bride,
    required String note,
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
        createdAt: DateTime.now(),
      );

      if (kBypassAuth) {
        ref.read(demoAstrologerRequestsProvider.notifier).add(request);
      } else {
        await ref.read(astrologerServiceProvider).createRequest(request);
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
