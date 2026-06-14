import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/master_location_model.dart';
import '../services/firebase/master_location_service.dart';

/// Master-location service (countries / states / districts / cities reader),
/// backed by bundled JSON assets and cached in memory for the session.
final masterLocationServiceProvider =
    Provider<MasterLocationService>((ref) => MasterLocationService());

/// Countries present in the master data (India first). Read from local JSON.
final countriesProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(masterLocationServiceProvider).getCountries(),
);

/// All states, alphabetically. Cached for the session; cheap to keep warm.
final statesProvider = FutureProvider<List<MasterState>>(
  (ref) => ref.watch(masterLocationServiceProvider).getStates(),
);

/// Districts for a given state id. Re-fetches only when [stateId] changes
/// (one cache entry per state). Returns [] for an empty id so the UI can render
/// an empty, disabled District field before a state is chosen.
final districtsProvider = FutureProvider.family<List<MasterDistrict>, String>(
  (ref, stateId) =>
      ref.watch(masterLocationServiceProvider).getDistricts(stateId),
);

/// Cities for a given district id. One cache entry per district.
final citiesProvider = FutureProvider.family<List<MasterCity>, String>(
  (ref, districtId) =>
      ref.watch(masterLocationServiceProvider).getCities(districtId),
);
