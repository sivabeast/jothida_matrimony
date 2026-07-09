import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../widgets/common/app_logo.dart';
import '../../providers/auth_provider.dart';
import '../../providers/announcement_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/notification_provider.dart';
import '../../widgets/common/app_drawer.dart';
import '../interests/interests_center_screen.dart';
import 'tabs/astrology_service_page.dart';
import 'tabs/discover_tab.dart';
import 'tabs/home_dashboard_tab.dart';
import 'tabs/notifications_tab.dart';
import 'tabs/reports_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Tab index → widget. Order matches the spec bottom navigation:
  // Home · Matches · Interests · Reports · Astrology. Chat moved to the Home
  // header (icon + unread badge); Profile lives in the header Drawer.
  static const _tabs = <Widget>[
    HomeDashboardTab(),       // 0 – Home
    DiscoverTab(),            // 1 – Matches
    InterestsCenterScreen(),  // 2 – Interests
    ReportsTab(),             // 3 – Reports
    AstrologyServicePage(),   // 4 – Astrology
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
          // Chat icon (beside Notifications) with an unread badge — replaces the
          // removed Chats bottom-nav tab.
          _ChatAction(unread: ref.watch(myUnreadChatCountProvider)),
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
          // Admin dashboard shortcut — visible ONLY to the Super Admin account
          // (the whitelisted Gmail). The Astrology/astrologer dashboard is
          // intentionally NOT here: admin and astrologer roles are fully
          // separated, so the admin account can never open an astrologer view.
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
      // Lazily-built IndexedStack: each tab is built on FIRST visit and then
      // kept alive, so switching tabs never resets a tab's state — the
      // Matches swipe browser continues exactly where the user left it, and
      // tabs don't refetch their data on every visit.
      body: _LazyTabStack(index: selectedIndex, tabs: _tabs),
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

/// An [IndexedStack] that builds each tab only on its FIRST visit and keeps it
/// alive afterwards. Unvisited tabs stay as empty placeholders, so the home
/// shell doesn't pay for all five tabs (providers, queries) up front, while a
/// visited tab's state (scroll/pager position, loaded data) survives tab
/// switches — the Matches page never restarts from profile 1 just because the
/// user opened Home / Interests / Chat and came back.
class _LazyTabStack extends StatefulWidget {
  final int index;
  final List<Widget> tabs;
  const _LazyTabStack({required this.index, required this.tabs});

  @override
  State<_LazyTabStack> createState() => _LazyTabStackState();
}

class _LazyTabStackState extends State<_LazyTabStack> {
  late final List<bool> _built =
      List<bool>.filled(widget.tabs.length, false);

  @override
  Widget build(BuildContext context) {
    _built[widget.index] = true;
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.tabs.length; i++)
          _built[i] ? widget.tabs[i] : const SizedBox.shrink(),
      ],
    );
  }
}

// ── Custom Bottom Navigation Bar ─────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.selectedIndex, required this.onTap});

  // Icons only — labels are localized per-build from [_labels] so the bar
  // switches language instantly with the rest of the app.
  // Order (spec): Home · Matches · Interests · Reports · Astrology.
  static const _items = [
    _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home),
    _NavItem(icon: Icons.favorite_border, activeIcon: Icons.favorite),
    _NavItem(icon: Icons.people_outline, activeIcon: Icons.people),
    _NavItem(
        icon: Icons.description_outlined, activeIcon: Icons.description),
    _NavItem(
        icon: Icons.auto_awesome_outlined, activeIcon: Icons.auto_awesome),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = [
      l10n.home,
      l10n.matches,
      l10n.interests,
      l10n.reports,
      l10n.astrology,
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

/// AppBar Chat action with a red unread badge. Opens the Chats list.
class _ChatAction extends StatelessWidget {
  final int unread;
  const _ChatAction({required this.unread});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Chats',
      onPressed: () => context.push('/chats'),
      icon: unread > 0
          ? Badge(
              label: Text('$unread', style: const TextStyle(fontSize: 10)),
              backgroundColor: Colors.red,
              child: const Icon(Icons.chat_bubble_outline, size: 25),
            )
          : const Icon(Icons.chat_bubble_outline, size: 25),
    );
  }
}
