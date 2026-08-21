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
/// language. Kept for the places that only ever needed a name (matching /
/// filters); FORMS should use [allPlaceOptionsProvider] instead so the place
/// is identified by City + District + State.
final allCityNamesProvider = FutureProvider<List<String>>((ref) async {
  final lang = ref.watch(localeProvider)?.languageCode ?? 'en';
  final cities = await ref.watch(locationRepositoryProvider).getAllCities();
  final names = {for (final c in cities) c.nameFor(lang)}.toList()..sort();
  return names;
});

/// Every city joined to its district — the source for the app's ONE
/// hierarchical place picker (spec §27–§32).
///
/// Cities are NOT de-duplicated by name here: two villages that share a name
/// in different districts are exactly what the picker has to tell apart, so
/// both rows must survive. Sorted by city name, then district, so the search
/// results read alphabetically.
final allPlaceOptionsProvider = FutureProvider<List<PlaceOption>>((ref) async {
  final repo = ref.watch(locationRepositoryProvider);
  final cities = await repo.getAllCities();
  final districts = await repo.getDistricts();
  final byId = {for (final d in districts) d.id: d};
  final out = <PlaceOption>[
    for (final c in cities)
      if (byId[c.districtId] != null)
        PlaceOption(city: c, district: byId[c.districtId]!),
  ]..sort((a, b) {
      final byCity = a.city.nameEn.compareTo(b.city.nameEn);
      return byCity != 0 ? byCity : a.district.nameEn.compareTo(b.district.nameEn);
    });
  return out;
});
