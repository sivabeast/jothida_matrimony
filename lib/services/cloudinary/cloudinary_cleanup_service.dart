import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'cloudinary_asset_id.dart';

/// Deletes Cloudinary assets for real (spec §12).
///
/// Cloudinary's destroy API must be called with a request signed by the API
/// SECRET, which cannot ship inside the app. So the client resolves the assets
/// and asks the `deleteCloudinaryAssets` Cloud Function to do the deleting;
/// the secret stays on the server.
///
/// Failures are never swallowed. Whatever the function could not delete is
/// recorded in `cloudinary_cleanup` (by the function), and if the CALL itself
/// fails — offline, function not deployed, permission denied — this records the
/// attempt from the client instead, so an orphaned asset is always findable
/// rather than leaking silently.
class CloudinaryCleanupService {
  static const String _queueCollection = 'cloudinary_cleanup';

  final FirebaseFunctions _functions;
  final FirebaseFirestore _db;

  CloudinaryCleanupService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  })  : _functions = functions ?? FirebaseFunctions.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  /// Deletes every Cloudinary asset behind [urls].
  ///
  /// Non-Cloudinary and blank URLs are skipped. Returns the number of assets
  /// confirmed deleted; a return of 0 with a non-empty input means the cleanup
  /// needs attention (and has been queued).
  Future<int> deleteByUrls(Iterable<String?> urls, {String reason = ''}) async {
    final refs = cloudinaryRefsFromUrls(urls);
    if (refs.isEmpty) return 0;
    return deleteRefs(refs, reason: reason);
  }

  Future<int> deleteRefs(List<CloudinaryAssetRef> refs,
      {String reason = ''}) async {
    if (refs.isEmpty) return 0;
    final payload = [
      for (final r in refs)
        {'publicId': r.publicId, 'resourceType': r.resourceType},
    ];
    try {
      final res = await _functions
          .httpsCallable('deleteCloudinaryAssets')
          .call<Map<String, dynamic>>({'assets': payload});
      final data = res.data;
      final deleted = (data['deleted'] as num?)?.toInt() ?? 0;
      final failed = (data['failed'] as num?)?.toInt() ?? 0;
      debugPrint('[CloudinaryCleanup] deleted=$deleted failed=$failed '
          '(${refs.length} requested, reason=$reason)');
      return deleted;
    } catch (e) {
      // The call itself did not get through, so NOTHING was deleted. Queue the
      // whole batch so the assets can be reconciled later.
      debugPrint('[CloudinaryCleanup] call failed ($e) — queuing '
          '${refs.length} asset(s) for later cleanup.');
      await _queue(payload, reason: reason, error: '$e');
      return 0;
    }
  }

  /// Best-effort record of assets that still need deleting. Never throws: a
  /// queue write that fails must not break the user-facing action that
  /// triggered the cleanup.
  Future<void> _queue(List<Map<String, String>> assets,
      {required String reason, required String error}) async {
    try {
      await _db.collection(_queueCollection).add({
        'assets': assets,
        'reason': reason,
        'error': error,
        'resolved': false,
        'source': 'client',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[CloudinaryCleanup] queue write failed too: $e');
    }
  }
}
