import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../widgets/common/app_logo.dart';
import '../../providers/auth_provider.dart';
import '../../providers/announcement_provider.dart';
import '../../providers/notification_provider.dart';
import '../interests/interests_center_screen.dart';
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

  // Tab index → widget. Tab 3 is the Interest Management Center (replaces the
  // old chat/messages page).
  static const _tabs = <Widget>[
    HomeDashboardTab(),       // 0 – Home
    DiscoverTab(),            // 1 – Matches
    AstrologyServicesTab(),   // 2 – Astrologer
    InterestsCenterScreen(),  // 3 – Interests
    MyProfileTab(),           // 4 – Profile
  ];

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadNotificationCountProvider) +
        ref.watch(unreadAnnouncementsCountProvider);
    // Admin icon visibility — only true for whitelisted Super Admin accounts.
    final isSuperAdmin =
        ref.watch(currentUserProvider).valueOrNull?.isSuperAdmin ?? false;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPress();
      },
      child: Scaffold(
      // ── AppBar ────────────────────────────────────────────────────────────
      // The Home tab (index 0) renders its own curved header inside
      // HomeDashboardTab, so the shared AppBar is hidden there. Every other tab
      // keeps this AppBar unchanged.
      appBar: _selectedIndex == 0
          ? null
          : AppBar(
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
                Text(
                  context.l10n.appTitle,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 17,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  context.l10n.appTagline.toUpperCase(),
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
                    title: Text(context.l10n.notifications),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  body: const NotificationsTab(),
                ),
              ),
            ),
            tooltip: context.l10n.notifications,
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
      ),
    );
  }

  DateTime? _lastBackPress;

  /// Android system-back handling for the home shell:
  ///  • not on the Home tab → switch back to the Home tab (never exits)
  ///  • on the Home tab      → "press back again to exit" within 2 seconds
  void _handleBackPress() {
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      return;
    }
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(context.l10n.pressBackToExit),
          duration: const Duration(seconds: 2),
        ));
      return;
    }
    SystemNavigator.pop();
  }
}

// ── Custom Bottom Navigation Bar ─────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.selectedIndex, required this.onTap});

  // Icons only — labels are localized per-build from [_labels] so the bar
  // switches language instantly with the rest of the app.
  static const _items = [
    _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home),
    _NavItem(icon: Icons.favorite_border, activeIcon: Icons.favorite),
    _NavItem(icon: Icons.auto_awesome_outlined, activeIcon: Icons.auto_awesome),
    _NavItem(icon: Icons.people_outline, activeIcon: Icons.people),
    _NavItem(icon: Icons.person_outline, activeIcon: Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = [
      l10n.home,
      l10n.matches,
      l10n.astrologers,
      l10n.interests,
      l10n.profile,
    ];
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
                        labels[i],
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
  const _NavItem({required this.icon, required this.activeIcon});
}
