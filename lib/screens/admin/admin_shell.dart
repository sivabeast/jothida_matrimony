import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';

class AdminShell extends ConsumerWidget {
  final Widget child;

  const AdminShell({super.key, required this.child});

  // Bottom-nav destinations. The "Reports" tab opens the analytics page
  // (/admin/analytics); content-moderation reports live under Settings.
  static const _routes = [
    '/admin',
    '/admin/users',
    '/admin/astrologers',
    '/admin/analytics',
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
            // Return to the normal user app WITHOUT signing out. A super_admin is
            // a normal matrimony user who just dipped into the admin area.
            TextButton.icon(
              onPressed: () => context.go('/home'),
              icon:
                  const Icon(Icons.home_outlined, color: Colors.white, size: 20),
              label: const Text('User App',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign Out',
              onPressed: () async {
                debugPrint('[AdminShell] Sign Out tapped');
                await ref.read(authNotifierProvider.notifier).signOut();
                debugPrint('[AdminShell] signOut() complete');
                if (context.mounted) context.go('/account-type');
              },
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
            NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Astrologers'),
            NavigationDestination(icon: Icon(Icons.report_outlined), selectedIcon: Icon(Icons.report), label: 'Reports'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
