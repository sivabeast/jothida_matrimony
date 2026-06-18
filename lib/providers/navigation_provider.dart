import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selected tab index for the main Home shell:
/// 0 Home · 1 Matches · 2 Astrologer · 3 Interests · 4 Profile.
///
/// Exposed as a provider (rather than local `setState`) so other screens can
/// switch tabs programmatically — e.g. the Home dashboard's "View All" buttons
/// jump to the Matches tab.
final homeTabIndexProvider = StateProvider<int>((ref) => 0);
