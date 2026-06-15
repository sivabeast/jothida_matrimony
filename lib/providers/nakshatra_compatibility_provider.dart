import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/nakshatra_compatibility.dart';

/// The loaded Nakshatra compatibility dataset (cached for the session). Used to
/// decide whether to show the informational "Horoscope Match" badge — it never
/// filters profiles.
final nakshatraCompatibilityProvider =
    FutureProvider<NakshatraCompatibility>((ref) => NakshatraCompatibility.load());
