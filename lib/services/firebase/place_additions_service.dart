import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/utils/place_additions.dart';
import 'master_options_service.dart';

/// Why saving a new place failed — each maps to its own message.
enum PlaceSaveFailure {
  /// No connection, or the server did not answer in time.
  offline,

  /// The security rules refused the write (e.g. a guest session).
  notAllowed,

  /// Anything else.
  unknown,
}

class PlaceSaveException implements Exception {
  final PlaceSaveFailure reason;
  final Object? cause;
  const PlaceSaveException(this.reason, [this.cause]);

  @override
  String toString() => 'PlaceSaveException($reason: $cause)';
}

/// The outcome of [PlaceAdditionsService.add].
class PlaceAddResult {
  final PlaceAddition place;

  /// True when the place was already on the list (possibly added by another
  /// member a moment earlier) — it is selected, nothing new was written.
  final bool alreadyExisted;

  const PlaceAddResult(this.place, {required this.alreadyExisted});
}

/// Member-added places, stored in `master_options/places` — the existing
/// "+ Add" collection for values the bundled master data is missing (see
/// `core/utils/place_additions.dart` for why this is not a JSON asset).
///
/// The document is `{ entries: [row, …], nextId, updatedAt }`. Additions are
/// APPEND-ONLY, which the deployed `master_options` rule already enforces
/// (`entries` may never shrink; only admins may remove a row).
class PlaceAdditionsService {
  static const collection = MasterOptionsService.collection;
  static const docId = 'places';

  FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ??= FirebaseFirestore.instance;

  PlaceAdditionsService({FirebaseFirestore? firestore})
    : _firestore = firestore;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection(collection).doc(docId);

  /// Every usable member-added place, live. Emits an empty list (never an
  /// error) when the document is missing or unreadable, so the bundled
  /// locations always load.
  Stream<List<PlaceAddition>> watch() => _doc
      .snapshots()
      .map(
        (d) => parsePlaceAdditions(
          (d.data()?['entries'] as List?) ?? const <Object?>[],
        ),
      )
      .transform(
        StreamTransformer<
          List<PlaceAddition>,
          List<PlaceAddition>
        >.fromHandlers(
          handleError: (e, st, sink) {
            debugPrint('[PlaceAdditions] places unavailable: $e');
            sink.add(const <PlaceAddition>[]);
          },
        ),
      );

  /// Adds [name] under [parent] for member [uid], or returns the matching
  /// place already on the list.
  ///
  /// A TRANSACTION, deliberately: the duplicate check and the append must see
  /// the same document. Two members adding at the same moment cannot
  /// overwrite each other — Firestore re-runs the losing transaction on the
  /// fresh document, where it either finds the other member's identical place
  /// (and selects it) or appends after it with the next id. A transaction also
  /// needs the server, which is what we want here: the member is told the
  /// place was saved only once it really was.
  Future<PlaceAddResult> add({
    required String name,
    required PlaceParent parent,
    required String uid,
  }) async {
    try {
      return await _db.runTransaction<PlaceAddResult>((tx) async {
        final snap = await tx.get(_doc);
        final data = snap.data() ?? const <String, dynamic>{};
        final plan = planPlaceAddition(
          rawEntries: List<Object?>.of((data['entries'] as List?) ?? const []),
          storedNextId: (data['nextId'] as num?)?.toInt(),
          name: name,
          parent: parent,
          addedBy: uid,
          now: DateTime.now().millisecondsSinceEpoch,
        );
        if (plan.isDuplicate) {
          return PlaceAddResult(plan.existing!, alreadyExisted: true);
        }
        tx.set(_doc, {
          'entries': plan.entries,
          'nextId': plan.nextId,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return PlaceAddResult(plan.added!, alreadyExisted: false);
      }, timeout: const Duration(seconds: 20));
    } on FirebaseException catch (e) {
      debugPrint('[PlaceAdditions] add "$name" failed: ${e.code} ${e.message}');
      throw PlaceSaveException(switch (e.code) {
        'permission-denied' || 'unauthenticated' => PlaceSaveFailure.notAllowed,
        'unavailable' || 'deadline-exceeded' => PlaceSaveFailure.offline,
        _ => PlaceSaveFailure.unknown,
      }, e);
    } on TimeoutException catch (e) {
      throw PlaceSaveException(PlaceSaveFailure.offline, e);
    } on PlaceSaveException {
      rethrow;
    } catch (e) {
      debugPrint('[PlaceAdditions] add "$name" failed: $e');
      throw PlaceSaveException(PlaceSaveFailure.unknown, e);
    }
  }
}
