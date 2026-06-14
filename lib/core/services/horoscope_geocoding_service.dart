import 'package:geocoding/geocoding.dart';

/// Geocoded coordinates for a birth place.
class GeoPoint {
  final double latitude;
  final double longitude;
  const GeoPoint(this.latitude, this.longitude);
}

/// Thrown when a birth place cannot be resolved to coordinates.
class GeocodingFailure implements Exception {
  final String message;
  const GeocodingFailure(this.message);
  @override
  String toString() => message;
}

/// Forward geocoding (place name → lat/long) for horoscope calculation, using
/// the platform `geocoding` plugin already bundled with the app.
class HoroscopeGeocodingService {
  /// Resolves [place] to coordinates. Throws [GeocodingFailure] when the place
  /// is empty, not found, or the geocoder is unavailable.
  Future<GeoPoint> resolve(String place) async {
    final query = place.trim();
    if (query.isEmpty) {
      throw const GeocodingFailure('Birth place is empty.');
    }
    try {
      final results = await locationFromAddress(query);
      if (results.isEmpty) {
        throw const GeocodingFailure('Birth place could not be located.');
      }
      final first = results.first;
      return GeoPoint(first.latitude, first.longitude);
    } on GeocodingFailure {
      rethrow;
    } catch (e) {
      // NoResultFoundException / platform errors → uniform failure.
      throw const GeocodingFailure('Birth place could not be located.');
    }
  }
}
