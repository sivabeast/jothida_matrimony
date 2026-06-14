import 'package:cloud_firestore/cloud_firestore.dart';

/// Master location data, sourced from the Firestore collections
/// `master_states`, `master_districts` and `master_cities`.
///
/// Hierarchy (parent referenced by the parent's DOCUMENT id):
///   master_states   { name }
///   master_districts{ name, stateId }     ← stateId = master_states doc id
///   master_cities   { name, districtId }  ← districtId = master_districts doc id
///
/// Each model keeps both the [id] (used to load children) and the [name] (shown
/// in the dropdown and stored on the user/astrologer profile).

class MasterState {
  final String id;
  final String name;

  const MasterState({required this.id, required this.name});

  factory MasterState.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return MasterState(id: doc.id, name: (d['name'] ?? '').toString());
  }

  @override
  bool operator ==(Object other) =>
      other is MasterState && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class MasterDistrict {
  final String id;
  final String name;
  final String stateId;

  const MasterDistrict({
    required this.id,
    required this.name,
    required this.stateId,
  });

  factory MasterDistrict.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return MasterDistrict(
      id: doc.id,
      name: (d['name'] ?? '').toString(),
      stateId: (d['stateId'] ?? '').toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MasterDistrict && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class MasterCity {
  final String id;
  final String name;
  final String districtId;

  const MasterCity({
    required this.id,
    required this.name,
    required this.districtId,
  });

  factory MasterCity.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return MasterCity(
      id: doc.id,
      name: (d['name'] ?? '').toString(),
      districtId: (d['districtId'] ?? '').toString(),
    );
  }

  @override
  bool operator ==(Object other) => other is MasterCity && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The full location a form collects — names are persisted on the profile,
/// [latitude] / [longitude] are stored alongside when "Use My Location" is used.
class LocationSelection {
  final String state;
  final String district;
  final String city;
  final double? latitude;
  final double? longitude;

  const LocationSelection({
    this.state = '',
    this.district = '',
    this.city = '',
    this.latitude,
    this.longitude,
  });

  bool get hasCity => city.trim().isNotEmpty;

  /// "📍 Chennai, Tamil Nadu" style summary (city + state).
  String get display =>
      [city, state].where((s) => s.trim().isNotEmpty).join(', ');

  LocationSelection copyWith({
    String? state,
    String? district,
    String? city,
    double? latitude,
    double? longitude,
  }) =>
      LocationSelection(
        state: state ?? this.state,
        district: district ?? this.district,
        city: city ?? this.city,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
      );
}
