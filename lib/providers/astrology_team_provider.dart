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

/// The signed-in astrologer's own registry entry (live), looked up by email so
/// an admin enable/disable reflects immediately. Null for non-astrologers.
final myAstrologerTeamMemberProvider =
    StreamProvider.autoDispose<AstrologerTeamMember?>((ref) {
  final email = ref.watch(currentUserProvider).valueOrNull?.email;
  if (email == null || email.trim().isEmpty) {
    return Stream.value(null);
  }
  return ref.read(astrologyTeamServiceProvider).watchByEmail(email);
});

/// Every request assigned to the signed-in astrologer (any status), newest
/// first. Drives the astrologer Dashboard / Pending / Completed pages. The
/// underlying query is scoped to `astrologerId == myUid`, so an astrologer can
/// only ever see their OWN requests.
final myAssignedRequestsProvider =
    StreamProvider.autoDispose<List<AstrologerRequestModel>>((ref) {
  final uid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.read(astrologerServiceProvider).watchRequestsForAstrologer(uid).map(
    (list) {
      final sorted = [...list]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sorted;
    },
  );
});
