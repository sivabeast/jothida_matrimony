// Tamil Nadu location master data.
//
// The app serves Tamil Nadu only: State is the fixed constant below, and the
// dataset is exactly four documents/files with matching ids —
//   districts_en / districts_ta : [{ id, name }]
//   cities_en    / cities_ta    : [{ id, districtId, name }]
// Firestore `master_data/{key}` is the source of truth; the same four JSON
// files are bundled under assets/master_data/location/ as the offline
// fallback. English and Tamil rows are joined by id into the models here, so
// the UI can display either language while profiles keep storing the
// canonical English name + stable numeric id.

/// The fixed state — the app supports Tamil Nadu only.
class TnState {
  static const String id = 'TN';
  static const String nameEn = 'Tamil Nadu';
  static const String nameTa = 'தமிழ்நாடு';

  static String nameFor(String lang) => lang == 'ta' ? nameTa : nameEn;
}

class TnDistrict {
  final int id;
  final String nameEn;
  final String nameTa;

  const TnDistrict({
    required this.id,
    required this.nameEn,
    required this.nameTa,
  });

  String nameFor(String lang) => lang == 'ta' ? nameTa : nameEn;

  @override
  bool operator ==(Object other) => other is TnDistrict && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class TnCity {
  final int id;
  final int districtId;
  final String nameEn;
  final String nameTa;

  const TnCity({
    required this.id,
    required this.districtId,
    required this.nameEn,
    required this.nameTa,
  });

  String nameFor(String lang) => lang == 'ta' ? nameTa : nameEn;

  @override
  bool operator ==(Object other) => other is TnCity && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The full location a form collects. Names are stored in canonical English
/// for readability and cross-language matching; the `*Id` fields are the
/// stable master-data ids persisted on the profile. [latitude] / [longitude]
/// are filled when "Use My Location" is used.
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
