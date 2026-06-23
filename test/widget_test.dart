// Unit tests for the subscription entitlements layer (pure Dart — no Firebase).
//
// Replaces the default Flutter counter-app boilerplate, which referenced a
// non-existent `MyApp` and never matched this project.

import 'package:flutter_test/flutter_test.dart';
import 'package:jothida_matrimony/core/config/plan_features.dart';

void main() {
  group('PlanFeatures.planFromString', () {
    test('maps known plans, treats legacy "medium" as Basic', () {
      expect(PlanFeatures.planFromString('premium'), AppPlan.premium);
      expect(PlanFeatures.planFromString('basic'), AppPlan.basic);
      expect(PlanFeatures.planFromString('medium'), AppPlan.basic);
      expect(PlanFeatures.planFromString('free'), AppPlan.free);
      expect(PlanFeatures.planFromString(''), AppPlan.free);
      expect(PlanFeatures.planFromString(null), AppPlan.free);
      expect(PlanFeatures.planFromString('PREMIUM'), AppPlan.premium);
    });
  });

  group('PlanFeatures entitlements', () {
    test('Free plan is limited to 2 interests/day with features locked', () {
      const f = PlanFeatures.free;
      expect(f.interestsPerDay, 2);
      expect(f.hasUnlimitedInterests, isFalse);
      expect(f.canViewContact, isFalse);
      expect(f.canBookAstrologer, isFalse);
      expect(f.canUseHoroscopeMatchFilter, isFalse);
    });

    test('Basic unlocks interests/contact/booking but not advanced filters', () {
      const b = PlanFeatures.basic;
      expect(b.hasUnlimitedInterests, isTrue);
      expect(b.canViewContact, isTrue);
      expect(b.canBookAstrologer, isTrue);
      expect(b.advancedFilters, isFalse);
    });

    test('Premium unlocks everything', () {
      const p = PlanFeatures.premium;
      expect(p.advancedFilters, isTrue);
      expect(p.featuredBadge, isTrue);
      expect(p.profileAnalytics, isTrue);
      expect(p.visibilityBoost, greaterThan(PlanFeatures.basic.visibilityBoost));
    });
  });
}
