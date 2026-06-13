import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../providers/astrologer_session_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/notification_provider.dart';
import '../home/tabs/notifications_tab.dart';
import 'tabs/astrologer_appointments_tab.dart';
import 'tabs/astrologer_messages_tab.dart';
import 'tabs/astrologer_overview_tab.dart';
import 'tabs/astrologer_profile_tab.dart';
import 'tabs/astrologer_requests_tab.dart';

/// The astrologer portal — a mobile-first shell with a 5-item bottom navigation
/// (Dashboard · Requests · Appointments · Messages · Profile). Each destination
/// is its own tab widget; all of them read real Firestore data.
class AstrologerDashboardScreen extends ConsumerStatefulWidget {
  const AstrologerDashboardScreen({super.key});

  @override
  ConsumerState<AstrologerDashboardScreen> createState() =>
      _AstrologerDashboardScreenState();
}

class _AstrologerDashboardScreenState
    extends ConsumerState<AstrologerDashboardScreen> {
  int _index = 0;

  static const _tabs = <Widget>[
    AstrologerOverviewTab(),
    AstrologerRequestsTab(),
    AstrologerAppointmentsTab(),
    AstrologerMessagesTab(),
    AstrologerProfileTab(),
  ];

  void _openNotifications() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: const NotificationsTab(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(myAstrologerAccountProvider);
    if (account == null) {
      // Router normally prevents reaching here un-onboarded — guard anyway.
      return const Scaffold(
        body: Center(child: Text('Please complete onboarding')),
      );
    }

    // Live badge counts (read-only reuse of existing providers).
    final pendingRequests = ref
            .watch(astrologerRequestsProvider)
            .valueOrNull
            ?.where((r) => r.status == AstrologerRequestStatus.pending)
            .length ??
        0;
    final myUid = ref.watch(myUidProvider) ?? '';
    final unreadMessages = ref.watch(myChatThreadsProvider).valueOrNull?.fold<int>(
              0,
              (sum, t) => sum + t.unreadFor(myUid),
            ) ??
        0;
    final notifUnread = ref.watch(unreadNotificationCountProvider);
    final initial = account.fullName.trim().isNotEmpty
        ? account.fullName.trim()[0].toUpperCase()
        : '?';

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
        // LEFT: profile photo + astrologer name (only).
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              backgroundImage: account.photoUrl.isNotEmpty
                  ? NetworkImage(account.photoUrl)
                  : null,
              child: account.photoUrl.isEmpty
                  ? Text(initial,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(account.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold)),
                  Text('Astrologer',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.white.withOpacity(0.8),
                          letterSpacing: 0.5)),
                ],
              ),
            ),
          ],
        ),
        // RIGHT: notification icon only.
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: notifUnread > 0
                ? Badge(
                    label: Text('$notifUnread',
                        style: const TextStyle(fontSize: 10)),
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.notifications_none, size: 26),
                  )
                : const Icon(Icons.notifications_none, size: 26),
            onPressed: _openNotifications,
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
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingRequests > 0,
              label: Text('$pendingRequests'),
              child: const Icon(Icons.assignment_outlined),
            ),
            selectedIcon: const Icon(Icons.assignment, color: AppColors.primary),
            label: 'Requests',
          ),
          const NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note, color: AppColors.primary),
            label: 'Appointments',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unreadMessages > 0,
              label: Text('$unreadMessages'),
              child: const Icon(Icons.chat_bubble_outline),
            ),
            selectedIcon:
                const Icon(Icons.chat_bubble, color: AppColors.primary),
            label: 'Messages',
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

  DateTime? _lastBackPress;

  /// Android system-back handling for the astrologer shell:
  ///  • not on the Dashboard tab → switch back to the Dashboard tab
  ///  • on the Dashboard tab      → "press back again to exit" within 2 seconds
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
