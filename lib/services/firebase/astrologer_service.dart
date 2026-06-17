import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/app_constants.dart';
import '../../models/astrologer_account_model.dart';
import '../../models/astrologer_model.dart' as model;
import '../../models/astrologer_request_model.dart';
import '../../models/astrologer_review_model.dart';

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

  // ── Certificate upload (Cloudinary unsigned) ──────────────────────────────
  // Cloud name / preset are public client config (never the API secret).
  static const String _cloudName = 'dh8hzjx5q';
  static const String _uploadPreset = 'matrimony_profiles';

  /// Uploads a certificate file and returns its public URL. PDFs use the `raw`
  /// delivery type; images use `image`. Each upload gets a unique public_id so
  /// multiple certificates never overwrite one another.
  Future<String> uploadCertificate({
    required String uid,
    required File file,
    required String fileType,
  }) async {
    final resourceType = fileType.toLowerCase() == 'pdf' ? 'raw' : 'image';
    final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = 'jothida_matrimony/astrologers/$uid/certificates'
      ..fields['public_id'] = 'cert_${DateTime.now().millisecondsSinceEpoch}'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode == 200) {
      final url = (jsonDecode(response.body) as Map<String, dynamic>)['secure_url']
          as String?;
      if (url != null && url.isNotEmpty) return url;
    }
    throw Exception('Certificate upload failed (HTTP ${response.statusCode})');
  }

  // ── Admin verification actions ─────────────────────────────────────────────
  // Each method updates `astrologers/{uid}.status`. They log the attempt and
  // any failure so the cause (permission denied, missing doc, offline) is
  // visible in the console instead of surfacing as a vague "backend" error.

  /// Sets an astrologer's verification status. [uid] is the astrologer's
  /// Firestore document id (== their auth uid).
  Future<void> setVerificationStatus(
    String uid,
    VerificationStatus status, {
    String? rejectionReason,
  }) async {
    debugPrint('[AstrologerService] ✏️  setVerificationStatus('
        'uid=$uid, status=${status.name}) → astrologers/$uid');
    try {
      await updateAccount(uid, {
        'status': status.name,
        if (status == VerificationStatus.rejected && rejectionReason != null)
          'rejectionReason': rejectionReason,
      });
      debugPrint('[AstrologerService] ✅ status updated to ${status.name} for $uid');
    } on FirebaseException catch (e) {
      debugPrint('[AstrologerService] ❌ Firestore write failed '
          '(code=${e.code}): ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[AstrologerService] ❌ unexpected write failure: $e');
      rethrow;
    }
  }

  /// Approve a pending astrologer → they become visible to users and their
  /// dashboard verification banner clears on next load.
  Future<void> approveAstrologer(String uid) =>
      setVerificationStatus(uid, VerificationStatus.approved);

  /// Reject an astrologer's application (optionally with a reason).
  Future<void> rejectAstrologer(String uid, {String reason = ''}) =>
      setVerificationStatus(uid, VerificationStatus.rejected,
          rejectionReason: reason);

  /// Suspend a previously-approved astrologer → moves them back to
  /// "under review" (pending) so they lose live visibility without being
  /// permanently rejected.
  Future<void> suspendAstrologer(String uid) =>
      setVerificationStatus(uid, VerificationStatus.pending);

  /// Replaces the embedded services list on the astrologer's account doc.
  Future<void> updateServices(
          String uid, List<model.AstrologerService> services) =>
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
  ///
  /// NOTE: intentionally a single-field equality query with NO `orderBy` — that
  /// combination would require a composite Firestore index and, until it was
  /// created, the stream would error (and every astrologer tab would show the
  /// "Try Again" state). The astrologer tabs already sort by `createdAt`
  /// client-side, so ordering here is unnecessary.
  Stream<List<AstrologerRequestModel>> watchRequestsForAstrologer(
          String astrologerId) =>
      _db
          .collection(AppConstants.astrologerRequestsCollection)
          .where('astrologerId', isEqualTo: astrologerId)
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

  // ── Ratings & reviews (astrologer_reviews) ─────────────────────────────────
  // Each user has at most one review per astrologer (deterministic doc id). The
  // astrologer document's `rating` / `reviewCount` / `ratingBreakdown` are kept
  // as a denormalised aggregate so the directory cards and Top-Rated section can
  // sort/show without reading every review.

  /// Live reviews for an astrologer, newest first. No `orderBy` in the query
  /// (would need a composite index); sorted client-side.
  Stream<List<AstrologerReviewModel>> watchReviews(String astrologerId) => _db
      .collection(AppConstants.astrologerReviewsCollection)
      .where('astrologerId', isEqualTo: astrologerId)
      .snapshots()
      .map((s) {
        final list =
            s.docs.map(AstrologerReviewModel.fromFirestore).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  /// The signed-in user's own review of [astrologerId], or null if none.
  Future<AstrologerReviewModel?> getMyReview(
      String astrologerId, String userId) async {
    final doc = await _db
        .collection(AppConstants.astrologerReviewsCollection)
        .doc(AstrologerReviewModel.docId(astrologerId, userId))
        .get();
    return doc.exists ? AstrologerReviewModel.fromFirestore(doc) : null;
  }

  /// Creates or edits the user's single review, then refreshes the astrologer's
  /// aggregate rating. The deterministic id makes a re-submit an edit, never a
  /// duplicate.
  Future<void> submitReview({
    required String astrologerId,
    required String userId,
    required String userName,
    required int rating,
    String review = '',
  }) async {
    final ref = _db
        .collection(AppConstants.astrologerReviewsCollection)
        .doc(AstrologerReviewModel.docId(astrologerId, userId));
    final existing = await ref.get();
    await ref.set({
      'astrologerId': astrologerId,
      'userId': userId,
      'userName': userName,
      'rating': rating,
      'review': review,
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _recomputeAstrologerRating(astrologerId);
  }

  /// Recomputes `rating` (mean), `reviewCount` and `ratingBreakdown` on the
  /// astrologer document from all of its reviews. Updates only those aggregate
  /// fields (a write the security rules allow any signed-in user to make).
  Future<void> _recomputeAstrologerRating(String astrologerId) async {
    final snap = await _db
        .collection(AppConstants.astrologerReviewsCollection)
        .where('astrologerId', isEqualTo: astrologerId)
        .get();
    final ratings = snap.docs
        .map((d) => (d.data()['rating'] as num?)?.toInt() ?? 0)
        .where((r) => r >= 1 && r <= 5)
        .toList();
    final count = ratings.length;
    final avg =
        count == 0 ? 0.0 : ratings.reduce((a, b) => a + b) / count;
    final breakdown = <String, int>{};
    for (final r in ratings) {
      breakdown['$r'] = (breakdown['$r'] ?? 0) + 1;
    }
    await _db
        .collection(AppConstants.astrologersCollection)
        .doc(astrologerId)
        .set({
      'rating': double.parse(avg.toStringAsFixed(2)),
      'reviewCount': count,
      'ratingBreakdown': breakdown,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Sum of completed-request amounts → earnings shown on the dashboard.
  ///
  /// Filters by `astrologerId` only (single-field index, always available) and
  /// applies the `status == completed` filter client-side. Two equality `where`
  /// clauses on different fields would otherwise require a composite index, and
  /// `amount` is read through `num` so a value stored as a double (e.g. 199.0)
  /// can never crash the stream with a bad `as int` cast.
  Stream<int> watchEarnings(String astrologerId) => _db
      .collection(AppConstants.astrologerRequestsCollection)
      .where('astrologerId', isEqualTo: astrologerId)
      .snapshots()
      .map((s) => s.docs.where((d) => d.data()['status'] == 'completed').fold<int>(
          0, (sum, d) => sum + ((d.data()['amount'] ?? 0) as num).toInt()));
}
