import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/dev_config.dart';
import '../models/astrologer_request_model.dart';

/// Employee-facing request providers.
///
/// There is NO astrologer account or astrologer session in this app: employees
/// (horoscope-analysis staff) sign in through the SAME common login as
/// everyone else, and appointments are never assigned to anyone.

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

  /// Demo-mode: flag an accepted booking as In Progress (astrologer started).
  void markInProgress(String id) {
    state = [
      for (final r in state)
        r.id == id
            ? r.copyWith(
                inProgress: true,
                startedAt: DateTime.now(),
                history: [
                  ...r.history,
                  BookingHistoryEntry.now('Analysis in progress'),
                ],
              )
            : r,
    ];
  }

  /// Demo-mode payment: flag an accepted booking as paid with a demo txn id.
  void markPaid(String id, {required String paymentId}) {
    state = [
      for (final r in state)
        r.id == id
            ? r.copyWith(
                paid: true,
                paidAt: DateTime.now(),
                paymentId: paymentId,
                history: [
                  ...r.history,
                  BookingHistoryEntry.now('Payment received ($paymentId)'),
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
