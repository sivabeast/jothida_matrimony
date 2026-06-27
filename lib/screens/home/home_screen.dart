import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../widgets/common/app_logo.dart';
import '../../providers/auth_provider.dart';
import '../../providers/announcement_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/notification_provider.dart';
import '../../widgets/common/app_drawer.dart';
import '../interests/interests_center_screen.dart';
import 'tabs/astrology_services_tab.dart';
import 'tabs/bookings_tab.dart';
import 'tabs/discover_tab.dart';
import 'tabs/home_dashboard_tab.dart';
import 'tabs/notifications_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Tab index → widget. Order matches the spec bottom navigation:
  // Home · Matches · Interests · Astrology · Bookings. Profile moved to the
  // header Drawer (it is no longer a bottom-nav tab).
  static const _tabs = <Widget>[
    HomeDashboardTab(),       // 0 – Home
    DiscoverTab(),            // 1 – Matches
    InterestsCenterScreen(),  // 2 – Interests
    AstrologyServicesTab(),   // 3 – Astrology
    BookingsTab(),            // 4 – Bookings
  ];

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(homeTabIndexProvider);
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
      // ── Navigation Drawer (header menu icon) ──────────────────────────────
      drawer: const AppDrawer(),
      // ── AppBar ────────────────────────────────────────────────────────────
      // The Home tab (index 0) renders its own curved header inside
      // HomeDashboardTab (which has its own menu icon), so the shared AppBar is
      // hidden there. Every other tab keeps this AppBar with a hamburger menu.
      appBar: selectedIndex == 0
          ? null
          : AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleSpacing: 4,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        // Header: [Logo] [Jothida Matrimony]. The "Find Your Perfect Match"
        // tagline subtitle was removed; the title is Flexible + ellipsis so it
        // never overflows or pushes the action icons on small screens.
        title: Row(
          children: [
            // App logo (official brand medallion).
            const AppLogo(size: 36),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                context.l10n.appTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 18,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Notification icon
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
          // Admin + Astrology dashboards — visible ONLY to the Super Admin
          // account (the whitelisted Gmail). Normal users never see these.
          if (isSuperAdmin) ...[
            IconButton(
              icon: const Icon(Icons.admin_panel_settings,
                  size: 26, color: AppColors.gold),
              tooltip: 'Admin Dashboard',
              onPressed: () {
                debugPrint('[HomeScreen] Admin icon tapped → /admin');
                context.push('/admin');
              },
            ),
            IconButton(
              icon: const Icon(Icons.auto_awesome,
                  size: 24, color: AppColors.gold),
              tooltip: 'Astrology Dashboard',
              onPressed: () => context.push('/astrology'),
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      // ── Body ─────────────────────────────────────────────────────────────
      body: _tabs[selectedIndex],
      // ── Bottom Navigation ─────────────────────────────────────────────────
      bottomNavigationBar: _BottomNav(
        selectedIndex: selectedIndex,
        onTap: (i) => ref.read(homeTabIndexProvider.notifier).state = i,
      ),
      ),
    );
  }

  DateTime? _lastBackPress;

  /// Android system-back handling for the home shell:
  ///  • not on the Home tab → switch back to the Home tab (never exits)
  ///  • on the Home tab      → "press back again to exit" within 2 seconds
  void _handleBackPress() {
    if (ref.read(homeTabIndexProvider) != 0) {
      ref.read(homeTabIndexProvider.notifier).state = 0;
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
    _NavItem(icon: Icons.people_outline, activeIcon: Icons.people),
    _NavItem(icon: Icons.auto_awesome_outlined, activeIcon: Icons.auto_awesome),
    _NavItem(
        icon: Icons.event_note_outlined, activeIcon: Icons.event_note),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = [
      l10n.home,
      l10n.matches,
      l10n.interests,
      l10n.astrologers,
      'Bookings',
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
