import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/dev_config.dart';
import '../core/utils/profile_completion.dart';
import '../models/astrologer_review_model.dart';
import 'astrologer_provider.dart';
import 'auth_provider.dart';
import 'demo_data_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';

/// Whether the signed-in account is allowed to rate astrologers.
///
/// Any registered USER with a completed profile may rate — NO subscription is
/// required. Conditions:
///  1. Account type is a normal **user** (never an astrologer / admin — they
///     can't rate, per the business rules / security rules).
///  2. The user is logged in and their matrimony **profile is completed**.
///
/// Completeness is decided from the ACTUAL Firestore profile data first
/// ([isProfileCompleteEnough]) and only falls back to the
/// `users/{uid}.isProfileComplete` flag. The flag is frequently stale (e.g. a
/// profile finished through the registration steps before the flag was written,
/// or contact details that live in the gated `contacts/{uid}` collection drag a
/// naive percentage below threshold), which previously left finished profiles
/// wrongly showing "Complete your profile to rate astrologers." Trusting the
/// real profile fields fixes that.
final canRateAstrologerProvider = Provider.autoDispose<bool>((ref) {
  if (kBypassAuth) return true;

  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return false;
  if (user.role != 'user') return false; // astrologers / admins cannot rate

  // Primary source of truth: the actual matrimony profile document.
  final profile = ref.watch(myProfileProvider).valueOrNull;
  if (isProfileCompleteEnough(profile)) return true;

  // Fallback: honour the persisted completion flag (covers the brief window
  // before the profile stream resolves, and any edge profile shapes).
  return user.isProfileComplete;
});

/// Live reviews for an astrologer (newest first).
final astrologerReviewsProvider = StreamProvider.autoDispose
    .family<List<AstrologerReviewModel>, String>((ref, astrologerId) {
  if (kBypassAuth) {
    final list = ref
        .watch(demoAstrologerReviewsProvider)
        .where((r) => r.astrologerId == astrologerId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Stream.value(list);
  }
  return ref.watch(astrologerServiceProvider).watchReviews(astrologerId);
});

/// The signed-in user's own review of an astrologer, or null. Drives the
/// "Rate" vs "Edit Your Rating" button and pre-fills the form.
final myAstrologerReviewProvider = FutureProvider.autoDispose
    .family<AstrologerReviewModel?, String>((ref, astrologerId) async {
  if (kBypassAuth) {
    for (final r in ref.watch(demoAstrologerReviewsProvider)) {
      if (r.astrologerId == astrologerId && r.userId == kDemoUserId) return r;
    }
    return null;
  }
  final uid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (uid == null) return null;
  return ref.watch(astrologerServiceProvider).getMyReview(astrologerId, uid);
});

/// Controller that submits / edits a review.
class AstrologerReviewController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> submit({
    required String astrologerId,
    required int rating,
    String review = '',
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final name = ref.read(myProfileProvider).valueOrNull?.name ??
          ref.read(currentUserProvider).valueOrNull?.displayName ??
          'User';

      if (kBypassAuth) {
        ref.read(demoAstrologerReviewsProvider.notifier).upsert(
              AstrologerReviewModel(
                id: AstrologerReviewModel.docId(astrologerId, kDemoUserId),
                astrologerId: astrologerId,
                userId: kDemoUserId,
                userName: name,
                rating: rating,
                review: review.trim(),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
      } else {
        final uid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
        if (uid == null) throw StateError('You must be signed in to rate.');
        await ref.read(astrologerServiceProvider).submitReview(
              astrologerId: astrologerId,
              userId: uid,
              userName: name,
              rating: rating,
              review: review.trim(),
            );
      }
      // Refresh the user's own review and the aggregate shown in listings.
      ref.invalidate(myAstrologerReviewProvider(astrologerId));
      ref.invalidate(astrologerReviewsProvider(astrologerId));
      ref.invalidate(astrologersProvider);
    });

    // CRITICAL: AsyncValue.guard swallows the exception into `state`. Without
    // re-throwing, the caller's `await submit()` always completes "normally"
    // and the UI shows a success toast even when the Firestore write was
    // denied — exactly the "Rating submitted successfully but nothing saved"
    // bug. Re-throw so the rating sheet shows the real outcome.
    final result = state;
    if (result is AsyncError) {
      Error.throwWithStackTrace(result.error, result.stackTrace);
    }
  }
}

final astrologerReviewControllerProvider =
    NotifierProvider<AstrologerReviewController, AsyncValue<void>>(
        AstrologerReviewController.new);

// ── Demo in-memory review store (kBypassAuth) ────────────────────────────────

class DemoAstrologerReviewsNotifier
    extends Notifier<List<AstrologerReviewModel>> {
  @override
  List<AstrologerReviewModel> build() => const [];

  void upsert(AstrologerReviewModel r) =>
      state = [r, ...state.where((x) => x.id != r.id)];
}

final demoAstrologerReviewsProvider =
    NotifierProvider<DemoAstrologerReviewsNotifier, List<AstrologerReviewModel>>(
        DemoAstrologerReviewsNotifier.new);
