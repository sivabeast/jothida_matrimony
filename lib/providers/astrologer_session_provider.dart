import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/dev_config.dart';
import '../models/astrologer_account_model.dart';
import '../models/astrologer_certificate.dart';
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

  /// General-purpose save used by the profile-section edit screens. Persists
  /// every astrologer-editable field of [updated] in one write, but never
  /// clobbers admin/server-managed fields (rating, reviewCount, status,
  /// profileCompleted), then updates the local session immediately.
  Future<void> saveAccount(AstrologerAccount updated) async {
    final current = state;
    if (current == null) return;
    if (!kBypassAuth) {
      final data = updated.toFirestore()
        ..remove('rating')
        ..remove('reviewCount')
        ..remove('status')
        ..remove('profileCompleted');
      await ref.read(astrologerServiceProvider).updateAccount(current.id, data);
    }
    state = updated;
  }

  /// Flips the manual Available / Not Available switch and persists just that
  /// field, updating the local session immediately so the dashboard, directory
  /// and profile reflect the change instantly.
  Future<void> setManualAvailability(bool available) async {
    final current = state;
    if (current == null) return;
    // Optimistic local update first so the toggle feels instant.
    state = current.copyWith(manuallyAvailable: available);
    if (!kBypassAuth) {
      try {
        await ref
            .read(astrologerServiceProvider)
            .updateAccount(current.id, {'manuallyAvailable': available});
      } catch (e) {
        // Roll back on failure so the UI never lies about the saved state.
        state = current;
        rethrow;
      }
    }
  }

  /// "Available for Assignment" — whether the admin may assign this astrologer
  /// an expired/reassigned booking. Optimistic local update, then persists.
  Future<void> setAvailableForAssignment(bool value) async {
    final current = state;
    if (current == null) return;
    state = current.copyWith(availableForAssignment: value);
    if (!kBypassAuth) {
      try {
        await ref
            .read(astrologerServiceProvider)
            .updateAccount(current.id, {'availableForAssignment': value});
      } catch (e) {
        state = current;
        rethrow;
      }
    }
  }

  /// "On Leave" — temporarily excludes the astrologer from admin assignment.
  Future<void> setOnLeave(bool value) async {
    final current = state;
    if (current == null) return;
    state = current.copyWith(onLeave: value);
    if (!kBypassAuth) {
      try {
        await ref
            .read(astrologerServiceProvider)
            .updateAccount(current.id, {'onLeave': value});
      } catch (e) {
        state = current;
        rethrow;
      }
    }
  }

  /// Persists the astrologer's working days (subset of [kWeekdays]) and updates
  /// the local session immediately.
  Future<void> saveWorkingDays(List<String> days) async {
    final current = state;
    if (current == null) return;
    if (!kBypassAuth) {
      await ref
          .read(astrologerServiceProvider)
          .updateAccount(current.id, {'workingDays': days});
    }
    state = current.copyWith(workingDays: days);
  }

  /// Uploads a certificate file (PDF/JPG/PNG) to storage, appends it to the
  /// account's certificate list (with verified=false for admin review) and
  /// persists. In demo mode the file is recorded without a remote upload.
  Future<void> addCertificate(
    File file, {
    required String name,
    required String fileType,
  }) async {
    final current = state;
    if (current == null) return;
    String url = '';
    if (!kBypassAuth) {
      url = await ref.read(astrologerServiceProvider).uploadCertificate(
            uid: current.id,
            file: file,
            fileType: fileType,
          );
    }
    final cert = AstrologerCertificate(
      id: 'cert_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      url: url,
      fileType: fileType,
      uploadedAt: DateTime.now(),
    );
    await saveAccount(
        current.copyWith(certificates: [...current.certificates, cert]));
  }

  /// Removes a certificate by id and persists.
  Future<void> removeCertificate(String id) async {
    final current = state;
    if (current == null) return;
    await saveAccount(current.copyWith(
      certificates:
          current.certificates.where((c) => c.id != id).toList(),
    ));
  }

  /// TEST MODE subscription activation — no payment. [plan] is a tier id
  /// ('starter' | 'basic' | 'pro' | 'elite'), or legacy 'monthly' / 'yearly'.
  /// Tiered plans bill monthly ([days] = 30); legacy 'yearly' keeps a 365-day
  /// term. Writes the plan + price + expiry (and the explicit status fields) so
  /// the astrologer becomes visible to users immediately, then updates the
  /// local session.
  Future<void> activateSubscription(String plan,
      {int days = 30, int amount = 0}) async {
    final current = state;
    if (current == null) return;
    final now = DateTime.now();
    final termDays = plan == 'yearly' ? 365 : days;
    final end = now.add(Duration(days: termDays));
    if (!kBypassAuth) {
      await ref.read(astrologerServiceProvider).updateAccount(current.id, {
        'subscriptionPlan': plan,
        'subscriptionType': plan,
        'subscriptionAmount': amount,
        'subscriptionExpiry': Timestamp.fromDate(end),
        'subscriptionActive': true,
        'subscriptionStatus': 'active',
        'activatedAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(end),
      });
    }
    state = current.copyWith(subscriptionPlan: plan, subscriptionExpiry: end);
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

  /// Demo-mode booking: prepend a newly-created request so it appears in the
  /// astrologer inbox and the user's "My Match Analysis" immediately.
  void add(AstrologerRequestModel request) => state = [request, ...state];

  /// Demo-mode analysis submission: attach the report and mark completed.
  void submitAnalysis(
    String id, {
    required String text,
    required List<String> images,
    required List<String> pdfs,
  }) {
    state = [
      for (final r in state)
        r.id == id
            ? r.copyWith(
                status: AstrologerRequestStatus.completed,
                analysisText: text,
                analysisImages: images,
                analysisPdfs: pdfs,
                history: [
                  ...r.history,
                  BookingHistoryEntry.now('Report submitted'),
                ],
              )
            : r,
    ];
  }

  /// Demo-mode reassignment (admin Expired Bookings / user "choose another"):
  /// move the booking to a new astrologer with a fresh response window.
  void reassign(
    String id, {
    required String astrologerId,
    required String astrologerName,
    bool byAdmin = true,
  }) {
    state = [
      for (final r in state)
        r.id == id
            ? r.copyWith(
                astrologerId: astrologerId,
                astrologerName: astrologerName,
                status: AstrologerRequestStatus.pending,
                reassigned: true,
                reassignedAt: DateTime.now(),
                expired: false,
                expiresAt: DateTime.now().add(kBookingResponseWindow),
                history: [
                  ...r.history,
                  BookingHistoryEntry.now(byAdmin
                      ? 'Assigned by Admin to $astrologerName'
                      : 'Reassigned by you to $astrologerName'),
                  BookingHistoryEntry.now('Waiting for response'),
                ],
              )
            : r,
    ];
  }

  /// Demo-mode expiry: flag a pending booking as expired.
  void markExpired(String id) {
    state = [
      for (final r in state)
        r.id == id
            ? r.copyWith(
                expired: true,
                expiredAt: DateTime.now(),
                history: [
                  ...r.history,
                  BookingHistoryEntry.now('No response'),
                  BookingHistoryEntry.now('Expired'),
                ],
              )
            : r,
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
