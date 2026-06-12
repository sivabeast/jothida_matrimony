import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/common/app_logo.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../chat/chat_list_screen.dart';
import 'tabs/astrology_services_tab.dart';
import 'tabs/discover_tab.dart';
import 'tabs/home_dashboard_tab.dart';
import 'tabs/my_profile_tab.dart';
import 'tabs/notifications_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  // Tab index → widget (Messages tab uses ChatListScreen inline).
  static const _tabs = <Widget>[
    HomeDashboardTab(),   // 0 – Home
    DiscoverTab(),        // 1 – Matches
    AstrologyServicesTab(), // 2 – Astrologer
    ChatListScreen(),     // 3 – Messages
    MyProfileTab(),       // 4 – Profile
  ];

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadNotificationCountProvider);
    // Admin icon visibility — only true for whitelisted Super Admin accounts.
    final isSuperAdmin =
        ref.watch(currentUserProvider).valueOrNull?.isSuperAdmin ?? false;

    return Scaffold(
      // ── AppBar ────────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleSpacing: 12,
        automaticallyImplyLeading: false,   // no hamburger menu
        title: Row(
          children: [
            // App logo (official brand medallion).
            const AppLogo(size: 40),
            const SizedBox(width: 10),
            // Brand name + subtitle
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Jothida Matrimony',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 17,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  'FIND YOUR PERFECT MATCH',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.80),
                    fontSize: 9.5,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Notification icon (only icon in the AppBar)
          IconButton(
            icon: unread > 0
                ? Badge(
                    label: Text('$unread',
                        style: const TextStyle(fontSize: 10)),
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.notifications_none, size: 26),
                  )
                : const Icon(Icons.notifications_none, size: 26),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(
                    title: const Text('Notifications'),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  body: const NotificationsTab(),
                ),
              ),
            ),
            tooltip: 'Notifications',
          ),
          // Admin Dashboard — visible ONLY to Super Admin accounts. Normal
          // users and astrologers never see this icon.
          if (isSuperAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings,
                  size: 26, color: AppColors.gold),
              tooltip: 'Admin Dashboard',
              onPressed: () {
                debugPrint('[HomeScreen] Admin icon tapped → /admin');
                context.push('/admin');
              },
            ),
          const SizedBox(width: 4),
        ],
      ),
      // ── Body ─────────────────────────────────────────────────────────────
      body: _tabs[_selectedIndex],
      // ── Bottom Navigation ─────────────────────────────────────────────────
      bottomNavigationBar: _BottomNav(
        selectedIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
      ),
    );
  }
}

// ── Custom Bottom Navigation Bar ─────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.selectedIndex, required this.onTap});

  static const _items = [
    _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
    _NavItem(icon: Icons.favorite_border, activeIcon: Icons.favorite, label: 'Matches'),
    _NavItem(icon: Icons.auto_awesome_outlined, activeIcon: Icons.auto_awesome, label: 'Astrologer'),
    _NavItem(icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble, label: 'Messages'),
    _NavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final active = i == selectedIndex;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  splashColor: AppColors.primary.withOpacity(0.08),
                  highlightColor: Colors.transparent,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        active ? item.activeIcon : item.icon,
                        color: active ? AppColors.primary : Colors.grey[500],
                        size: 24,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                          color: active ? AppColors.primary : Colors.grey[500],
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}
