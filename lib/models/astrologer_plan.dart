/// The four astrologer subscription tiers.
enum AstrologerPlanTier { starter, basic, pro, elite }

/// An astrologer subscription plan with its launch-offer and regular monthly
/// price (INR). All plans are billed monthly (30 days).
///
/// Launch offer:  Starter ₹29 · Basic ₹49 · Pro ₹99 · Elite ₹149
/// Regular price: Starter ₹49 · Basic ₹99 · Pro ₹149 · Elite ₹249
class AstrologerPlan {
  final AstrologerPlanTier tier;
  final String id; // stored in Firestore: 'starter' | 'basic' | 'pro' | 'elite'
  final String name;
  final String emoji;
  final int launchPrice;
  final int regularPrice;
  final List<String> perks;

  const AstrologerPlan({
    required this.tier,
    required this.id,
    required this.name,
    required this.emoji,
    required this.launchPrice,
    required this.regularPrice,
    required this.perks,
  });

  static const AstrologerPlan starter = AstrologerPlan(
    tier: AstrologerPlanTier.starter,
    id: 'starter',
    name: 'Starter',
    emoji: '🌙',
    launchPrice: 29,
    regularPrice: 49,
    perks: [
      'Listed in the astrologer directory',
      'Receive match-analysis requests',
      'Standard support',
    ],
  );

  static const AstrologerPlan basic = AstrologerPlan(
    tier: AstrologerPlanTier.basic,
    id: 'basic',
    name: 'Basic',
    emoji: '⭐',
    launchPrice: 49,
    regularPrice: 99,
    perks: [
      'Everything in Starter',
      'Higher placement in search',
      'Unlimited analysis requests',
    ],
  );

  static const AstrologerPlan pro = AstrologerPlan(
    tier: AstrologerPlanTier.pro,
    id: 'pro',
    name: 'Pro',
    emoji: '🔱',
    launchPrice: 99,
    regularPrice: 149,
    perks: [
      'Everything in Basic',
      'Eligible for Top Rated section',
      'Pro subscription badge',
    ],
  );

  static const AstrologerPlan elite = AstrologerPlan(
    tier: AstrologerPlanTier.elite,
    id: 'elite',
    name: 'Elite',
    emoji: '👑',
    launchPrice: 149,
    regularPrice: 249,
    perks: [
      'Everything in Pro',
      'Homepage / nearby spotlight',
      'Elite badge + priority support',
    ],
  );

  static const List<AstrologerPlan> all = [starter, basic, pro, elite];

  /// Whether the launch offer is currently active. Flip to false (or wire to a
  /// remote flag / end date) once the launch window closes — the regular price
  /// then applies everywhere automatically.
  static const bool launchOfferActive = true;

  /// The price actually charged right now (launch price during the offer).
  int get currentPrice => launchOfferActive ? launchPrice : regularPrice;

  /// Look up a plan by its stored id; null for empty/legacy values.
  static AstrologerPlan? byId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// "Starter Plan" etc. for a stored plan id; '' when unknown/legacy.
  static String labelFor(String? id) {
    final p = byId(id);
    return p == null ? '' : '${p.name} Plan';
  }

  /// Short badge text shown on the public profile/directory, e.g. "🔱 Pro".
  static String badgeFor(String? id) {
    final p = byId(id);
    return p == null ? '' : '${p.emoji} ${p.name}';
  }
}
