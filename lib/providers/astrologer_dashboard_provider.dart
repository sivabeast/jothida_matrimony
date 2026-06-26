import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/astrologer_request_model.dart';
import '../models/consultation_model.dart';
import 'astrologer_session_provider.dart';
import 'consultation_provider.dart';

/// Which kind of incoming work an inbox item represents.
enum AstrologerInboxKind { matchRequest, consultation }

/// One unified entry in the astrologer dashboard's top "New Requests" feed —
/// either a match-analysis request or a consultation booking, normalised so the
/// UI can render them in a single newest-first list.
class AstrologerInboxItem {
  final AstrologerInboxKind kind;
  final DateTime createdAt;
  final String userName;
  final String userPhotoUrl;
  final String typeLabel; // 'Match Analysis' | 'In-App Consultation' | …
  final String statusLabel; // current status, e.g. 'Pending'

  /// Set when [kind] == matchRequest.
  final AstrologerRequestModel? request;

  /// Set when [kind] == consultation.
  final ConsultationBooking? consultation;

  const AstrologerInboxItem({
    required this.kind,
    required this.createdAt,
    required this.userName,
    required this.userPhotoUrl,
    required this.typeLabel,
    required this.statusLabel,
    this.request,
    this.consultation,
  });

  /// True while the item is still awaiting the astrologer's first action.
  bool get isPending => kind == AstrologerInboxKind.matchRequest
      ? request?.status == AstrologerRequestStatus.pending
      : consultation?.status == ConsultationStatus.pending;
}

/// Unified, realtime "incoming activity" feed for the dashboard's top
/// notifications: every match-analysis request + consultation booking addressed
/// to this astrologer, newest first. Updates instantly as new bookings arrive —
/// both sources are Firestore streams, so no manual refresh is ever needed.
final astrologerInboxProvider =
    Provider.autoDispose<List<AstrologerInboxItem>>((ref) {
  final requests =
      ref.watch(astrologerRequestsProvider).valueOrNull ?? const [];
  final consultations =
      ref.watch(astrologerConsultationsProvider).valueOrNull ?? const [];

  final items = <AstrologerInboxItem>[
    for (final r in requests)
      AstrologerInboxItem(
        kind: AstrologerInboxKind.matchRequest,
        createdAt: r.createdAt,
        userName: r.userName,
        userPhotoUrl: r.userPhotoUrl,
        typeLabel: r.type.label,
        statusLabel: r.status.label,
        request: r,
      ),
    for (final c in consultations)
      AstrologerInboxItem(
        kind: AstrologerInboxKind.consultation,
        createdAt: c.createdAt,
        userName: c.userName,
        userPhotoUrl: c.userPhotoUrl,
        typeLabel: c.mode.label,
        statusLabel: c.statusLabel,
        consultation: c,
      ),
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return items;
});

/// Count of incoming items still awaiting the astrologer's first action.
final astrologerPendingInboxCountProvider = Provider.autoDispose<int>(
    (ref) => ref.watch(astrologerInboxProvider).where((i) => i.isPending).length);

// ── Dashboard "new requests" unread banner (spec §1) ─────────────────────────
// The dashboard no longer lists request cards — it shows a single compact unread
// banner. "Unread" is tracked per-device: the timestamp the astrologer last
// opened the Requests page. Any still-pending booking created after that counts
// as new, exactly like the announcements unread badge.

const String _kRequestsLastSeenKey = 'astrologer_requests_last_seen_ms';

class _RequestsSeenNotifier extends Notifier<int> {
  @override
  int build() {
    _load();
    return 0;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getInt(_kRequestsLastSeenKey) ?? 0;
    } catch (_) {/* keep 0 */}
  }

  /// Marks all current requests as seen (call when the Requests page opens).
  Future<void> markSeen() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    state = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kRequestsLastSeenKey, now);
    } catch (_) {/* best-effort */}
  }
}

final requestsLastSeenProvider =
    NotifierProvider<_RequestsSeenNotifier, int>(_RequestsSeenNotifier.new);

/// New (still-pending) match-analysis requests since the astrologer last opened
/// the Requests page.
final newMatchAnalysisCountProvider = Provider.autoDispose<int>((ref) {
  final lastSeen = ref.watch(requestsLastSeenProvider);
  final requests =
      ref.watch(astrologerRequestsProvider).valueOrNull ?? const [];
  return requests
      .where((r) =>
          r.isMatchAnalysis &&
          r.status == AstrologerRequestStatus.pending &&
          !r.isEffectivelyExpired &&
          r.createdAt.millisecondsSinceEpoch > lastSeen)
      .length;
});

/// New (still-pending) direct-visit bookings since last seen.
final newDirectVisitCountProvider = Provider.autoDispose<int>((ref) {
  final lastSeen = ref.watch(requestsLastSeenProvider);
  final consultations =
      ref.watch(astrologerConsultationsProvider).valueOrNull ?? const [];
  return consultations
      .where((c) =>
          c.isDirectVisit &&
          c.status == ConsultationStatus.pending &&
          c.createdAt.millisecondsSinceEpoch > lastSeen)
      .length;
});

/// Total unread new requests — drives the bottom-nav badge + dashboard banner.
final unreadRequestsCountProvider = Provider.autoDispose<int>((ref) =>
    ref.watch(newMatchAnalysisCountProvider) +
    ref.watch(newDirectVisitCountProvider));
