import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/dev_config.dart';
import '../models/astrologer_account_model.dart';
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
    final account = await ref.read(astrologerServiceProvider).getAccount(uid);
    state = account;
    return account != null;
  }

  /// Persists edited profile fields to Firestore (real mode) and updates the
  /// local session immediately so the UI reflects the change without a refetch.
  Future<void> saveProfile(AstrologerAccount updated) async {
    if (!kBypassAuth) {
      await ref.read(astrologerServiceProvider).updateAccount(updated.id, {
        'photoUrl': updated.photoUrl,
        'experienceYears': updated.experienceYears,
        'languages': updated.languages,
        'expertise': updated.expertise,
        'consultationModes': updated.consultationModes,
        'consultationFee': updated.consultationFee,
        'about': updated.about,
      });
    }
    state = updated;
  }

  /// Persists the services list to Firestore (real mode) and updates the local
  /// session immediately.
  Future<void> saveServices(List<AstrologerService> services) async {
    final current = state;
    if (current == null) return;
    if (!kBypassAuth) {
      await ref
          .read(astrologerServiceProvider)
          .updateServices(current.id, services);
    }
    state = current.copyWith(services: services);
  }

  void signOut() => state = null;
}

final myAstrologerAccountProvider =
    NotifierProvider<MyAstrologerAccountNotifier, AstrologerAccount?>(
        MyAstrologerAccountNotifier.new);

final isAstrologerOnboardedProvider =
    Provider<bool>((ref) => ref.watch(myAstrologerAccountProvider) != null);

// ── Requests ─────────────────────────────────────────────────────────────────
// Real mode streams Firestore `astrologer_requests`; demo mode (kBypassAuth)
// serves the in-memory seed below so the dashboard is reviewable offline.

/// Demo seed for consultation/inquiry/matching requests. Mutable so
/// accept/reject works in demo too. Only used when [kBypassAuth] is true.
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
        userLocation: 'Chennai, Tamil Nadu',
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
        userLocation: 'Coimbatore, Tamil Nadu',
        type: AstrologerRequestType.matching,
        status: AstrologerRequestStatus.accepted,
        message: 'Please check porutham between my profile and Suresh Kumar.',
        amount: 199,
        profileAId: 'p1',
        profileBId: 'p2',
        createdAt: now.subtract(const Duration(hours: 5)),
        respondedAt: now.subtract(const Duration(hours: 4)),
      ),
      AstrologerRequestModel(
        id: 'req-3',
        astrologerId: 'demo-astrologer',
        userId: 'u3',
        userName: 'Anand Subramanian',
        userPhotoUrl: 'https://i.pravatar.cc/150?img=33',
        userLocation: 'Madurai, Tamil Nadu',
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
        userLocation: 'Trichy, Tamil Nadu',
        type: AstrologerRequestType.consultation,
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

/// Realtime requests addressed to the logged-in astrologer (consultations,
/// inquiries, horoscope matching). Demo mode → in-memory list above.
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

/// Total earnings = sum of completed-request amounts. Real Firestore in prod
/// (`watchEarnings`); derived from the demo seed when auth is bypassed.
final astrologerEarningsProvider = StreamProvider.autoDispose<int>((ref) {
  if (kBypassAuth) {
    final total = ref
        .watch(demoAstrologerRequestsProvider)
        .where((r) => r.status == AstrologerRequestStatus.completed)
        .fold<int>(0, (sum, r) => sum + r.amount);
    return Stream.value(total);
  }
  final account = ref.watch(myAstrologerAccountProvider);
  if (account == null) return Stream.value(0);
  return ref.read(astrologerServiceProvider).watchEarnings(account.id);
});

/// Appointments are derived from the consultation lifecycle (no separate
/// bookings collection is written): an **accepted** request is an *upcoming*
/// appointment, **completed** → *completed*, **rejected** → *cancelled*.
/// Pending requests stay in the Requests inbox until acted on.
enum AppointmentBucket { upcoming, completed, cancelled }

extension AstrologerRequestAppointmentX on AstrologerRequestModel {
  AppointmentBucket? get appointmentBucket {
    switch (status) {
      case AstrologerRequestStatus.accepted:
        return AppointmentBucket.upcoming;
      case AstrologerRequestStatus.completed:
        return AppointmentBucket.completed;
      case AstrologerRequestStatus.rejected:
        return AppointmentBucket.cancelled;
      case AstrologerRequestStatus.pending:
        return null;
    }
  }
}
