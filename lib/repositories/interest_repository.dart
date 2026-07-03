import '../models/interest_model.dart';
import '../services/firebase/firestore_service.dart';

class InterestRepository {
  final FirestoreService _firestore;

  InterestRepository(this._firestore);

  Future<void> sendInterest(InterestModel interest) => _firestore.sendInterest(interest);

  /// Accepts an interest AND records the connection that unlocks contact
  /// details for both users. Falls back to a plain status update if the
  /// interest document can't be loaded.
  Future<void> acceptInterest(String interestId) async {
    final interest = await _firestore.getInterestById(interestId);
    if (interest == null) {
      return _firestore.updateInterestStatus(interestId, 'accepted');
    }
    return _firestore.acceptInterestAndConnect(interest);
  }

  /// Backfills the contact-unlock connection for an already-accepted interest.
  Future<void> ensureConnection(InterestModel interest) =>
      _firestore.createConnection(interest);

  /// Loads a single interest straight from Firestore — used by the
  /// accepted-interest chat creation so it never depends on a provider cache.
  Future<InterestModel?> getInterestById(String interestId) =>
      _firestore.getInterestById(interestId);

  Future<void> rejectInterest(String interestId) =>
      _firestore.updateInterestStatus(interestId, 'rejected');

  Stream<List<InterestModel>> watchSentInterests(String userId) =>
      _firestore.watchSentInterests(userId);

  Stream<List<InterestModel>> watchReceivedInterests(String userId) =>
      _firestore.watchReceivedInterests(userId);

  Future<InterestModel?> getInterestBetweenProfiles(
    String senderProfileId,
    String receiverProfileId,
  ) =>
      _firestore.getInterestBetweenProfiles(senderProfileId, receiverProfileId);
}
