import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/location_search.dart';
import '../core/utils/place_additions.dart';
import '../models/location_model.dart';
import '../services/firebase/location_repository.dart';
import '../services/firebase/place_additions_service.dart';
import 'auth_provider.dart';
import 'locale_provider.dart';

/// Tamil Nadu location data (bundled JSON, with member-added places merged
/// in), cached in memory for the session by [LocationRepository].
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

/// Writes/reads the member-added places (`master_options/places`).
final placeAdditionsServiceProvider =
    Provider<PlaceAdditionsService>((ref) => PlaceAdditionsService());

/// Every member-added place, LIVE — a place any member adds reaches every
/// picker without a restart, and Firestore's offline cache keeps the list
/// available after reopening the app without a connection.
///
/// Re-subscribes when the session changes: the document is readable by any
/// visitor session, and a listener refused before the session existed never
/// retries on its own.
final placeAdditionsProvider = StreamProvider<List<PlaceAddition>>((ref) {
  try {
    ref.watch(firebaseAuthStreamProvider);
  } catch (_) {
    // No Firebase (widget tests) — the bundled list still works.
  }
  try {
    return ref.watch(placeAdditionsServiceProvider).watch();
  } catch (e) {
    debugPrint('[Locations] member-added places unavailable: $e');
    return Stream.value(const <PlaceAddition>[]);
  }
});

/// The shared place search index (town + district + nickname matching,
/// transliteration-tolerant, nearest-town fallback) — built from the bundled
/// location JSON plus the member-added places, and reused by every place
/// field.
final placeSearchIndexProvider = FutureProvider<PlaceSearchIndex>((ref) async {
  // Derived from [allPlaceOptionsProvider] (itself cached for the session), so
  // there is exactly one load of the location data behind every picker.
  final options = await ref.watch(allPlaceOptionsProvider.future);
  final additions =
      ref.watch(placeAdditionsProvider).valueOrNull ?? const <PlaceAddition>[];
  final repo = ref.watch(locationRepositoryProvider);
  final seen = <String>{};
  final others = [
    for (final a in [...additions, ...repo.additionsOutsideTamilNadu])
      if (!a.isTamilNadu && seen.add(a.key)) a,
  ];
  // Every district has towns (each has its head-quarters town), so the
  // districts joined into [options] are the complete parent list.
  return PlaceSearchIndex.fromOptions(options, others: others);
});

/// Every city joined to its district — the source for the app's ONE
/// hierarchical place picker (spec §27–§32). Member-added Tamil Nadu places
/// are included, each under the district it was added to.
///
/// Cities are NOT de-duplicated by name here: two villages that share a name
/// in different districts are exactly what the picker has to tell apart, so
/// both rows must survive. Sorted by city name, then district, so the search
/// results read alphabetically.
final allPlaceOptionsProvider = FutureProvider<List<PlaceOption>>((ref) async {
  final repo = ref.watch(locationRepositoryProvider);
  final additions = ref.watch(placeAdditionsProvider).valueOrNull;
  if (additions != null) repo.mergeAdditions(additions);
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
