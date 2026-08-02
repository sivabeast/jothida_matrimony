import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../models/astrology_service_config.dart';

/// Read / stream / update the ONE astrology service configuration document,
/// `astrology_service/config`.
///
/// SINGLE SOURCE OF TRUTH: Astrology Management (admin) writes here and the user
/// app reads here — the same collection, the same document. There is no second
/// copy of this data anywhere, so "the admin saved but the user app still shows
/// the old values" can only ever be a delivery problem, never a divergence.
///
/// The doc is world-readable to signed-in users (the service page + booking need
/// the charge/slots/office) and writable only by an admin, enforced in
/// firestore.rules.
class AstrologyConfigService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _collection = 'astrology_service';
  static const String _docId = 'config';

  /// How long to wait before re-subscribing after a listener error.
  static const Duration _retryDelay = Duration(seconds: 4);

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection(_collection).doc(_docId);

  /// LIVE config — a realtime `snapshots()` listener, so every admin save is
  /// pushed to the user app immediately, with no refresh and no app restart.
  ///
  /// The stream is SELF-HEALING: a Firestore listener that errors (a transient
  /// network drop, an App Check retry, or a permission-denied because the rules
  /// have not been deployed yet) is torn down and re-subscribed after
  /// [_retryDelay], instead of leaving the provider stuck in an error state for
  /// the rest of the session. That "stuck listener" is precisely what made
  /// Astrology Management changes look like they never arrived: one early
  /// failure and the page never updated again.
  ///
  /// Errors are still forwarded to the listener so the UI can show a real
  /// message — it must never silently substitute hardcoded defaults for the
  /// admin's live data.
  Stream<AstrologyServiceConfig> watch() {
    late final StreamController<AstrologyServiceConfig> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub;
    Timer? retry;
    var closed = false;

    void subscribe() {
      sub = _doc.snapshots().listen(
        (snap) {
          try {
            controller.add(snap.exists
                ? AstrologyServiceConfig.fromFirestore(snap)
                : AstrologyServiceConfig.defaults);
          } catch (e, st) {
            debugPrint('[AstrologyConfig] malformed config document: $e');
            controller.addError(e, st);
          }
        },
        onError: (Object e, StackTrace st) {
          debugPrint('[AstrologyConfig] listener error (re-subscribing in '
              '${_retryDelay.inSeconds}s): $e');
          controller.addError(e, st);
          sub?.cancel();
          sub = null;
          retry?.cancel();
          retry = Timer(_retryDelay, () {
            if (!closed) subscribe();
          });
        },
      );
    }

    controller = StreamController<AstrologyServiceConfig>(
      onListen: subscribe,
      onCancel: () async {
        closed = true;
        retry?.cancel();
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  Future<AstrologyServiceConfig> get() async {
    final d = await _doc.get();
    return d.exists
        ? AstrologyServiceConfig.fromFirestore(d)
        : AstrologyServiceConfig.defaults;
  }

  /// Admin save (merge) of the full config — the ONLY write path.
  Future<void> save(AstrologyServiceConfig config) =>
      _doc.set(config.toFirestore(), SetOptions(merge: true));

  /// Best-effort: stamp the internal astrology account's real uid onto the
  /// config the first time it logs in, so purchases can pre-create the chat.
  Future<void> setInternalUid(String uid) =>
      _doc.set({'internalUid': uid}, SetOptions(merge: true));
}
