import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_account_model.dart';
import '../../providers/announcement_provider.dart';
import '../../providers/astrologer_dashboard_provider.dart';
import '../../providers/astrologer_session_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/notification_provider.dart';
import '../../widgets/common/app_logo.dart';
import 'astrologer_requests_page.dart';
import 'tabs/astrologer_notifications_tab.dart';
import 'tabs/astrologer_overview_tab.dart';
import 'tabs/astrologer_profile_tab.dart';

/// The astrologer portal — a focused marketplace experience with a 4-item
/// bottom navigation (Dashboard · Requests · Notifications · Profile).
///
/// Astrologers manage their bookings, profile, reputation, certificates and
/// subscription. They never browse users or view user contacts — users contact
/// astrologers, not the other way around.
class AstrologerDashboardScreen extends ConsumerStatefulWidget {
  const AstrologerDashboardScreen({super.key});

  @override
  ConsumerState<AstrologerDashboardScreen> createState() =>
      _AstrologerDashboardScreenState();
}

class _AstrologerDashboardScreenState
    extends ConsumerState<AstrologerDashboardScreen> {
  int _index = 0;
  // Which sub-tab the embedded Requests page opens on (0 = Match Analysis,
  // 1 = Direct Visit). Bumped via [_openRequests] so the dashboard banner can
  // jump to the right tab; the ValueKey forces the TabController to re-init.
  int _requestsTab = 0;

  /// Opens the Requests bottom-nav tab (optionally on [subTab]) and clears the
  /// "new requests" unread banner/badge (spec §1).
  void _openRequests([int subTab = 0]) {
    setState(() {
      _index = 1;
      _requestsTab = subTab;
    });
    ref.read(requestsLastSeenProvider.notifier).markSeen();
  }

  void _onNavSelected(int i) {
    setState(() => _index = i);
    // Tapping the Requests tab also marks new requests as seen.
    if (i == 1) ref.read(requestsLastSeenProvider.notifier).markSeen();
  }

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
    final chatUnread = ref.watch(myUnreadChatCountProvider);
    final requestsUnread = ref.watch(unreadRequestsCountProvider);

    final tabs = <Widget>[
      AstrologerOverviewTab(onOpenRequests: _openRequests),
      AstrologerRequestsPage(
          embedded: true,
          initialTab: _requestsTab,
          key: ValueKey('requests_$_requestsTab')),
      const AstrologerNotificationsTab(),
      const AstrologerProfileTab(),
    ];

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
          // RIGHT: approval status pill + chat icon + notification icon.
          // (Availability now lives on the dashboard's availability card.)
          actions: [
            _approvalPill(account),
            const SizedBox(width: 2),
            // Chat — realtime unread red badge; opens the conversations list.
            IconButton(
              tooltip: 'Chats',
              onPressed: () => context.push('/chats'),
              icon: chatUnread > 0
                  ? Badge(
                      backgroundColor: AppColors.error,
                      label: Text('$chatUnread',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white)),
                      child: const Icon(Icons.chat_bubble_outline, size: 24),
                    )
                  : const Icon(Icons.chat_bubble_outline, size: 24),
            ),
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => setState(() => _index = 2),
              icon: notifUnread > 0
                  ? Badge(
                      backgroundColor: AppColors.gold,
                      label: Text('$notifUnread',
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.primary)),
                      child: const Icon(Icons.notifications_none, size: 24),
                    )
                  : const Icon(Icons.notifications_none, size: 24),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: IndexedStack(index: _index, children: tabs),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _onNavSelected,
          backgroundColor: Colors.white,
          indicatorColor: AppColors.primary.withOpacity(0.12),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard, color: AppColors.primary),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: requestsUnread > 0,
                label: Text('$requestsUnread'),
                child: const Icon(Icons.inbox_outlined),
              ),
              selectedIcon: const Icon(Icons.inbox, color: AppColors.primary),
              label: 'Requests',
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

  /// Compact AppBar pill showing the astrologer's verification / approval
  /// status. This is the SINGLE place approval status is surfaced — there is no
  /// separate approval card on the dashboard.
  Widget _approvalPill(AstrologerAccount account) {
    final Color color;
    final IconData icon;
    final String label;
    switch (account.status) {
      case VerificationStatus.approved:
        color = AppColors.success;
        icon = Icons.verified;
        label = 'Verified';
        break;
      case VerificationStatus.rejected:
        color = AppColors.error;
        icon = Icons.cancel;
        label = 'Rejected';
        break;
      case VerificationStatus.pending:
        color = AppColors.warning;
        icon = Icons.hourglass_top;
        label = 'Pending';
        break;
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
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
