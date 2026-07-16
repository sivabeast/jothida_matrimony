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
/// pages. Scoped to `astrologerEmail == my Gmail` (the stable assignment key),
/// so an astrologer only ever sees their OWN requests — and sees them even if
/// they were assigned before this astrologer's first sign-in.
final myAssignedRequestsProvider =
    StreamProvider.autoDispose<List<AstrologerRequestModel>>((ref) {
  final rawEmail = ref.watch(myAuthEmailProvider);
  if (rawEmail == null || rawEmail.trim().isEmpty) return Stream.value(const []);
  // Match the LOWERCASED email that assignment stores, so the query never
  // misses on a case difference between the token email and the registry key.
  final email = rawEmail.trim().toLowerCase();
  return ref
      .read(astrologerServiceProvider)
      .watchRequestsForAstrologerEmail(email)
      .map((list) {
    final sorted = [...list]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  });
});
