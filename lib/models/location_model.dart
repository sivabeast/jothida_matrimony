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

/// One searchable place in the hierarchical place picker: a city/village row
/// joined to the district it belongs to (spec §27/§32).
///
/// A city name alone is ambiguous — the same village name occurs in several
/// districts — so the picker always identifies a place by **City/Village +
/// District + State** and stores all three separately.
class PlaceOption {
  final TnCity city;
  final TnDistrict district;

  const PlaceOption({required this.city, required this.district});

  String cityName(String lang) => city.nameFor(lang);
  String districtName(String lang) => district.nameFor(lang);

  /// "District, Tamil Nadu" — the disambiguating subtitle under the city name.
  String subtitle(String lang) =>
      '${district.nameFor(lang)}, ${TnState.nameFor(lang)}';

  PlaceSelection toSelection(String lang) => PlaceSelection(
        city: city.nameFor(lang),
        cityEn: city.nameEn,
        cityId: city.id,
        district: district.nameFor(lang),
        districtEn: district.nameEn,
        districtId: district.id,
        state: TnState.nameFor(lang),
      );
}

/// A place chosen in the picker. Carries the three levels separately so a
/// duplicate city name in another district is never confused with this one.
///
/// A [custom] selection is a free-typed place that is not in the master data
/// (e.g. a small village). It exists ONLY inside the form that created it —
/// the picker never writes anything back to the master `location` datasets or
/// to another member's data (spec §30).
class PlaceSelection {
  final String city;

  /// Canonical English city name, for language-independent storage/matching.
  final String cityEn;
  final int? cityId;
  final String district;
  final String districtEn;
  final int? districtId;
  final String state;
  final bool custom;

  const PlaceSelection({
    required this.city,
    this.cityEn = '',
    this.cityId,
    this.district = '',
    this.districtEn = '',
    this.districtId,
    this.state = TnState.nameEn,
    this.custom = false,
  });

  /// A place the member typed themselves — only the name is known.
  const PlaceSelection.custom(this.city)
      : cityEn = '',
        cityId = null,
        district = '',
        districtEn = '',
        districtId = null,
        state = '',
        custom = true;

  /// "Athikkolam, Ramanathapuram, Tamil Nadu" — what the field displays and
  /// what is stored as the place value.
  String get display => [city, district, state]
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .join(', ');

  bool get isEmpty => city.trim().isEmpty;
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
