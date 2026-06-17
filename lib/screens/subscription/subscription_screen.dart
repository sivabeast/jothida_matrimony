import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/dev_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/subscription_model.dart';
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
            if (kSubscriptionTestMode) ...[
              const _TestModeBadge(),
              const SizedBox(height: 16),
            ],
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

/// "🧪 TEST MODE" banner shown while payment is bypassed.
class _TestModeBadge extends StatelessWidget {
  const _TestModeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Text('🧪', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TEST MODE',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.warning.withOpacity(0.95))),
                const SizedBox(height: 2),
                Text('Payment is bypassed — plans activate instantly.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              ],
            ),
          ),
        ],
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

  static int _rank(String p) => switch (p) {
        AppConstants.planPremium => 3,
        AppConstants.planMedium => 2,
        _ => 1,
      };

  static String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(authNotifierProvider);
    final user = userAsync.valueOrNull;
    final subNotifier = ref.read(subscriptionNotifierProvider.notifier);
    final color = isPremium ? AppColors.gold : isPopular ? AppColors.primary : Colors.grey[700]!;

    // Authoritative active subscription (index-free fetch). Drives the
    // Current-Plan badge and Upgrade/Switch button labels.
    final activeSub = ref.watch(activeSubscriptionProvider).valueOrNull;
    final hasActive = activeSub != null && !activeSub.isExpired;
    final isCurrent = hasActive && activeSub.plan == plan;
    final switchLabel =
        hasActive && _rank(plan) > _rank(activeSub.plan) ? 'Upgrade Plan' : 'Switch Plan';

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
                if (isCurrent)
                  _currentPlanStatus(activeSub)
                else
                  GradientButton(
                    onPressed: user == null
                        ? null
                        : () async {
                            if (kSubscriptionTestMode) {
                              await subNotifier.activatePlan(
                                plan: plan,
                                userId: user.uid,
                                type: 'monthly',
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(
                                        '${plan[0].toUpperCase()}${plan.substring(1)} plan activated (test mode).')));
                              }
                            } else {
                              subNotifier.purchase(
                                plan: plan,
                                userId: user.uid,
                                userPhone: user.phone ?? '',
                                userEmail: user.email ?? '',
                                userName: user.displayName ?? 'User',
                              );
                            }
                          },
                    text: hasActive
                        ? switchLabel
                        : (kSubscriptionTestMode ? 'Activate Plan' : 'Subscribe'),
                    gradient: isPremium
                        ? AppColors.goldGradient
                        : AppColors.primaryGradient,
                  ),
              ],
            ),
          ),
        ),
        if (isCurrent)
          Positioned(
            top: 0,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: const BoxDecoration(
                color: AppColors.success,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 13),
                  SizedBox(width: 4),
                  Text('CURRENT PLAN',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          )
        else if (isPopular)
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

  /// Active-plan status block (replaces the action button on the current plan):
  /// ✅ Active · expiry date · days remaining, with a disabled "Current Plan".
  Widget _currentPlanStatus(SubscriptionModel sub) {
    final days = sub.daysRemaining < 0 ? 0 : sub.daysRemaining;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.success.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.check_circle, color: AppColors.success, size: 18),
                  SizedBox(width: 6),
                  Text('ACTIVE',
                      style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              _statusRow('Expires', _fmtDate(sub.endDate)),
              const SizedBox(height: 3),
              _statusRow('Remaining', '$days days'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: null,
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: AppColors.success.withOpacity(0.5),
              disabledForegroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Current Plan'),
          ),
        ),
      ],
    );
  }

  Widget _statusRow(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      );
}
