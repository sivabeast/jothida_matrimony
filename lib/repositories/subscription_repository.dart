import '../models/subscription_model.dart';
import '../services/firebase/firestore_service.dart';

class SubscriptionRepository {
  final FirestoreService _firestore;

  SubscriptionRepository(this._firestore);

  Future<void> saveSubscription(SubscriptionModel sub) => _firestore.saveSubscription(sub);

  Future<SubscriptionModel?> getActiveSubscription(String userId) =>
      _firestore.getActiveSubscription(userId);
}
