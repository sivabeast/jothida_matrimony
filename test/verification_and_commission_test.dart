// Pure-Dart rules for the two systems this change introduced:
//
//  • PROFILE VERIFICATION — the existing approval queue renamed. The stored
//    status value is still 'approved' (Firestore rules / indexes / Cloud
//    Functions key off it), but every human-facing label reads "Verified".
//  • EMPLOYEE COMMISSION — credited per COMPLETED horoscope request, at the
//    rate frozen on that request, never recalculated by a later rate change.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/constants/app_constants.dart';
import 'package:jothida_matrimony/core/theme/app_colors.dart';
import 'package:jothida_matrimony/core/utils/profile_status.dart';
import 'package:jothida_matrimony/models/astrologer_request_model.dart';
import 'package:jothida_matrimony/models/astrologer_team_member.dart';
import 'package:jothida_matrimony/models/astrology_service_config.dart';
import 'package:jothida_matrimony/models/banner_model.dart';
import 'package:jothida_matrimony/providers/astrology_team_stats_provider.dart';
import 'package:jothida_matrimony/widgets/profile/verification_tick.dart';

AstrologerRequestModel _req({
  required String id,
  required String email,
  required AstrologerRequestStatus status,
  DateTime? completedAt,
  int commissionAmount = 0,
  DateTime? commissionCreditedAt,
}) =>
    AstrologerRequestModel(
      id: id,
      astrologerId: 'employee-uid',
      astrologerEmail: email,
      userId: 'user-1',
      userName: 'Test User',
      type: AstrologerRequestType.matching,
      status: status,
      createdAt: DateTime(2026, 8, 1),
      completedAt: completedAt,
      commissionAmount: commissionAmount,
      commissionCreditedAt: commissionCreditedAt,
    );

void main() {
  group('profile verification labels', () {
    test("the stored 'approved' status reads as Verified", () {
      expect(profileStatusLabel(AppConstants.profileApproved), 'Verified');
      expect(profileStatusLabel('APPROVED'), 'Verified');
    });

    test("'pending' reads as Pending Verification", () {
      expect(profileStatusLabel(AppConstants.profilePending),
          'Pending Verification');
      // A profile document with no status at all is still awaiting review.
      expect(profileStatusLabel(''), 'Pending Verification');
      expect(profileStatusLabel(null), 'Pending Verification');
    });

    test('rejected and blocked keep their own labels', () {
      expect(profileStatusLabel('rejected'), 'Rejected');
      expect(profileStatusLabel('blocked'), 'Blocked');
    });

    test('no label ever says "Approved"', () {
      for (final s in ['approved', 'pending', 'rejected', 'blocked', '']) {
        expect(profileStatusLabel(s).toLowerCase(), isNot(contains('approve')));
      }
    });

    test('verified is green, everything else is not', () {
      expect(profileStatusColor(AppConstants.profileApproved),
          AppColors.success);
      expect(profileStatusColor(AppConstants.profilePending),
          isNot(AppColors.success));
    });
  });

  group('verification tick', () {
    testWidgets('is GREEN for a verified profile', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: VerificationTick(verified: true))));
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, AppColors.success);
      expect(icon.icon, Icons.verified);
    });

    testWidgets('is DARK and inactive for an unverified profile',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: VerificationTick(verified: false))));
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, VerificationTick.unverifiedColor);
      // Same tick shape, visibly disabled.
      expect(icon.icon, Icons.verified);
      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, lessThan(1));
    });
  });

  group('home banners', () {
    test('a banner without artwork is never displayable', () {
      final blank =
          HomeBannerModel(id: 'a', createdAt: DateTime(2026, 8, 1));
      expect(blank.hasImage, isFalse);

      final real = HomeBannerModel(
          id: 'b',
          imageUrl: 'https://example.com/banner.png',
          createdAt: DateTime(2026, 8, 1));
      expect(real.hasImage, isTrue);
    });

    test('only the image and the admin label are persisted', () {
      final banner = HomeBannerModel(
        id: 'b',
        imageUrl: 'https://example.com/banner.png',
        title: 'Diwali Offer',
        createdAt: DateTime(2026, 8, 1),
      );
      // No template / text / colour / button fields survive: the uploaded
      // artwork is shown exactly as-is.
      expect(banner.toFirestore().keys,
          containsAll(<String>['imageUrl', 'title', 'enabled', 'order']));
      expect(banner.toFirestore().keys.any((k) => k.startsWith('template')),
          isFalse);
      expect(banner.toFirestore().containsKey('subtitle'), isFalse);
      expect(banner.toFirestore().containsKey('textColor'), isFalse);
    });
  });

  group('employee commission', () {
    const member = AstrologerTeamMember(id: 'a@x.com', email: 'a@x.com');
    const cfg = AstrologyServiceConfig(analysisCommission: 100);

    test('only COMPLETED requests earn commission', () {
      final stats = computeAstrologerStats(member, [
        _req(
            id: '1',
            email: 'a@x.com',
            status: AstrologerRequestStatus.pending),
        _req(
            id: '2',
            email: 'a@x.com',
            status: AstrologerRequestStatus.accepted),
      ], cfg);
      expect(stats.totalAssigned, 2);
      expect(stats.completed, 0);
      expect(stats.totalCommission, 0);
    });

    test('each completed request earns its own stamped amount', () {
      final now = DateTime.now();
      final stats = computeAstrologerStats(member, [
        for (var i = 0; i < 5; i++)
          _req(
            id: '$i',
            email: 'a@x.com',
            status: AstrologerRequestStatus.completed,
            completedAt: now,
            commissionAmount: 100,
            commissionCreditedAt: now,
          ),
      ], cfg);
      expect(stats.completed, 5);
      expect(stats.totalCommission, 500);
    });

    test('changing the configured rate never rewrites past completions', () {
      final now = DateTime.now();
      final completed = [
        _req(
          id: '1',
          email: 'a@x.com',
          status: AstrologerRequestStatus.completed,
          completedAt: now,
          commissionAmount: 100,
          commissionCreditedAt: now,
        ),
      ];
      // Admin doubles the rate afterwards.
      const raised = AstrologyServiceConfig(analysisCommission: 200);
      final stats = computeAstrologerStats(member, completed, raised);
      expect(stats.totalCommission, 100,
          reason: 'a historical completion must keep the rate it earned');
      expect(stats.commissionPerReport, 200,
          reason: 'the NEXT completion uses the new rate');
    });

    test('a legacy completion with no stamp falls back to the current rate',
        () {
      final now = DateTime.now();
      final stats = computeAstrologerStats(member, [
        _req(
          id: '1',
          email: 'a@x.com',
          status: AstrologerRequestStatus.completed,
          completedAt: now,
        ),
      ], cfg);
      expect(stats.totalCommission, 100);
    });

    test('another employee\'s requests never count', () {
      final now = DateTime.now();
      final stats = computeAstrologerStats(member, [
        _req(
          id: '1',
          email: 'someone-else@x.com',
          status: AstrologerRequestStatus.completed,
          completedAt: now,
          commissionAmount: 100,
          commissionCreditedAt: now,
        ),
      ], cfg);
      expect(stats.totalAssigned, 0);
      expect(stats.totalCommission, 0);
    });
  });
}
