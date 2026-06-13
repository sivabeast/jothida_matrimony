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
/// Demo mode → in-memory [sampleAstrologers]. Real mode → only admin-VERIFIED
/// (status == approved) astrologers, via the server-side `status == approved`
/// query. Pending and rejected accounts are NEVER shown to users (business
/// "only verified astrologers appear" rule), and this query also satisfies the
/// Firestore rule that limits astrologer reads to approved documents.
///
/// NOTE (Phase 2): active-subscription gating is layered on top of this — an
/// approved astrologer whose subscription has expired must also be hidden here.
final astrologersProvider = StreamProvider.autoDispose<List<Astrologer>>((ref) {
  if (kBypassAuth) return Stream.value(sampleAstrologers());
  return ref.watch(astrologerServiceProvider).watchApprovedAstrologers().map(
        (accounts) => accounts.map(astrologerFromAccount).toList(),
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
