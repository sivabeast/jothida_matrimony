import 'package:flutter/material.dart' show TimeOfDay;

import 'astrology_engine.dart';
import 'horoscope_geocoding_service.dart';
import 'master_astrology_data.dart';

/// User-facing message shown for any calculation failure (per spec).
const String kHoroscopeCalcErrorMessage =
    'Unable to calculate horoscope details. Please verify date, time and birth place.';

/// India Standard Time offset. The app is India-focused, so birth times are
/// interpreted as IST (UTC+5:30) when converting to UT for the engine.
const Duration _istOffset = Duration(hours: 5, minutes: 30);

/// The validated, ready-to-store result of a horoscope calculation. Names are
/// the master-file Tamil values (so they are guaranteed to exist in the master
/// data and stay consistent with the rest of the app).
class HoroscopeCalcResult {
  final String rasi; // Tamil name from master_rasi.json
  final String nakshatra; // Tamil name from master_nakshatra.json
  final String lagnam; // Tamil name from master_lagnam.json
  final double latitude;
  final double longitude;

  const HoroscopeCalcResult({
    required this.rasi,
    required this.nakshatra,
    required this.lagnam,
    required this.latitude,
    required this.longitude,
  });
}

/// Thrown for ANY failure in the calculation pipeline. [message] is always the
/// single user-facing string above; [cause] carries the technical detail for
/// logging.
class HoroscopeCalculationException implements Exception {
  final String message;
  final Object? cause;
  const HoroscopeCalculationException([this.cause])
      : message = kHoroscopeCalcErrorMessage;
  @override
  String toString() => '$message (cause: $cause)';
}

/// Orchestrates the full pipeline:
///
/// ```
/// DOB + Time + Place
///   → geocode (lat/long)
///   → IST→UT
///   → Swiss Ephemeris (sidereal, Lahiri)
///   → validate against master Rasi/Nakshatra/Lagnam
///   → HoroscopeCalcResult
/// ```
///
/// Any failure surfaces as [HoroscopeCalculationException] with the standard
/// message.
class HoroscopeCalculationService {
  HoroscopeCalculationService({
    HoroscopeGeocodingService? geocoder,
  }) : _geocoder = geocoder ?? HoroscopeGeocodingService();

  final HoroscopeGeocodingService _geocoder;

  Future<HoroscopeCalcResult> calculate({
    required DateTime dateOfBirth, // date portion is used
    required TimeOfDay birthTime,
    required String birthPlace,
  }) async {
    try {
      // 1) Birth place → coordinates.
      final geo = await _geocoder.resolve(birthPlace);

      // 2) IST wall-clock → UT instant. Build the entered components AS a UTC
      // label (device-timezone independent), then subtract the IST offset to
      // get the true universal time.
      final istLabeledAsUtc = DateTime.utc(
        dateOfBirth.year,
        dateOfBirth.month,
        dateOfBirth.day,
        birthTime.hour,
        birthTime.minute,
      );
      final utc = istLabeledAsUtc.subtract(_istOffset);

      // 3) Swiss Ephemeris sidereal computation.
      final astro = await AstrologyEngine.compute(
        utcDateTime: utc,
        latitude: geo.latitude,
        longitude: geo.longitude,
      );

      // 4) Validate against master data — only accept values that exist there.
      final master = await MasterAstrologyData.load();
      final rasi = master.rasiByIndex(astro.rasiIndex);
      final nak = master.nakshatraByIndex(astro.nakshatraIndex);
      final lagnam = master.lagnamByIndex(astro.lagnamIndex);
      if (rasi == null || nak == null || lagnam == null) {
        throw const HoroscopeCalculationException(
            'Computed index outside master data range');
      }

      return HoroscopeCalcResult(
        rasi: rasi.nameTamil,
        nakshatra: nak.nameTamil,
        lagnam: lagnam.nameTamil,
        latitude: geo.latitude,
        longitude: geo.longitude,
      );
    } on HoroscopeCalculationException {
      rethrow;
    } catch (e) {
      throw HoroscopeCalculationException(e);
    }
  }

  /// Parses a stored birth-time string ("HH:mm" or "h:mm AM/PM") back into a
  /// [TimeOfDay] so the edit-profile flow can recalculate. Returns `null` when
  /// the string can't be parsed.
  static TimeOfDay? parseStoredTime(String value) {
    final s = value.trim();
    if (s.isEmpty) return null;
    final ampm = RegExp(r'^(\d{1,2}):(\d{2})\s*([AaPp][Mm])$').firstMatch(s);
    if (ampm != null) {
      var h = int.parse(ampm.group(1)!);
      final m = int.parse(ampm.group(2)!);
      final pm = ampm.group(3)!.toUpperCase() == 'PM';
      if (h == 12) h = 0;
      if (pm) h += 12;
      return TimeOfDay(hour: h % 24, minute: m);
    }
    final h24 = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
    if (h24 != null) {
      return TimeOfDay(
          hour: int.parse(h24.group(1)!) % 24,
          minute: int.parse(h24.group(2)!));
    }
    return null;
  }

  /// Formats a [TimeOfDay] to the canonical stored form "HH:mm".
  static String formatStoredTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
