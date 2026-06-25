import 'package:flutter_riverpod/flutter_riverpod.dart';
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
