import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/interest_request_model.dart';

/// In-memory interest-request store for demo mode.
///
/// Models the full lifecycle: a user sends an interest (outgoing · pending);
/// the receiver accepts (→ accepted, which creates a "match") or rejects
/// (→ rejected). A "match" is simply any request whose status is `accepted` —
/// only matched profiles unlock the compatibility analysis.
///
/// TODO(backend): back this with Firestore `interest_requests` + `matches`
/// collections and push notifications to the `notifications` collection.
class RequestsNotifier extends Notifier<List<InterestRequest>> {
  int _counter = 0;

  @override
  List<InterestRequest> build() => _sample();

  List<InterestRequest> _sample() {
    final now = DateTime.now();
    InterestRequest r(String profileId, RequestDirection dir, RequestStatus st,
            Duration ago) =>
        InterestRequest(
          id: 'req_${profileId}_${dir.name}',
          profileId: profileId,
          direction: dir,
          status: st,
          timestamp: now.subtract(ago),
        );

    return [
      // Incoming — waiting on the user to accept/reject
      r('sample_m2', RequestDirection.incoming, RequestStatus.pending,
          const Duration(minutes: 25)),
      r('sample_m3', RequestDirection.incoming, RequestStatus.pending,
          const Duration(hours: 3)),
      // Incoming already accepted → a match
      r('sample_m1', RequestDirection.incoming, RequestStatus.accepted,
          const Duration(days: 1)),
      // Outgoing
      r('sample_f1', RequestDirection.outgoing, RequestStatus.accepted,
          const Duration(days: 2)),
      r('sample_f2', RequestDirection.outgoing, RequestStatus.pending,
          const Duration(hours: 6)),
      r('sample_f3', RequestDirection.outgoing, RequestStatus.rejected,
          const Duration(days: 4)),
    ];
  }

  /// Send an interest to [profileId] (outgoing · pending). No-op if one already
  /// exists, preventing duplicates.
  void sendInterest(String profileId) {
    final exists = state.any(
        (x) => x.profileId == profileId && x.direction == RequestDirection.outgoing);
    if (exists) return;
    state = [
      InterestRequest(
        id: 'req_new_${_counter++}',
        profileId: profileId,
        direction: RequestDirection.outgoing,
        status: RequestStatus.pending,
        timestamp: DateTime.now(),
      ),
      ...state,
    ];
  }

  /// Accept an incoming request → status accepted (creates a match).
  void accept(String id) => _setStatus(id, RequestStatus.accepted);

  /// Reject an incoming request → status rejected.
  void reject(String id) => _setStatus(id, RequestStatus.rejected);

  void _setStatus(String id, RequestStatus status) {
    state = [
      for (final x in state) x.id == id ? x.copyWith(status: status) : x,
    ];
  }
}

final requestsProvider =
    NotifierProvider<RequestsNotifier, List<InterestRequest>>(RequestsNotifier.new);

final incomingRequestsProvider = Provider<List<InterestRequest>>((ref) => ref
    .watch(requestsProvider)
    .where((r) => r.direction == RequestDirection.incoming)
    .toList());

final outgoingRequestsProvider = Provider<List<InterestRequest>>((ref) => ref
    .watch(requestsProvider)
    .where((r) => r.direction == RequestDirection.outgoing)
    .toList());

/// Accepted connections (matches).
final matchesProvider = Provider<List<InterestRequest>>((ref) =>
    ref.watch(requestsProvider).where((r) => r.isAccepted).toList());

/// True once the user has a mutually-accepted match with [profileId] — gates
/// the compatibility analysis.
final isMatchedProvider = Provider.family<bool, String>((ref, profileId) => ref
    .watch(requestsProvider)
    .any((r) => r.profileId == profileId && r.isAccepted));

/// True if the user already sent an interest to [profileId].
final hasSentInterestProvider = Provider.family<bool, String>((ref, profileId) =>
    ref.watch(requestsProvider).any((r) =>
        r.profileId == profileId && r.direction == RequestDirection.outgoing));
