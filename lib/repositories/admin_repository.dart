import '../models/user_model.dart';
import '../models/profile_model.dart';
import '../models/report_model.dart';
import '../models/dashboard_analytics.dart';
import '../services/firebase/firestore_service.dart';

class AdminRepository {
  final FirestoreService _firestore;

  AdminRepository(this._firestore);

  Future<List<UserModel>> getAllUsers({int limit = 50}) => _firestore.getAllUsers(limit: limit);

  Future<List<ProfileModel>> getPendingProfiles() => _firestore.getPendingProfiles();

  Future<void> approveProfile(String profileId) => _firestore.approveProfile(profileId);

  Future<void> rejectProfile(String profileId, String reason) =>
      _firestore.rejectProfile(profileId, reason);

  Future<void> blockUser(String userId) => _firestore.blockUser(userId);

  Future<List<ReportModel>> getAllReports() => _firestore.getAllReports();

  Future<Map<String, dynamic>> getAdminStats() => _firestore.getAdminStats();

  Future<DashboardAnalytics> getDashboardAnalytics() =>
      _firestore.getDashboardAnalytics();
}
