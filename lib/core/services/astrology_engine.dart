import 'package:sweph/sweph.dart';

/// Raw sidereal result from the Vedic engine. Indices are 0-based:
///  • [rasiIndex] / [lagnamIndex] : 0-11 (Mesham … Meenam)
///  • [nakshatraIndex]            : 0-26 (Ashwini … Revathi)
class AstroResult {
  final int rasiIndex;
  final int nakshatraIndex;
  final int lagnamIndex;
  final double moonLongitude; // sidereal, degrees
  final double ascendantLongitude; // sidereal, degrees
  const AstroResult({
    required this.rasiIndex,
    required this.nakshatraIndex,
    required this.lagnamIndex,
    required this.moonLongitude,
    required this.ascendantLongitude,
  });
}

/// Thrown when the underlying ephemeris computation fails.
class AstrologyEngineException implements Exception {
  final String message;
  const AstrologyEngineException(this.message);
  @override
  String toString() => 'AstrologyEngineException: $message';
}

/// Vedic (sidereal) astrology engine backed by the **Swiss Ephemeris**
/// (`sweph` package). It computes the **Moon** longitude (→ Rasi + Nakshatra)
/// and the **Ascendant** (→ Lagnam) using the **Lahiri** ayanamsa.
///
/// No hardcoded date→sign mappings and no static lookups are used — every
/// value is derived astronomically. The built-in **Moshier** ephemeris
/// (`SEFLG_MOSEPH`) is used so no ephemeris data files need to be shipped.
class AstrologyEngine {
  static const double _signSpan = 30.0; // degrees per rasi
  static const double _nakSpan = 360.0 / 27.0; // 13°20′ per nakshatra

  static bool _initialized = false;

  /// One-time native init. Safe to call repeatedly.
  static Future<void> _ensureInit() async {
    if (_initialized) return;
    // No ephemeris assets: Moshier mode needs no data files.
    await Sweph.init();
    _initialized = true;
  }

  /// Compute the sidereal chart for an instant in **UTC** at [latitude] /
  /// [longitude] (degrees, East/North positive).
  static Future<AstroResult> compute({
    required DateTime utcDateTime,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _ensureInit();
      final ut = utcDateTime.toUtc();
      final hour = ut.hour +
          ut.minute / 60.0 +
          ut.second / 3600.0 +
          ut.millisecond / 3600000.0;

      final jd = Sweph.swe_julday(
          ut.year, ut.month, ut.day, hour, CalendarType.SE_GREG_CAL);

      // Sidereal zodiac, Lahiri ayanamsa.
      Sweph.swe_set_sid_mode(
          SiderealMode.SE_SIDM_LAHIRI, SiderealModeFlag.SE_SIDBIT_NONE, 0);

      final flags = SwephFlag.SEFLG_MOSEPH |
          SwephFlag.SEFLG_SIDEREAL |
          SwephFlag.SEFLG_SPEED;

      // Moon → Rasi + Nakshatra.
      final moon = Sweph.swe_calc_ut(jd, HeavenlyBody.SE_MOON, flags);
      final moonLon = _norm360(moon.longitude);

      // Ascendant (Lagnam). Whole-sign houses; only the ascendant sign matters.
      final houses = Sweph.swe_houses_ex2(
          jd, SwephFlag.SEFLG_SIDEREAL, latitude, longitude, Hsys.W);
      final ascLon = _norm360(houses.ascmc[0]);

      return AstroResult(
        rasiIndex: (moonLon / _signSpan).floor() % 12,
        nakshatraIndex: (moonLon / _nakSpan).floor() % 27,
        lagnamIndex: (ascLon / _signSpan).floor() % 12,
        moonLongitude: moonLon,
        ascendantLongitude: ascLon,
      );
    } on AstrologyEngineException {
      rethrow;
    } catch (e) {
      throw AstrologyEngineException(e.toString());
    }
  }

  static double _norm360(double x) {
    var v = x % 360.0;
    if (v < 0) v += 360.0;
    return v;
  }
}
