import '../models/interest_model.dart';
import '../services/firebase/firestore_service.dart';

class InterestRepository {
  final FirestoreService _firestore;

  InterestRepository(this._firestore);

  Future<void> sendInterest(InterestModel interest) => _firestore.sendInterest(interest);

  /// Accepts an interest AND records the connection that unlocks contact
  /// details for both users. Falls back to a plain status update if the
  /// interest document can't be loaded.
  ///
  /// IDEMPOTENT: an interest that is already accepted (double-tap, second
  /// device, retried call) is treated as success — re-issuing the status
  /// update would be denied by the rules (which only allow the one
  /// pending→accepted/rejected transition) and surface a false
  /// "Could not accept" error after the match had in fact succeeded.
  Future<void> acceptInterest(String interestId) async {
    final interest = await _firestore.getInterestById(interestId);
    if (interest == null) {
      return _firestore.updateInterestStatus(interestId, 'accepted');
    }
    if (interest.isAccepted) {
      // Already matched — just make sure the contact-unlock connection exists.
      await _firestore.createConnection(interest);
      return;
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

  /// Withdraws (unsends) an interest the signed-in user sent, by deleting the
  /// document so it disappears for both parties.
  Future<void> withdrawInterest(String interestId) =>
      _firestore.deleteInterest(interestId);

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
