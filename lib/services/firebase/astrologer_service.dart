import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../../models/astrologer_account_model.dart';
import '../../models/astrologer_model.dart';
import '../../models/astrologer_request_model.dart';

/// Firestore CRUD + realtime streams for the astrologer side of the app:
/// `astrologers/{uid}` accounts and `astrologer_requests` (consultations,
/// inquiries, horoscope-matching requests).
class AstrologerService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Accounts ────────────────────────────────────────────────────────────
  /// Creates (or overwrites) the astrologer account document and marks the
  /// auth user's role as `astrologer`.
  Future<void> createAccount(String uid, AstrologerAccount account) async {
    final batch = _db.batch();
    batch.set(
      _db.collection(AppConstants.astrologersCollection).doc(uid),
      {
        ...account.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    batch.set(
      _db.collection(AppConstants.usersCollection).doc(uid),
      {
        'role': AppConstants.roleAstrologer,
        'displayName': account.fullName,
        'phone': account.mobile,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<AstrologerAccount?> getAccount(String uid) async {
    final doc = await _db
        .collection(AppConstants.astrologersCollection)
        .doc(uid)
        .get();
    if (!doc.exists) return null;
    return AstrologerAccount.fromFirestore(doc);
  }

  Stream<AstrologerAccount?> watchAccount(String uid) => _db
      .collection(AppConstants.astrologersCollection)
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? AstrologerAccount.fromFirestore(doc) : null);

  Future<void> updateAccount(String uid, Map<String, dynamic> data) => _db
      .collection(AppConstants.astrologersCollection)
      .doc(uid)
      .update({...data, 'updatedAt': FieldValue.serverTimestamp()});

  /// Replaces the embedded services list on the astrologer's account doc.
  Future<void> updateServices(String uid, List<AstrologerService> services) =>
      updateAccount(
          uid, {'services': services.map((s) => s.toMap()).toList()});

  /// Approved astrologers visible to matrimony users.
  Stream<List<AstrologerAccount>> watchApprovedAstrologers() => _db
      .collection(AppConstants.astrologersCollection)
      .where('status', isEqualTo: 'approved')
      .snapshots()
      .map((s) => s.docs.map(AstrologerAccount.fromFirestore).toList());

  /// Every astrologer account (any status). The directory filters out rejected
  /// accounts client-side so newly signed-up (pending) astrologers also appear,
  /// and no composite index is needed.
  Stream<List<AstrologerAccount>> watchAllAstrologers() => _db
      .collection(AppConstants.astrologersCollection)
      .snapshots()
      .map((s) => s.docs.map(AstrologerAccount.fromFirestore).toList());

  // ── Requests (consultations / inquiries / horoscope matching) ──────────
  Future<void> createRequest(AstrologerRequestModel request) => _db
      .collection(AppConstants.astrologerRequestsCollection)
      .add(request.toFirestore())
      .then((_) {});

  /// Realtime stream of every request addressed to this astrologer.
  Stream<List<AstrologerRequestModel>> watchRequestsForAstrologer(
          String astrologerId) =>
      _db
          .collection(AppConstants.astrologerRequestsCollection)
          .where('astrologerId', isEqualTo: astrologerId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) =>
              s.docs.map(AstrologerRequestModel.fromFirestore).toList());

  /// Requests this matrimony user has sent (to track status).
  Stream<List<AstrologerRequestModel>> watchRequestsByUser(String userId) =>
      _db
          .collection(AppConstants.astrologerRequestsCollection)
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) =>
              s.docs.map(AstrologerRequestModel.fromFirestore).toList());

  Future<void> updateRequestStatus(
          String requestId, AstrologerRequestStatus status) =>
      _db
          .collection(AppConstants.astrologerRequestsCollection)
          .doc(requestId)
          .update({
        'status': status.name,
        'respondedAt': FieldValue.serverTimestamp(),
      });

  /// Sum of completed-request amounts → earnings shown on the dashboard.
  Stream<int> watchEarnings(String astrologerId) => _db
      .collection(AppConstants.astrologerRequestsCollection)
      .where('astrologerId', isEqualTo: astrologerId)
      .where('status', isEqualTo: 'completed')
      .snapshots()
      .map((s) => s.docs
          .fold<int>(0, (sum, d) => sum + ((d.data()['amount'] ?? 0) as int)));
}
