import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../widgets/common/gradient_button.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(activeSubscriptionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription Plans'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Active sub banner
            subAsync.when(
              data: (sub) => sub != null
                  ? Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            'Active: ${sub.plan} plan • ${sub.daysRemaining} days left',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),
            Text('Choose Your Plan', style: AppTextStyles.heading1),
            const SizedBox(height: 8),
            Text('Unlock more features with a plan', style: AppTextStyles.bodyMedium),
            const SizedBox(height: 24),
            _PlanCard(
              plan: AppConstants.planBasic,
              price: AppConstants.basicPrice,
              features: const [
                'View 20 profiles/day',
                'Send 5 interests/day',
                'Basic search filters',
              ],
            ),
            const SizedBox(height: 16),
            _PlanCard(
              plan: AppConstants.planMedium,
              price: AppConstants.mediumPrice,
              isPopular: true,
              features: const [
                'View 50 profiles/day',
                'Send unlimited interests',
                'Advanced search filters',
                '1 Free Astrologer Consultation/month',
              ],
            ),
            const SizedBox(height: 16),
            _PlanCard(
              plan: AppConstants.planPremium,
              price: AppConstants.premiumPrice,
              isPremium: true,
              features: const [
                'Unlimited profile views',
                'Send unlimited interests',
                'All search filters',
                '3 Free Astrologer Consultations/month',
                'Priority support',
                'Profile highlighted',
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  final String plan;
  final int price;
  final List<String> features;
  final bool isPopular;
  final bool isPremium;

  const _PlanCard({
    required this.plan,
    required this.price,
    required this.features,
    this.isPopular = false,
    this.isPremium = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(authNotifierProvider);
    final user = userAsync.valueOrNull;
    final subNotifier = ref.read(subscriptionNotifierProvider.notifier);
    final color = isPremium ? AppColors.gold : isPopular ? AppColors.primary : Colors.grey[700]!;

    return Stack(
      children: [
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color.withOpacity(0.4), width: isPremium ? 2 : 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${plan[0].toUpperCase()}${plan.substring(1)}',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold, color: color),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '₹$price',
                            style: TextStyle(
                                fontSize: 26, fontWeight: FontWeight.bold, color: color),
                          ),
                          const TextSpan(
                            text: '/mo',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...features.map((f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, size: 18, color: color),
                          const SizedBox(width: 8),
                          Text(f),
                        ],
                      ),
                    )),
                const SizedBox(height: 20),
                GradientButton(
                  onPressed: user == null
                      ? null
                      : () => subNotifier.purchase(
                            plan: plan,
                            userId: user.uid,
                            userPhone: user.phone ?? '',
                            userEmail: user.email ?? '',
                            userName: user.displayName ?? 'User',
                          ),
                  text: 'Subscribe',
                  gradient: isPremium ? AppColors.goldGradient : AppColors.primaryGradient,
                ),
              ],
            ),
          ),
        ),
        if (isPopular)
          Positioned(
            top: 0,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
              child: const Text('POPULAR',
                  style: TextStyle(
                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}
