import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/utils/login_identifier.dart';
import '../../models/password_reset_request.dart';

/// Admin-assisted password recovery: the member files a request, the admin
/// verifies identity and resolves it (see PasswordResetRequestsScreen).
class PasswordResetRequestService {
  final FirebaseFirestore _db;

  PasswordResetRequestService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppConstants.passwordResetRequestsCollection);

  /// Files a request from the (possibly anonymous) recovery session.
  ///
  /// One per number per day: the id is `{mobile}_{dayKey}` and the security
  /// rules only allow CREATING it, so a second submission the same day is
  /// refused server-side — that is the abuse limit, not a client check.
  /// Returns false when today's request already exists.
  Future<bool> submit({
    required String uid,
    required String mobile,
    String name = '',
    String description = '',
    DateTime? now,
  }) async {
    final local = LoginIdentifier.localMobile(mobile);
    if (local == null) {
      throw const AuthException('Enter a valid 10-digit mobile number.',
          code: 'invalid-mobile');
    }
    final day = PasswordResetRequest.dayKeyFor(now ?? DateTime.now());
    final ref = _col.doc(PasswordResetRequest.idFor(local, day));
    try {
      await ref.set({
        'mobile': local,
        'name': name.trim().substring(
            0,
            name.trim().length.clamp(0, PasswordResetRequest.maxNameLength)),
        'description': description.trim().substring(
            0,
            description
                .trim()
                .length
                .clamp(0, PasswordResetRequest.maxDescriptionLength)),
        'status': PasswordResetStatus.pending.stored,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': uid,
        'dayKey': day,
        'source': 'app',
      }).timeout(const Duration(seconds: 20));
      return true;
    } on FirebaseException catch (e) {
      // The document exists already (a create-only rule answers an overwrite
      // with permission-denied) — today's request is already with the admin.
      if (e.code == 'permission-denied') {
        debugPrint('[PasswordResetRequest] submit refused for $local: '
            '${e.message}');
        return false;
      }
      rethrow;
    }
  }

  /// ADMIN: every request, newest first.
  Stream<List<PasswordResetRequest>> watchAll({int limit = 500}) => _col
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) PasswordResetRequest.fromFirestore(d)]);

  /// ADMIN: moves a request to [status], appending to its history.
  Future<void> updateStatus(
    String id, {
    required PasswordResetStatus status,
    required String adminUid,
    String note = '',
    String resolution = '',
  }) =>
      _col.doc(id).update({
        'status': status.stored,
        'updatedAt': FieldValue.serverTimestamp(),
        'handledBy': adminUid,
        if (note.trim().isNotEmpty) 'adminNote': note.trim(),
        if (resolution.isNotEmpty) 'resolution': resolution,
        if (!status.isOpen) 'resolvedAt': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([
          {
            'status': status.stored,
            'by': adminUid,
            'at': Timestamp.now(),
            if (note.trim().isNotEmpty) 'note': note.trim(),
          }
        ]),
      });

  /// ADMIN: pending requests count (drawer badge).
  Stream<int> watchOpenCount() => _col
      .where('status', whereIn: [
        PasswordResetStatus.pending.stored,
        PasswordResetStatus.underReview.stored,
      ])
      .snapshots()
      .map((s) => s.size);
}
