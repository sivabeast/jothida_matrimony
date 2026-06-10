import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/notification_provider.dart';
import '../astrologer/astrologers_tab.dart';
import 'tabs/discover_tab.dart';
import 'tabs/interests_tab.dart';
import 'tabs/my_profile_tab.dart';
import 'tabs/notifications_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  static const _tabs = [
    DiscoverTab(),
    AstrologersTab(),
    InterestsTab(),
    NotificationsTab(),
    MyProfileTab(),
  ];

  static const _labels = ['Discover', 'Astrologers', 'Interests', 'Alerts', 'Profile'];
  static const _icons = [
    Icons.search,
    Icons.auto_awesome_outlined,
    Icons.favorite_border,
    Icons.notifications_none,
    Icons.person_outline,
  ];
  static const _activeIcons = [
    Icons.search,
    Icons.auto_awesome,
    Icons.favorite,
    Icons.notifications,
    Icons.person,
  ];

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadNotificationCountProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jothida Matrimony',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/search'),
            tooltip: 'Search & Filter',
          ),
        ],
      ),
      body: _tabs[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primary.withOpacity(0.12),
        destinations: List.generate(
          _tabs.length,
          (i) => NavigationDestination(
            icon: i == 3 && unread > 0
                ? Badge(label: Text('$unread'), child: Icon(_icons[i]))
                : Icon(_icons[i]),
            selectedIcon: Icon(_activeIcons[i], color: AppColors.primary),
            label: _labels[i],
          ),
        ),
      ),
    );
  }
}
