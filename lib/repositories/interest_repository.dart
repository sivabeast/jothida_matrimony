import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/interest_model.dart';
import '../services/firebase/firestore_service.dart';

class InterestRepository {
  final FirestoreService _firestore;

  InterestRepository(this._firestore);

  Future<void> sendInterest(InterestModel interest) => _firestore.sendInterest(interest);

  Future<void> acceptInterest(String interestId) =>
      _firestore.updateInterestStatus(interestId, 'accepted');

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
