import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/dev_config.dart';
import '../core/data/sample_astrologer_dashboard.dart';
import '../models/astrologer_account_model.dart';
import '../models/astrologer_booking_model.dart';
import '../models/astrologer_model.dart';
import '../models/astrologer_request_model.dart';
import 'service_providers.dart';

/// Session for the logged-in astrologer.
///
/// `null` until signup/login completes — the router uses this to gate the
/// dashboard. In real mode ([kBypassAuth] == false) the account is hydrated
/// from Firestore `astrologers/{uid}` after Firebase login; in demo mode the
/// signup form fills it locally.
class MyAstrologerAccountNotifier extends Notifier<AstrologerAccount?> {
  @override
  AstrologerAccount? build() => null;

  void completeOnboarding(AstrologerAccount account) => state = account;

  /// Real mode: load (or refresh) the account from Firestore after login.
  /// Returns `true` when an astrologer account exists for [uid].
  Future<bool> loadFromFirestore(String uid) async {
    final account =
        await ref.read(astrologerServiceProvider).getAccount(uid);
    state = account;
    return account != null;
  }

  void updateServices(List<AstrologerService> services) =>
      state = state?.copyWith(services: services);

  void signOut() => state = null;
}

final myAstrologerAccountProvider =
    NotifierProvider<MyAstrologerAccountNotifier, AstrologerAccount?>(
        MyAstrologerAccountNotifier.new);

final isAstrologerOnboardedProvider =
    Provider<bool>((ref) => ref.watch(myAstrologerAccountProvider) != null);

// ── Dashboard data ──────────────────────────────────────────────────────────
// Demo mode serves in-memory sample data; real mode streams Firestore.

final astrologerBookingsProvider =
    Provider<List<AstrologerBooking>>((ref) => sampleBookings());

final astrologerReviewsProvider =
    Provider<List<AstrologerReview>>((ref) => sampleDashboardReviews());

final astrologerAvailabilityProvider =
    Provider<Map<String, List<AvailabilitySlot>>>(
        (ref) => sampleWeeklyAvailability());

/// Demo seed for consultation/inquiry/matching requests so the dashboard is
/// reviewable without a backend. Mutable so accept/reject works in demo too.
class DemoAstrologerRequestsNotifier
    extends Notifier<List<AstrologerRequestModel>> {
  @override
  List<AstrologerRequestModel> build() {
    final now = DateTime.now();
    return [
      AstrologerRequestModel(
        id: 'req-1',
        astrologerId: 'demo-astrologer',
        userId: 'u1',
        userName: 'Karthik Raja',
        userPhotoUrl: 'https://i.pravatar.cc/150?img=12',
        type: AstrologerRequestType.consultation,
        message: 'Need guidance on marriage timing as per my horoscope.',
        amount: 499,
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      AstrologerRequestModel(
        id: 'req-2',
        astrologerId: 'demo-astrologer',
        userId: 'u2',
        userName: 'Priya Lakshmi',
        userPhotoUrl: 'https://i.pravatar.cc/150?img=47',
        type: AstrologerRequestType.matching,
        message: 'Please check porutham between my profile and Suresh Kumar.',
        amount: 199,
        profileAId: 'p1',
        profileBId: 'p2',
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
      AstrologerRequestModel(
        id: 'req-3',
        astrologerId: 'demo-astrologer',
        userId: 'u3',
        userName: 'Anand Subramanian',
        userPhotoUrl: 'https://i.pravatar.cc/150?img=33',
        type: AstrologerRequestType.inquiry,
        message: 'Do you provide Nadi astrology readings online?',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      AstrologerRequestModel(
        id: 'req-4',
        astrologerId: 'demo-astrologer',
        userId: 'u4',
        userName: 'Divya Bharathi',
        userPhotoUrl: 'https://i.pravatar.cc/150?img=25',
        type: AstrologerRequestType.matching,
        status: AstrologerRequestStatus.completed,
        message: 'Horoscope match for two shortlisted profiles.',
        amount: 199,
        createdAt: now.subtract(const Duration(days: 3)),
        respondedAt: now.subtract(const Duration(days: 2)),
      ),
    ];
  }

  void setStatus(String id, AstrologerRequestStatus status) {
    state = [
      for (final r in state) r.id == id ? r.copyWith(status: status) : r,
    ];
  }
}

final demoAstrologerRequestsProvider = NotifierProvider<
    DemoAstrologerRequestsNotifier,
    List<AstrologerRequestModel>>(DemoAstrologerRequestsNotifier.new);

/// Realtime requests for the logged-in astrologer (consultations, inquiries,
/// horoscope matching). Demo mode → in-memory list above.
final astrologerRequestsProvider =
    StreamProvider.autoDispose<List<AstrologerRequestModel>>((ref) {
  if (kBypassAuth) {
    return Stream.value(ref.watch(demoAstrologerRequestsProvider));
  }
  final account = ref.watch(myAstrologerAccountProvider);
  if (account == null) return Stream.value(const []);
  return ref
      .read(astrologerServiceProvider)
      .watchRequestsForAstrologer(account.id);
});

/// Derived overview stats for the dashboard.
final astrologerStatsProvider = Provider<Map<String, dynamic>>((ref) {
  final bookings = ref.watch(astrologerBookingsProvider);
  final reviews = ref.watch(astrologerReviewsProvider);
  final requests =
      ref.watch(astrologerRequestsProvider).valueOrNull ?? const [];
  final completed =
      bookings.where((b) => b.status == BookingStatus.completed).toList();
  final upcoming =
      bookings.where((b) => b.status == BookingStatus.upcoming).length;
  final bookingEarnings = completed.fold<int>(0, (sum, b) => sum + b.amount);
  final requestEarnings = requests
      .where((r) => r.status == AstrologerRequestStatus.completed)
      .fold<int>(0, (sum, r) => sum + r.amount);
  final pendingRequests = requests
      .where((r) => r.status == AstrologerRequestStatus.pending)
      .length;
  final avgRating = reviews.isEmpty
      ? 0.0
      : reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;
  return {
    'totalBookings': bookings.length,
    'upcoming': upcoming,
    'pendingRequests': pendingRequests,
    'monthlyEarnings': bookingEarnings + requestEarnings,
    'avgRating': double.parse(avgRating.toStringAsFixed(1)),
    'reviewCount': reviews.length,
  };
});
