import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/data/sample_astrologer_dashboard.dart';
import '../models/astrologer_account_model.dart';
import '../models/astrologer_booking_model.dart';
import '../models/astrologer_model.dart';

/// Demo session for the logged-in astrologer.
///
/// `null` until onboarding is completed — the router uses this to force
/// onboarding before the dashboard (mirrors the matrimony profile gate).
///
/// TODO(auth): back with real role-based Firebase auth + Firestore
/// `astrologers/{uid}`.
class MyAstrologerAccountNotifier extends Notifier<AstrologerAccount?> {
  @override
  AstrologerAccount? build() => null;

  void completeOnboarding(AstrologerAccount account) => state = account;

  void updateServices(List<AstrologerService> services) =>
      state = state?.copyWith(services: services);

  void signOut() => state = null;
}

final myAstrologerAccountProvider =
    NotifierProvider<MyAstrologerAccountNotifier, AstrologerAccount?>(
        MyAstrologerAccountNotifier.new);

final isAstrologerOnboardedProvider =
    Provider<bool>((ref) => ref.watch(myAstrologerAccountProvider) != null);

// ── Dashboard sample data ──────────────────────────────────────────────────
final astrologerBookingsProvider =
    Provider<List<AstrologerBooking>>((ref) => sampleBookings());

final astrologerReviewsProvider =
    Provider<List<AstrologerReview>>((ref) => sampleDashboardReviews());

final astrologerAvailabilityProvider =
    Provider<Map<String, List<AvailabilitySlot>>>(
        (ref) => sampleWeeklyAvailability());

/// Derived overview stats for the dashboard.
final astrologerStatsProvider = Provider<Map<String, dynamic>>((ref) {
  final bookings = ref.watch(astrologerBookingsProvider);
  final reviews = ref.watch(astrologerReviewsProvider);
  final completed =
      bookings.where((b) => b.status == BookingStatus.completed).toList();
  final upcoming =
      bookings.where((b) => b.status == BookingStatus.upcoming).length;
  final earnings = completed.fold<int>(0, (sum, b) => sum + b.amount);
  final avgRating = reviews.isEmpty
      ? 0.0
      : reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;
  return {
    'totalBookings': bookings.length,
    'upcoming': upcoming,
    'monthlyEarnings': earnings,
    'avgRating': double.parse(avgRating.toStringAsFixed(1)),
    'reviewCount': reviews.length,
  };
});
