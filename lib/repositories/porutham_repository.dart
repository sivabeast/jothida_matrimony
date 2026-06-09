import '../models/porutham_model.dart';
import '../services/firebase/firestore_service.dart';

class PoruthamsRepository {
  final FirestoreService _firestore;

  PoruthamsRepository(this._firestore);

  Future<String> createRequest(PoruthamsModel model) => _firestore.createPoruthamsRequest(model);

  Future<void> submitResult(String id, PoruthamsResult result, String astrologerId) =>
      _firestore.submitPoruthamsResult(id, result, astrologerId);

  Stream<List<PoruthamsModel>> watchUserPoruthams(String userId) =>
      _firestore.watchUserPoruthams(userId);

  Future<List<PoruthamsModel>> getPendingPoruthams() => _firestore.getPendingPoruthams();
}
