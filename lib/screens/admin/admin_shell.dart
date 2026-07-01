import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

class AdminShell extends ConsumerWidget {
  final Widget child;

  const AdminShell({super.key, required this.child});

  // Bottom-nav destinations. Notifications now live inside Settings; the bottom
  // bar surfaces the five primary admin areas: Dashboard · Users · Employees
  // (horoscope-analysis staff) · Horoscope Requests · Settings.
  static const _routes = [
    '/admin',
    '/admin/users',
    '/admin/astrologers',
    '/admin/horoscope-requests',
    '/admin/settings',
  ];

  int _indexForLocation(String loc) {
    final i = _routes.indexOf(loc);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).matchedLocation;

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
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => context.go('/home'),
                icon: const Icon(Icons.home_outlined,
                    color: Colors.white, size: 20),
                label: const Text('Return to User App',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _indexForLocation(loc),
          onDestinationSelected: (i) => context.go(_routes[i]),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
            NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Users'),
            NavigationDestination(icon: Icon(Icons.badge_outlined), selectedIcon: Icon(Icons.badge), label: 'Employees'),
            NavigationDestination(icon: Icon(Icons.auto_stories_outlined), selectedIcon: Icon(Icons.auto_stories), label: 'Horoscope'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
