import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/location_model.dart';
import '../services/firebase/location_repository.dart';
import 'locale_provider.dart';

/// Tamil Nadu location data (Firestore-first with bundled-JSON fallback),
/// cached in memory for the session by [LocationRepository].
final locationRepositoryProvider =
    Provider<LocationRepository>((ref) => LocationRepository());

/// All 38 districts (each row carries both English and Tamil names).
final districtsProvider = FutureProvider<List<TnDistrict>>(
  (ref) => ref.watch(locationRepositoryProvider).getDistricts(),
);

/// Cities for a district id. One cache entry per district; returns [] for an
/// unknown id so dependent dropdowns can render empty before a pick.
final citiesProvider = FutureProvider.family<List<TnCity>, int>(
  (ref, districtId) => ref.watch(locationRepositoryProvider).getCities(districtId),
);

/// Flat, de-duplicated, sorted list of ALL city names in the viewer's
/// language — used by the searchable Birth Place picker. Re-computes when the
/// app language changes.
final allCityNamesProvider = FutureProvider<List<String>>((ref) async {
  final lang = ref.watch(localeProvider)?.languageCode ?? 'en';
  final cities = await ref.watch(locationRepositoryProvider).getAllCities();
  final names = {for (final c in cities) c.nameFor(lang)}.toList()..sort();
  return names;
});
