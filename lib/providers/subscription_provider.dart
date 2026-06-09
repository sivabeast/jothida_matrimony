import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../models/subscription_model.dart';
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
            endDate: DateTime.now().add(const Duration(days: 30)),
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
}

final subscriptionNotifierProvider =
    NotifierProvider<SubscriptionNotifier, AsyncValue<SubscriptionModel?>>(
        () => SubscriptionNotifier());
