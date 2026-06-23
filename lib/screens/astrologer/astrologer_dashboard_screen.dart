import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_account_model.dart';
import '../../providers/announcement_provider.dart';
import '../../providers/astrologer_session_provider.dart';
import '../../providers/notification_provider.dart';
import '../../widgets/common/app_logo.dart';
import 'tabs/astrologer_notifications_tab.dart';
import 'tabs/astrologer_overview_tab.dart';
import 'tabs/astrologer_profile_tab.dart';
import 'tabs/astrologer_reviews_tab.dart';

/// The astrologer portal — a focused marketplace experience with a 4-item
/// bottom navigation (Dashboard · Reviews · Notifications · Profile).
///
/// Astrologers manage their profile, reputation, certificates and subscription.
/// They never browse users, view user contacts, or manage appointments/leads —
/// users contact astrologers, not the other way around.
class AstrologerDashboardScreen extends ConsumerStatefulWidget {
  const AstrologerDashboardScreen({super.key});

  @override
  ConsumerState<AstrologerDashboardScreen> createState() =>
      _AstrologerDashboardScreenState();
}

class _AstrologerDashboardScreenState
    extends ConsumerState<AstrologerDashboardScreen> {
  int _index = 0;

  late final List<Widget> _tabs = <Widget>[
    AstrologerOverviewTab(onSelectTab: (i) => setState(() => _index = i)),
    const AstrologerReviewsTab(),
    const AstrologerNotificationsTab(),
    const AstrologerProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(myAstrologerAccountProvider);
    if (account == null) {
      return const Scaffold(
        body: Center(child: Text('Please complete onboarding')),
      );
    }

    final notifUnread = ref.watch(unreadNotificationCountProvider) +
        ref.watch(unreadAnnouncementsCountProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          titleSpacing: 12,
          // LEFT: app logo + brand name (only).
          title: Row(
            children: [
              const AppLogo(size: 36),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  'Jothida Matrimony',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 17,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          // RIGHT: quick availability toggle + notification icon.
          actions: [
            _availabilityToggle(account),
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => setState(() => _index = 2),
              icon: notifUnread > 0
                  ? Badge(
                      backgroundColor: AppColors.gold,
                      label: Text('$notifUnread',
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.primary)),
                      child: const Icon(Icons.notifications_none, size: 26),
                    )
                  : const Icon(Icons.notifications_none, size: 26),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: IndexedStack(index: _index, children: _tabs),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: Colors.white,
          indicatorColor: AppColors.primary.withOpacity(0.12),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard, color: AppColors.primary),
              label: 'Dashboard',
            ),
            const NavigationDestination(
              icon: Icon(Icons.star_outline),
              selectedIcon: Icon(Icons.star, color: AppColors.primary),
              label: 'Reviews',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: notifUnread > 0,
                label: Text('$notifUnread'),
                child: const Icon(Icons.notifications_none),
              ),
              selectedIcon:
                  const Icon(Icons.notifications, color: AppColors.primary),
              label: 'Notifications',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: AppColors.primary),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  /// Compact AppBar pill that mirrors and flips the manual availability switch.
  /// Colour = the *effective* status (green only when also a working day); the
  /// tap flips the manual switch and saves instantly.
  Widget _availabilityToggle(AstrologerAccount account) {
    final availableNow = account.isAvailableNow;
    final color = availableNow ? AppColors.success : AppColors.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _toggleAvailability(account),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  account.manuallyAvailable ? 'Available' : 'Unavailable',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleAvailability(AstrologerAccount account) async {
    try {
      await ref
          .read(myAstrologerAccountProvider.notifier)
          .setManualAvailability(!account.manuallyAvailable);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not update availability — please try again.'),
            backgroundColor: AppColors.error));
      }
    }
  }

  DateTime? _lastBackPress;

  void _handleBackPress() {
    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ));
      return;
    }
    SystemNavigator.pop();
  }
}
