import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/dev_config.dart';
import '../core/data/sample_astrologers.dart';
import '../models/astrologer_account_model.dart';
import '../models/astrologer_model.dart';
import 'service_providers.dart';

/// Maps a Firestore astrologer account (`astrologers/{uid}`) to the directory
/// display model. If the account has no service catalogue but does have a flat
/// consultation fee, a single synthetic service is added so the card/`₹` shows
/// the right amount.
Astrologer astrologerFromAccount(AstrologerAccount a) {
  final services = a.services.isNotEmpty
      ? a.services
      : (a.consultationFee > 0
          ? [AstrologerService(name: 'Consultation', price: a.consultationFee.round())]
          : const <AstrologerService>[]);
  return Astrologer(
    id: a.id,
    name: a.fullName,
    photoUrl: a.photoUrl,
    location: a.city,
    rating: a.rating,
    reviewCount: a.reviewCount,
    experienceYears: a.experienceYears,
    languages: a.languages,
    specializations: a.expertise,
    certifications: a.certName.isEmpty ? const [] : [a.certName],
    services: services,
    reviews: const [],
    isAvailable: true,
    isRecommended: false,
    lastActive: DateTime.now(),
    about: a.about,
    // Verified badge shows only once an admin approves the account.
    verified: a.isApproved,
  );
}

/// Directory astrologers shown to USERS.
///
/// ⚠️ TEMPORARY (development/testing): verification, subscription and approval
/// filtering are DISABLED. Every astrologer is shown — both ✅ verified and ⏳
/// pending — so we can test profile loading, cards, search and the
/// Nearby/Top-Rated/All sections without gating. Only suspended astrologers
/// (status == rejected) are excluded. The card still shows the correct status
/// badge so verified vs. pending is identifiable.
///
/// TODO(restore): switch back to `watchApprovedAstrologers()` (verified-only,
/// plus active-subscription gating) before production. Firestore security rules
/// must also temporarily allow reading non-approved astrologer documents while
/// this is in effect.
final astrologersProvider = StreamProvider.autoDispose<List<Astrologer>>((ref) {
  if (kBypassAuth) return Stream.value(sampleAstrologers());
  return ref.watch(astrologerServiceProvider).watchAllAstrologers().map(
        (accounts) => accounts
            // Exclude only suspended/rejected (and there is no separate
            // "deleted" status — deleted docs simply don't exist).
            .where((a) => a.status != VerificationStatus.rejected)
            .map(astrologerFromAccount)
            .toList(),
      );
});

/// Top rated astrologers (rating desc).
final topRatedAstrologersProvider = Provider.autoDispose<List<Astrologer>>((ref) {
  final list = [...(ref.watch(astrologersProvider).valueOrNull ?? const <Astrologer>[])]
    ..sort((a, b) => b.rating.compareTo(a.rating));
  return list.take(6).toList();
});

/// Editorially recommended astrologers.
final recommendedAstrologersProvider = Provider.autoDispose<List<Astrologer>>((ref) =>
    (ref.watch(astrologersProvider).valueOrNull ?? const <Astrologer>[])
        .where((a) => a.isRecommended)
        .toList());

/// Recently active astrologers (most recent first).
final recentlyActiveAstrologersProvider = Provider.autoDispose<List<Astrologer>>((ref) {
  final list = [...(ref.watch(astrologersProvider).valueOrNull ?? const <Astrologer>[])]
    ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
  return list.take(6).toList();
});

/// Look up a single astrologer by id.
final astrologerByIdProvider =
    Provider.autoDispose.family<Astrologer?, String>((ref, id) {
  for (final a in ref.watch(astrologersProvider).valueOrNull ?? const <Astrologer>[]) {
    if (a.id == id) return a;
  }
  return null;
});
