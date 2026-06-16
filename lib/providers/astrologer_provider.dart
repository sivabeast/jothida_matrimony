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
    // Direct-contact details + read-only certificate documents for the profile.
    phone: a.mobile,
    certificateDocs:
        a.certificates.where((c) => c.url.isNotEmpty && !c.isRejected).toList(),
  );
}

/// Directory astrologers shown to USERS.
///
/// Astrologer listings are public BUSINESS profiles, so every signed-in user may
/// browse the directory. This reads the whole collection (`watchAllAstrologers`)
/// and the matching Firestore rule is `allow read: if isAuthenticated()` — the
/// two MUST stay in sync: a query that reads docs the rule forbids is rejected
/// wholesale with permission-denied (that was the old "Astrologer page" bug,
/// when the rule only allowed reading `approved` docs). Only suspended
/// astrologers (status == rejected) are excluded client-side; the card shows a
/// status badge so verified vs. pending stays identifiable.
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
