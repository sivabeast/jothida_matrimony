import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/astrologer_request_model.dart';
import '../models/astrologer_team_member.dart';
import 'auth_provider.dart';
import 'service_providers.dart';

/// All registered astrology team members — powers the admin "Astrologer
/// Accounts" page.
final allAstrologerTeamProvider =
    StreamProvider.autoDispose<List<AstrologerTeamMember>>((ref) {
  return ref.read(astrologyTeamServiceProvider).watchAll();
});

/// The signed-in account's email — taken from the AUTH TOKEN first (always
/// present for Google sign-in, and exactly what the security rules compare
/// against), with the `users/{uid}` document as the fallback. Using the token
/// removes a whole failure mode: the employee portal no longer hangs when the
/// users-doc read is slow or fails.
final myAuthEmailProvider = Provider.autoDispose<String?>((ref) {
  final tokenEmail = ref.watch(firebaseAuthStreamProvider).valueOrNull?.email;
  if (tokenEmail != null && tokenEmail.trim().isNotEmpty) return tokenEmail;
  return ref.watch(currentUserProvider).valueOrNull?.email;
});

/// The signed-in astrologer's own registry entry (live), looked up by email so
/// an admin enable/disable reflects immediately. Null for non-astrologers.
final myAstrologerTeamMemberProvider =
    StreamProvider.autoDispose<AstrologerTeamMember?>((ref) {
  final email = ref.watch(myAuthEmailProvider);
  if (email == null || email.trim().isEmpty) {
    return Stream.value(null);
  }
  return ref.read(astrologyTeamServiceProvider).watchByEmail(email);
});

/// Every request assigned to the signed-in astrologer (any status), newest
/// first. Drives the astrologer Dashboard / Pending / In Progress / Completed
/// pages.
///
/// It is the UNION of two independent Firestore streams:
///   • by `astrologerEmail == my Gmail` — the stable key stamped at assignment
///     time (works even before the astrologer's first sign-in);
///   • by `astrologerId == my uid` — the ORIGINAL key. Once an employee has
///     logged in, their uid is linked to the registry so assignment stamps
///     `astrologerId = uid`; this path is served by the long-standing security
///     rule, so assignments reach the employee even if the newer
///     `astrologerEmail` read rule has not been deployed.
///
/// Unioning both keys (de-duplicated by doc id) means an assignment is
/// delivered whichever key matched, and a permission error / delay on ONE
/// source never blanks the other.
final myAssignedRequestsProvider =
    StreamProvider.autoDispose<List<AstrologerRequestModel>>((ref) {
  // Match the LOWERCASED email that assignment stores, so the query never
  // misses on a case difference between the token email and the registry key.
  final email = (ref.watch(myAuthEmailProvider) ?? '').trim().toLowerCase();
  final uid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid ?? '';
  if (email.isEmpty && uid.isEmpty) return Stream.value(const []);
  final svc = ref.read(astrologerServiceProvider);

  final controller = StreamController<List<AstrologerRequestModel>>();
  var latestEmail = const <AstrologerRequestModel>[];
  var latestUid = const <AstrologerRequestModel>[];

  void emit() {
    final map = <String, AstrologerRequestModel>{};
    for (final r in latestEmail) {
      map[r.id] = r;
    }
    for (final r in latestUid) {
      map.putIfAbsent(r.id, () => r);
    }
    final list = map.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!controller.isClosed) controller.add(list);
  }

  final subs = <StreamSubscription<List<AstrologerRequestModel>>>[];
  if (email.isNotEmpty) {
    subs.add(svc.watchRequestsForAstrologerEmail(email).listen(
      (list) {
        latestEmail = list;
        emit();
      },
      onError: (Object e) {
        debugPrint('[myAssignedRequests] email source error: $e');
        latestEmail = const [];
        emit();
      },
    ));
  }
  if (uid.isNotEmpty) {
    subs.add(svc.watchRequestsForAstrologer(uid).listen(
      (list) {
        latestUid = list;
        emit();
      },
      onError: (Object e) {
        debugPrint('[myAssignedRequests] uid source error: $e');
        latestUid = const [];
        emit();
      },
    ));
  }

  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    controller.close();
  });
  return controller.stream;
});
