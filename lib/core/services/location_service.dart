import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// A successfully detected location.
class DetectedLocation {
  final String country;
  final String state;
  final String city;
  final double latitude;
  final double longitude;

  const DetectedLocation({
    required this.country,
    required this.state,
    required this.city,
    required this.latitude,
    required this.longitude,
  });

  /// "Chennai, Tamil Nadu" — for the under-the-button display.
  String get display =>
      [city, state].where((s) => s.trim().isNotEmpty).join(', ');
}

/// Raised on any detection failure, carrying a user-facing message. Callers
/// show [message] and fall back to manual selection — the app never crashes.
class LocationException implements Exception {
  final String message;
  const LocationException(this.message);
  @override
  String toString() => message;
}

/// GPS detection + reverse geocoding for "Use My Location".
///
/// Handles every failure mode gracefully (services off, permission denied,
/// timeout, geocoding failure) by throwing a [LocationException] with a clear,
/// non-technical message.
class LocationService {
  Future<DetectedLocation> detect() async {
    // 1) Location services on?
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
          'Location is turned off. Enable GPS or select your location manually.');
    }

    // 2) Permission (request if not yet decided).
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationException(
          'Location access denied. Please select your location manually.');
    }

    // 3) Current position (with a timeout so the UI never hangs).
    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      throw const LocationException(
          'Could not get your location. Please try again or select manually.');
    }

    // 4) Reverse geocode → country / state / city. If this fails we still
    // return the coordinates (the user can fill the names manually).
    String country = '';
    String state = '';
    String city = '';
    try {
      final placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        country = p.country ?? '';
        state = p.administrativeArea ?? '';
        city = (p.locality != null && p.locality!.trim().isNotEmpty)
            ? p.locality!
            : (p.subAdministrativeArea ?? '');
      }
    } catch (_) {
      // Geocoding unavailable — keep coordinates, leave names blank.
    }

    return DetectedLocation(
      country: country,
      state: state,
      city: city,
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}
