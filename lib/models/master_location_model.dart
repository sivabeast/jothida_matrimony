// Master location data, sourced from the bundled JSON assets
// `assets/master_data/location/master_states.json`,
// `master_districts.json` and `master_cities.json` (no Firestore dependency).
//
// Hierarchy (parent referenced by the parent's id):
//   master_states    { id, name, country }
//   master_districts { id, name, stateId, stateName }
//   master_cities    { id, name, districtId, districtName, stateId, stateName }
//
// Each model keeps the `id` (used to load children and persisted on the
// profile) and the `name` (shown in the dropdown and persisted as the
// human-readable value).

class MasterState {
  final String id;
  final String name;
  final String country;

  const MasterState({
    required this.id,
    required this.name,
    this.country = 'India',
  });

  factory MasterState.fromJson(Map<String, dynamic> j) => MasterState(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        country: (j['country'] ?? 'India').toString(),
      );

  @override
  bool operator ==(Object other) => other is MasterState && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class MasterDistrict {
  final String id;
  final String name;
  final String stateId;
  final String stateName;

  const MasterDistrict({
    required this.id,
    required this.name,
    required this.stateId,
    this.stateName = '',
  });

  factory MasterDistrict.fromJson(Map<String, dynamic> j) => MasterDistrict(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        stateId: (j['stateId'] ?? '').toString(),
        stateName: (j['stateName'] ?? '').toString(),
      );

  @override
  bool operator ==(Object other) => other is MasterDistrict && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class MasterCity {
  final String id;
  final String name;
  final String districtId;
  final String districtName;
  final String stateId;
  final String stateName;

  const MasterCity({
    required this.id,
    required this.name,
    required this.districtId,
    this.districtName = '',
    this.stateId = '',
    this.stateName = '',
  });

  factory MasterCity.fromJson(Map<String, dynamic> j) => MasterCity(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        districtId: (j['districtId'] ?? '').toString(),
        districtName: (j['districtName'] ?? '').toString(),
        stateId: (j['stateId'] ?? '').toString(),
        stateName: (j['stateName'] ?? '').toString(),
      );

  @override
  bool operator ==(Object other) => other is MasterCity && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The full location a form collects. Names are shown/stored for readability;
/// the `*Id` fields are the stable master-data ids persisted on the profile.
/// [latitude] / [longitude] are filled when "Use My Location" is used.
class LocationSelection {
  final String country;
  final String state;
  final String stateId;
  final String district;
  final String districtId;
  final String city;
  final String cityId;
  final double? latitude;
  final double? longitude;

  const LocationSelection({
    this.country = 'India',
    this.state = '',
    this.stateId = '',
    this.district = '',
    this.districtId = '',
    this.city = '',
    this.cityId = '',
    this.latitude,
    this.longitude,
  });

  bool get hasState => state.trim().isNotEmpty;
  bool get hasCity => city.trim().isNotEmpty;

  /// "Chennai, Tamil Nadu" style summary (city + state).
  String get display =>
      [city, state].where((s) => s.trim().isNotEmpty).join(', ');

  LocationSelection copyWith({
    String? country,
    String? state,
    String? stateId,
    String? district,
    String? districtId,
    String? city,
    String? cityId,
    double? latitude,
    double? longitude,
  }) =>
      LocationSelection(
        country: country ?? this.country,
        state: state ?? this.state,
        stateId: stateId ?? this.stateId,
        district: district ?? this.district,
        districtId: districtId ?? this.districtId,
        city: city ?? this.city,
        cityId: cityId ?? this.cityId,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
      );
}
