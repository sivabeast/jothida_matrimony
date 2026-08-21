import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/admin_badge_provider.dart';
import '../../widgets/common/app_logo.dart';

/// One entry in the admin navigation drawer.
class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  const _NavItem(this.label, this.icon, this.route);
}

/// A titled group of drawer entries ([title] is null for the ungrouped
/// Dashboard entry at the top).
class _NavGroup {
  final String? title;
  final List<_NavItem> items;
  const _NavGroup(this.title, this.items);
}

/// Admin navigation shell — a professional SaaS-style grouped
/// [Drawer] (Material 3) opened from the AppBar menu icon. Every admin area is
/// reachable from the drawer; the previously orphaned Analytics, Married
/// Members and Test Data routes are all linked here.
///
/// Drawer entries that can receive new work carry a live red badge (spec
/// §20–§26): the number of NEW action-required records for that section, from
/// [adminBadgeCountsProvider]. Opening the section marks it seen, which clears
/// the badge without touching a single record.
class AdminShell extends ConsumerWidget {
  final Widget child;

  const AdminShell({super.key, required this.child});

  static const List<_NavGroup> _groups = [
    _NavGroup(null, [
      _NavItem('Dashboard', Icons.dashboard_outlined, '/admin'),
    ]),
    _NavGroup('User Management', [
      _NavItem('All Users', Icons.people_outline, '/admin/users'),
      _NavItem('Pending Verification', Icons.verified_outlined,
          '/admin/approvals'),
      _NavItem('Married Members', Icons.favorite_outline, '/admin/married'),
      _NavItem('Create Profile', Icons.person_add_alt_1, '/admin/create-profile'),
    ]),
    _NavGroup('Employee Management', [
      _NavItem('Employees', Icons.badge_outlined, '/admin/astrologers'),
      _NavItem('Commission', Icons.percent, '/admin/commission'),
    ]),
    _NavGroup('Horoscope', [
      _NavItem('Requests', Icons.auto_stories_outlined,
          '/admin/horoscope-requests'),
    ]),
    // Astrology appointments get their OWN top-level entry: they are a separate
    // customer flow from horoscope report requests (no employee assignment, and
    // the admin's main job here is ringing the customer back).
    _NavGroup('Astrology', [
      _NavItem('Astrology Bookings', Icons.event_available,
          '/admin/appointments'),
      _NavItem('Astrology Service', Icons.auto_awesome_outlined,
          '/admin/astrology-service'),
    ]),
    _NavGroup('Payments', [
      _NavItem('Transactions', Icons.receipt_long_outlined, '/admin/payments'),
      _NavItem('Revenue & Analytics', Icons.insights, '/admin/analytics'),
    ]),
    _NavGroup('Reports', [
      _NavItem('User Reports', Icons.flag_outlined, '/admin/reports'),
      _NavItem('Activity Log', Icons.history_outlined, '/admin/activity-log'),
    ]),
    _NavGroup('Content', [
      _NavItem('Banners', Icons.image_outlined, '/admin/banners'),
      _NavItem('Announcements', Icons.campaign_outlined, '/admin/notifications'),
    ]),
    // There is deliberately no "General" hub and no "Pricing" page: General
    // only duplicated entries that already exist in this drawer, and the app
    // has no pricing/subscription model (the one-time Horoscope Request payment
    // is handled by the Horoscope flow itself).
    //
    // No "App Update" entry either: updates are driven entirely by Google Play
    // In-App Updates and need no admin action (spec §9).
    _NavGroup('Settings', [
      _NavItem('Test Data', Icons.science_outlined, '/admin/test-data'),
    ]),
  ];

  /// The drawer route to highlight for the current location. Detail pages
  /// highlight their parent list entry.
  static String? _selectedRoute(String loc) {
    for (final g in _groups) {
      for (final item in g.items) {
        if (item.route == loc) return item.route;
      }
    }
    if (loc.startsWith('/admin/user/')) return '/admin/users';
    // Covers /admin/astrologer-account/:id (employee details).
    if (loc.startsWith('/admin/astrologer')) return '/admin/astrologers';
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).matchedLocation;

