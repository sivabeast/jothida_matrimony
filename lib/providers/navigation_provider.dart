import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selected tab index for the main Home shell:
/// 0 Home · 1 Matches · 2 Chats · 3 Interests · 4 Reports.
///
/// Exposed as a provider (rather than local `setState`) so other screens can
/// switch tabs programmatically — e.g. the Home dashboard's "View All" buttons
/// jump to the Matches tab.
final homeTabIndexProvider = StateProvider<int>((ref) => 0);

/// Centralised Home-shell tab indices so cross-screen "jump to tab" actions
/// stay correct if the order ever changes again.
const int kMatchesTabIndex = 1;
const int kChatsTabIndex = 2;
const int kInterestsTabIndex = 3;
const int kReportsTabIndex = 4;

/// A pair the user wants an astrologer to analyse, stashed when they tap
/// "Consult Astrologer" (from a horoscope-match result or a member's profile)
/// so the Astrologers list / booking flow can pre-fill the partner.
class ConsultMatchContext {
  /// The other member's USER id (UID) — the dependable key for booking.
  final String partnerUserId;
  final String partnerName;

  const ConsultMatchContext({
    required this.partnerUserId,
    required this.partnerName,
  });
}

/// Set when "Consult Astrologer" is tapped; read (and cleared) by the
/// Astrologers / booking flow. Null when no consultation is pending.
final consultMatchProvider = StateProvider<ConsultMatchContext?>((ref) => null);
