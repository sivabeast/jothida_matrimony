import '../constants/app_constants.dart';

/// The three subscription tiers offered in the app.
enum AppPlan { free, basic, premium }

/// What a given [AppPlan] is allowed to do. This is the single source of truth
/// for per-feature access control across the UI — gate features off this rather
/// than re-deriving from membership strings.
///
/// Mirrors the product spec:
///  • Free    — browse + filters + astrologers LIST; 2 interests/day; contact &
///              WhatsApp hidden; astrologer booking, horoscope-match filter and
///              who-viewed-me disabled.
///  • Basic   — ₹299 / 30 days — unlimited interests, contact + WhatsApp,
///              horoscope-match filter, astrologer booking, who-viewed-me,
///              better visibility.
///  • Premium — ₹599 / 60 days — everything in Basic plus featured badge, top
///              search placement, priority recommendations, advanced filters
///              (height/occupation/income/marital/horoscope), profile analytics,
///              highest visibility and priority support.
class PlanFeatures {
  final AppPlan plan;

  /// Interests allowed per day; -1 means unlimited.
  final int interestsPerDay;
  final bool canViewContact;
  final bool canViewWhatsapp;
  final bool canUseHoroscopeMatchFilter;
  final bool canBookAstrologer;
  final bool canSeeWhoViewedMe;
  final bool featuredBadge;
  final bool topSearchPlacement;
  final bool priorityRecommendations;

  /// Advanced Matches filters: height, occupation, income, marital status and
  /// horoscope-based matching (Premium only).
  final bool advancedFilters;
  final bool profileAnalytics;
  final bool prioritySupport;

  /// Relative ranking boost applied to the user's own profile in others' feeds
  /// (1.0 = none).
  final double visibilityBoost;

  const PlanFeatures({
    required this.plan,
    required this.interestsPerDay,
    required this.canViewContact,
    required this.canViewWhatsapp,
    required this.canUseHoroscopeMatchFilter,
    required this.canBookAstrologer,
    required this.canSeeWhoViewedMe,
    required this.featuredBadge,
    required this.topSearchPlacement,
    required this.priorityRecommendations,
    required this.advancedFilters,
    required this.profileAnalytics,
    required this.prioritySupport,
    required this.visibilityBoost,
  });

  bool get isFree => plan == AppPlan.free;
  bool get isPremium => plan == AppPlan.premium;
  bool get hasUnlimitedInterests => interestsPerDay < 0;

  static const free = PlanFeatures(
    plan: AppPlan.free,
    interestsPerDay: AppConstants.freeInterestsPerDay, // 2/day
    canViewContact: false,
    canViewWhatsapp: false,
    canUseHoroscopeMatchFilter: false,
    canBookAstrologer: false,
    canSeeWhoViewedMe: false,
    featuredBadge: false,
    topSearchPlacement: false,
    priorityRecommendations: false,
    advancedFilters: false,
    profileAnalytics: false,
    prioritySupport: false,
    visibilityBoost: 1.0,
  );

  static const basic = PlanFeatures(
    plan: AppPlan.basic,
    interestsPerDay: -1, // unlimited
    canViewContact: true,
    canViewWhatsapp: true,
    canUseHoroscopeMatchFilter: true,
    canBookAstrologer: true,
    canSeeWhoViewedMe: true,
    featuredBadge: false,
    topSearchPlacement: false,
    priorityRecommendations: false,
    advancedFilters: false,
    profileAnalytics: false,
    prioritySupport: false,
    visibilityBoost: 1.3, // better visibility
  );

  static const premium = PlanFeatures(
    plan: AppPlan.premium,
    interestsPerDay: -1, // unlimited
    canViewContact: true,
    canViewWhatsapp: true,
    canUseHoroscopeMatchFilter: true,
    canBookAstrologer: true,
    canSeeWhoViewedMe: true,
    featuredBadge: true,
    topSearchPlacement: true,
    priorityRecommendations: true,
    advancedFilters: true,
    profileAnalytics: true,
    prioritySupport: true,
    visibilityBoost: 2.0, // highest visibility
  );

  static PlanFeatures forPlan(AppPlan plan) => switch (plan) {
        AppPlan.free => free,
        AppPlan.basic => basic,
        AppPlan.premium => premium,
      };

  /// Maps a stored `membershipType` / subscription plan string to an [AppPlan].
  /// Legacy `'medium'` is treated as Basic. Anything unrecognised → Free.
  static AppPlan planFromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case AppConstants.planPremium:
        return AppPlan.premium;
      case AppConstants.planBasic:
      case AppConstants.planMedium: // legacy mid-tier → Basic
        return AppPlan.basic;
      default:
        return AppPlan.free;
    }
  }
}
