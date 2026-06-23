import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../models/subscription_model.dart';
import '../core/config/plan_features.dart';
import '../core/constants/app_constants.dart';
import '../services/razorpay/razorpay_service.dart';
import 'service_providers.dart';
import 'auth_provider.dart';

final activeSubscriptionProvider =
    FutureProvider.autoDispose<SubscriptionModel?>((ref) async {
  final userId = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (userId == null) return null;
  return ref.watch(subscriptionRepositoryProvider).getActiveSubscription(userId);
});

/// The effective subscription tier (Free / Basic / Premium) for the signed-in
/// user. A live, non-expired subscription record is authoritative; otherwise we
/// fall back to the user document's membershipType while it's still active.
/// Reflects a test-mode activation instantly.
final currentPlanProvider = Provider.autoDispose<AppPlan>((ref) {
  final sub = ref.watch(activeSubscriptionProvider).valueOrNull;
  if (sub != null && sub.isActive && !sub.isExpired) {
    return PlanFeatures.planFromString(sub.plan);
  }
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user != null && user.membershipType != 'free') {
    // Honour an active expiry, or a plan grant with no expiry (legacy/admin).
    if (user.hasActiveSubscription || user.subscriptionExpiry == null) {
      return PlanFeatures.planFromString(user.membershipType);
    }
  }
  return AppPlan.free;
});

/// Per-feature entitlements for the signed-in user — gate UI features off this.
final planFeaturesProvider = Provider.autoDispose<PlanFeatures>(
    (ref) => PlanFeatures.forPlan(ref.watch(currentPlanProvider)));

/// Single source of truth for "does the signed-in user have a paid plan"
/// (Basic or Premium). Reflects a test-mode activation instantly.
final isPremiumProvider = Provider.autoDispose<bool>(
    (ref) => ref.watch(currentPlanProvider) != AppPlan.free);

class SubscriptionNotifier extends Notifier<AsyncValue<SubscriptionModel?>> {
  @override
  AsyncValue<SubscriptionModel?> build() => const AsyncData(null);

  Future<void> purchase({
    required String plan,
    required String userId,
    required String userPhone,
    required String userEmail,
    required String userName,
  }) async {
    final razorpay = ref.read(razorpayServiceProvider);
    razorpay.init(
      onSuccess: (PaymentSuccessResponse res) async {
        state = const AsyncLoading();
        state = await AsyncValue.guard(() async {
          final sub = SubscriptionModel(
            id: '${userId}_${DateTime.now().millisecondsSinceEpoch}',
            userId: userId,
            plan: plan,
            amountPaid: _planPrice(plan),
            razorpayPaymentId: res.paymentId ?? '',
            razorpayOrderId: res.orderId ?? '',
            startDate: DateTime.now(),
            endDate:
                DateTime.now().add(Duration(days: _planDurationDays(plan))),
            isActive: true,
            createdAt: DateTime.now(),
          );
          await ref.read(subscriptionRepositoryProvider).saveSubscription(sub);
          return sub;
        });
      },
      onFailure: (PaymentFailureResponse res) {
        state = AsyncError(res.message ?? 'Payment failed', StackTrace.current);
      },
    );

    razorpay.openSubscriptionCheckout(
      plan: plan,
      amountPaise: RazorpayService.planAmountPaise(plan),
      userId: userId,
      userPhone: userPhone,
      userEmail: userEmail,
      userName: userName,
    );
  }

  /// TEST MODE activation — no payment. Creates the subscription record and
  /// updates the user's premium status/expiry exactly as a real purchase would.
  /// [type] is 'monthly' (30 days) or 'yearly' (365 days).
  Future<void> activatePlan({
    required String plan,
    required String userId,
    String type = 'monthly',
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final now = DateTime.now();
      final end = now.add(
          Duration(days: type == 'yearly' ? 365 : _planDurationDays(plan)));
      final sub = SubscriptionModel(
        id: '${userId}_${now.millisecondsSinceEpoch}',
        userId: userId,
        plan: plan,
        amountPaid: 0, // bypassed in test mode
        razorpayPaymentId: 'test_mode',
        razorpayOrderId: 'test_mode',
        startDate: now,
        endDate: end,
        isActive: true,
        createdAt: now,
      );
      final repo = ref.read(subscriptionRepositoryProvider);
      await repo.saveSubscription(sub);
      // Reflect premium status on the user document so access checks pass now.
      await ref.read(firestoreServiceProvider).updateUserSubscription(
            userId,
            plan: plan,
            type: type,
            activatedAt: now,
            expiresAt: end,
          );
      // Refresh anything that reads subscription / premium state.
      ref.invalidate(activeSubscriptionProvider);
      ref.invalidate(currentUserProvider);
      return sub;
    });
  }

  int _planPrice(String plan) {
    switch (plan) {
      case AppConstants.planBasic:
        return AppConstants.basicPrice;
      case AppConstants.planMedium:
        return AppConstants.mediumPrice;
      case AppConstants.planPremium:
        return AppConstants.premiumPrice;
      default:
        return 0;
    }
  }

  /// Plan validity in days: Premium = 60, everything else (Basic) = 30.
  int _planDurationDays(String plan) => plan == AppConstants.planPremium
      ? AppConstants.premiumDurationDays
      : AppConstants.basicDurationDays;
}

final subscriptionNotifierProvider =
    NotifierProvider<SubscriptionNotifier, AsyncValue<SubscriptionModel?>>(
        () => SubscriptionNotifier());
