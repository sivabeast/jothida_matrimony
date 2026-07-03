import '../constants/app_constants.dart';

/// The three subscription tiers offered in the app.
enum AppPlan { free, basic, premium }

/// What a given [AppPlan] is allowed to do. This is the single source of truth
/// for per-feature access control across the UI — gate features off this rather
/// than re-deriving from membership strings.
///
/// FREE-FEATURES POLICY: every core MATRIMONY feature is free for everyone —
/// browsing/searching profiles, all filters, match suggestions, unlimited
/// interests (send/accept/reject), chat, and contact/WhatsApp details. The ONLY
/// paid services in the app are the ASTROLOGY ones (Horoscope Report/Analysis
/// and astrologer appointment booking), and those are paid PER SERVICE via
/// Razorpay at booking time — never through a subscription gate. Paid plans now
/// only add cosmetic/visibility perks:
///  • Basic   — better visibility.
///  • Premium — featured badge, top search placement, priority recommendations,
///              profile analytics, highest visibility and priority support.
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

  // All matrimony features are free for everyone (see class doc). Only the
  // astrology services carry a per-service charge, handled at booking time.
  static const free = PlanFeatures(
    plan: AppPlan.free,
    interestsPerDay: -1, // unlimited — sending interest is free
    canViewContact: true,
    canViewWhatsapp: true,
    canUseHoroscopeMatchFilter: true,
    canBookAstrologer: true, // booking itself is paid per appointment
    canSeeWhoViewedMe: true,
    featuredBadge: false,
    topSearchPlacement: false,
    priorityRecommendations: false,
    advancedFilters: true,
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
    advancedFilters: true,
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
