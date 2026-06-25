/// The astrologer subscription billing periods. Only TWO plans exist —
/// Monthly and Yearly. There are intentionally no Basic / Premium / Gold /
/// Silver / Platinum tiers.
enum AstrologerPlanTier { monthly, yearly }

/// An astrologer subscription plan with its launch-offer and regular price
/// (INR). A plan is defined purely by its billing period: Monthly (30 days) or
/// Yearly (365 days).
///
/// Launch offer:  Monthly ₹199 · Yearly ₹1999
/// Regular price: Monthly ₹299 · Yearly ₹2999
class AstrologerPlan {
  final AstrologerPlanTier tier;
  final String id; // stored in Firestore: 'monthly' | 'yearly'
  final String name;
  final String emoji;
  final int launchPrice;
  final int regularPrice;

  /// Length of the subscription term in days (30 for monthly, 365 for yearly).
  final int durationDays;
  final List<String> perks;

  const AstrologerPlan({
    required this.tier,
    required this.id,
    required this.name,
    required this.emoji,
    required this.launchPrice,
    required this.regularPrice,
    required this.durationDays,
    required this.perks,
  });

  static const AstrologerPlan monthly = AstrologerPlan(
    tier: AstrologerPlanTier.monthly,
    id: 'monthly',
    name: 'Monthly',
    emoji: '🗓️',
    launchPrice: 199,
    regularPrice: 299,
    durationDays: 30,
    perks: [
      'Listed in the astrologer directory',
      'Receive match-analysis & consultation requests',
      'Chat with users · standard support',
    ],
  );

  static const AstrologerPlan yearly = AstrologerPlan(
    tier: AstrologerPlanTier.yearly,
    id: 'yearly',
    name: 'Yearly',
    emoji: '📅',
    launchPrice: 1999,
    regularPrice: 2999,
    durationDays: 365,
    perks: [
      'Everything in Monthly',
      'Save vs paying month-to-month',
      'Priority placement & support',
    ],
  );

  /// The only two plans offered, in display order.
  static const List<AstrologerPlan> all = [monthly, yearly];

  /// Whether the launch offer is currently active. Flip to false (or wire to a
  /// remote flag / end date) once the launch window closes — the regular price
  /// then applies everywhere automatically.
  static const bool launchOfferActive = true;

  /// The price actually charged right now (launch price during the offer).
  int get currentPrice => launchOfferActive ? launchPrice : regularPrice;

  /// Short unit suffix for a price, e.g. "/mo" or "/yr".
  String get unit => tier == AstrologerPlanTier.yearly ? 'yr' : 'mo';

  /// Human billing period, e.g. "per month" / "per year".
  String get periodLabel =>
      tier == AstrologerPlanTier.yearly ? 'per year' : 'per month';

  /// Look up a plan by its stored id; null for empty/legacy values.
  static AstrologerPlan? byId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// "Monthly Plan" / "Yearly Plan" for a stored plan id; '' when unknown/legacy.
  static String labelFor(String? id) {
    final p = byId(id);
    return p == null ? '' : '${p.name} Plan';
  }

  /// Short badge text shown on the public profile/directory, e.g. "📅 Yearly".
  static String badgeFor(String? id) {
    final p = byId(id);
    return p == null ? '' : '${p.emoji} ${p.name}';
  }
}
