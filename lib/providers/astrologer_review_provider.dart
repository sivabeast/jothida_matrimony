import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/dev_config.dart';
import '../models/astrologer_review_model.dart';
import 'astrologer_provider.dart';
import 'auth_provider.dart';
import 'demo_data_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';
import 'subscription_provider.dart';

/// Whether the signed-in account is allowed to rate astrologers.
///
/// ALL of these must hold (per spec):
///  1. Account type is a normal **user** (never an astrologer / admin).
///  2. The user's matrimony **profile is completed**.
///  3. The user has an **active (non-expired) premium subscription**.
///
/// Contact-viewed / call-made / verified-user are intentionally NOT required.
/// In demo mode the gate is open so the feature is testable offline.
final canRateAstrologerProvider = Provider.autoDispose<bool>((ref) {
  if (kBypassAuth) return true;

  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return false;
  if (user.role != 'user') return false; // astrologers / admins cannot rate
  if (!user.isProfileComplete) return false;

  // Active premium — accept either a live subscription document or the mirrored
  // membership fields on the user doc, as long as it hasn't expired.
  final sub = ref.watch(activeSubscriptionProvider).valueOrNull;
  final subActive = sub != null && sub.isActive && !sub.isExpired;
  final now = DateTime.now();
  final membershipActive = user.membershipType != 'free' &&
      user.subscriptionExpiry != null &&
      user.subscriptionExpiry!.isAfter(now);
  return subActive || membershipActive;
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
