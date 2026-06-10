import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/data/sample_astrologers.dart';
import '../models/astrologer_model.dart';

/// In-memory astrologer store (demo mode). Backed by [sampleAstrologers].
///
/// TODO(backend): replace with a Firestore-backed repository reading the
/// `astrologers` / `astrologer_services` collections.
final astrologersProvider = Provider<List<Astrologer>>((ref) => sampleAstrologers());

/// Top rated astrologers (rating desc).
final topRatedAstrologersProvider = Provider<List<Astrologer>>((ref) {
  final list = [...ref.watch(astrologersProvider)];
  list.sort((a, b) => b.rating.compareTo(a.rating));
  return list.take(6).toList();
});

/// Editorially recommended astrologers.
final recommendedAstrologersProvider = Provider<List<Astrologer>>((ref) =>
    ref.watch(astrologersProvider).where((a) => a.isRecommended).toList());

/// Recently active astrologers (most recent first).
final recentlyActiveAstrologersProvider = Provider<List<Astrologer>>((ref) {
  final list = [...ref.watch(astrologersProvider)];
  list.sort((a, b) => b.lastActive.compareTo(a.lastActive));
  return list.take(6).toList();
});

/// Look up a single astrologer by id.
final astrologerByIdProvider = Provider.family<Astrologer?, String>((ref, id) {
  for (final a in ref.watch(astrologersProvider)) {
    if (a.id == id) return a;
  }
  return null;
});
