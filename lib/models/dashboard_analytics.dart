/// A single labelled point on a revenue trend chart (e.g. a day, week, month
/// or year bucket) with its total INR amount.
class RevenuePoint {
  final String label; // x-axis label, e.g. "Mon", "W1", "Jan", "2026"
  final int amount; // total INR in this bucket
  const RevenuePoint(this.label, this.amount);
}

/// A compact row for "top / most-consulted astrologer" leaderboards.
class AstrologerStatRow {
  final String name;
  final double rating;
  final int reviewCount;
  final int consultations;
  const AstrologerStatRow({
    required this.name,
    this.rating = 0,
    this.reviewCount = 0,
    this.consultations = 0,
  });
}

/// Everything the Admin business dashboard needs, computed in one pass over
/// Firestore. Every field defaults to zero / empty so a partial failure in one
/// section never blanks the whole dashboard.
class DashboardAnalytics {
  // ── Overview ───────────────────────────────────────────────────────────────
  final int totalUsers;
  final int totalAstrologers;
  final int totalMatches;
  final int totalMessages;
  final int premiumSubscribers;
  final int marriedUsers;

  // ── Revenue ──────────────────────────────────────────────────────────────
  final int revenueToday;
  final int revenueWeek;
  final int revenueMonth;
  final int revenueYear;
  final int revenueTotal;
  final List<RevenuePoint> revenueDaily; // last 7 days
  final List<RevenuePoint> revenueWeekly; // last ~6 weeks
  final List<RevenuePoint> revenueMonthly; // last 6 months
  final List<RevenuePoint> revenueYearly; // last 4 years

  // ── Subscriptions ──────────────────────────────────────────────────────────
  final int monthlySubscribers;
  final int yearlySubscribers;
  final int activePremium;
  final int expiredPremium;
  final int cancelledSubscriptions;

  // ── Users ──────────────────────────────────────────────────────────────────
  final int newUsersToday;
  final int newUsersWeek;
  final int newUsersMonth;
  final int dailyActiveUsers;
  final int monthlyActiveUsers;

  // ── Astrologers ──────────────────────────────────────────────────────────
  final int pendingAstrologers;
  final int verifiedAstrologers;
  final List<AstrologerStatRow> topRatedAstrologers;
  final List<AstrologerStatRow> mostConsultedAstrologers;

  // ── Consultations ──────────────────────────────────────────────────────────
  final int consultationsToday;
  final int consultationsWeek;
  final int consultationsMonth;
  final int consultationsCompleted;
  final int consultationsCancelled;

  // ── Marriage success ───────────────────────────────────────────────────────
  final int successfulMatches;
  final double marriageSuccessRate; // percentage 0-100

  const DashboardAnalytics({
    this.totalUsers = 0,
    this.totalAstrologers = 0,
    this.totalMatches = 0,
    this.totalMessages = 0,
    this.premiumSubscribers = 0,
    this.marriedUsers = 0,
    this.revenueToday = 0,
    this.revenueWeek = 0,
    this.revenueMonth = 0,
    this.revenueYear = 0,
    this.revenueTotal = 0,
    this.revenueDaily = const [],
    this.revenueWeekly = const [],
    this.revenueMonthly = const [],
    this.revenueYearly = const [],
    this.monthlySubscribers = 0,
    this.yearlySubscribers = 0,
    this.activePremium = 0,
    this.expiredPremium = 0,
    this.cancelledSubscriptions = 0,
    this.newUsersToday = 0,
    this.newUsersWeek = 0,
    this.newUsersMonth = 0,
    this.dailyActiveUsers = 0,
    this.monthlyActiveUsers = 0,
    this.pendingAstrologers = 0,
    this.verifiedAstrologers = 0,
    this.topRatedAstrologers = const [],
    this.mostConsultedAstrologers = const [],
    this.consultationsToday = 0,
    this.consultationsWeek = 0,
    this.consultationsMonth = 0,
    this.consultationsCompleted = 0,
    this.consultationsCancelled = 0,
    this.successfulMatches = 0,
    this.marriageSuccessRate = 0,
  });
}