    // Landing on a badged section IS the admin seeing it: clear its badge
    // (the records themselves are untouched — spec §26). Deferred to after
    // the frame so the notifier is never written to during a build.
    if (AdminBadgeSection.all.contains(loc)) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => ref.read(adminSeenProvider.notifier).markSeen(loc));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Any admin child page → back to the Admin Dashboard.
        // Already on the Dashboard → back to the user app (never closes the app;
        // a super_admin is a normal user who dipped into the admin area).
        if (loc != '/admin') {
          context.go('/admin');
        } else {
          context.go('/home');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Builder(
            builder: (ctx) => _MenuButtonWithDot(
              hasNew: ref
                  .watch(adminBadgeCountsProvider)
                  .values
                  .any((c) => c > 0),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          title: const Text('Jothida Admin',
              style:
                  TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [
            // The Admin Dashboard is only an extra access area for an account
            // that is ALSO a normal user, so there is NO Logout here. This
            // button simply returns to the user app and keeps the session fully
            // intact — no sign-out, no session clear.
            IconButton(
              tooltip: 'Return to User App',
              onPressed: () => context.go('/home'),
              icon: const Icon(Icons.home_outlined, color: Colors.white),
            ),
          ],
        ),
        drawer: _AdminDrawer(selectedRoute: _selectedRoute(loc)),
        body: child,
      ),
    );
  }
}

/// The grouped navigation drawer: brand header, labelled sections of nav items
/// with a primary-tint highlight on the active route, a live notification
/// badge on every section that can receive new work, and a pinned
/// "Return to User App" action at the bottom.
class _AdminDrawer extends ConsumerWidget {
  final String? selectedRoute;
  const _AdminDrawer({required this.selectedRoute});

  void _open(BuildContext context, String route) {
    Navigator.of(context).pop(); // close the drawer first
    if (route != GoRouterState.of(context).matchedLocation) {
      context.go(route);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(adminBadgeCountsProvider);
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          _header(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 6, bottom: 12),
              children: [
                for (final group in AdminShell._groups) ...[
                  if (group.title != null) _SectionLabel(group.title!),
                  for (final item in group.items)
                    _DrawerItem(
                      item: item,
                      selected: item.route == selectedRoute,
                      badge: badges[item.route] ?? 0,
                      onTap: () => _open(context, item.route),
                    ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: _DrawerItem(
              item: const _NavItem(
                  'Return to User App', Icons.logout_outlined, '/home'),
              selected: false,
              onTap: () {
                Navigator.of(context).pop();
                context.go('/home');
              },
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 20, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          const AppLogo(size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Jothida Matrimony',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('Admin Panel',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Uppercase 11px section label above each drawer group.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Colors.grey[600])),
    );
  }
}

/// A single drawer row — compact, rounded, with a primary tint + w600 label
/// when it is the active route.
class _DrawerItem extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  /// New/action-required records for this section. 0 renders NO badge at all
  /// (spec §21) — an empty queue must look empty.
  final int badge;

  const _DrawerItem({
    required this.item,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : Colors.grey[800]!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(item.icon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? AppColors.primary : Colors.black87)),
                ),
                if (badge > 0) _NotificationBadge(count: badge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The red count badge on a drawer row. Renders the exact number up to 99 and
/// "99+" beyond, so a busy queue never blows the row's width.
class _NotificationBadge extends StatelessWidget {
  final int count;
  const _NotificationBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      margin: const EdgeInsets.only(left: 8),
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: Text(label,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1.2)),
    );
  }
}

/// The drawer button with a small red dot when ANY admin section has new work.
/// No count here — the exact numbers live on the drawer rows themselves.
class _MenuButtonWithDot extends StatelessWidget {
  final bool hasNew;
  final VoidCallback onPressed;
  const _MenuButtonWithDot({required this.hasNew, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
      onPressed: onPressed,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.menu),
          if (hasNew)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 1.2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
