/// Status of an interest request.
enum RequestStatus { pending, accepted, rejected }

/// Whether the request was received by ("incoming") or sent by ("outgoing")
/// the current user.
enum RequestDirection { incoming, outgoing }

/// A matrimony interest request between the current user and another profile.
///
/// Maps to the Firestore `interest_requests` collection:
/// { senderUserId, receiverUserId, status, createdAt }.
class InterestRequest {
  final String id;

  /// The OTHER party's profile id (the sender if incoming, the receiver if
  /// outgoing).
  final String profileId;
  final RequestDirection direction;
  final RequestStatus status;
  final DateTime timestamp;

  const InterestRequest({
    required this.id,
    required this.profileId,
    required this.direction,
    required this.status,
    required this.timestamp,
  });

  bool get isIncoming => direction == RequestDirection.incoming;
  bool get isAccepted => status == RequestStatus.accepted;

  InterestRequest copyWith({RequestStatus? status}) => InterestRequest(
        id: id,
        profileId: profileId,
        direction: direction,
        status: status ?? this.status,
        timestamp: timestamp,
      );

  String get statusLabel {
    switch (status) {
      case RequestStatus.pending:
        return 'Pending';
      case RequestStatus.accepted:
        return 'Accepted';
      case RequestStatus.rejected:
        return 'Declined';
    }
  }
}
