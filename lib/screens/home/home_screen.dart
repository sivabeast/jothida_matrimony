import 'package:flutter/material.dart';
import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/profile_provider.dart';
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
    final l10n = AppLocalizations.of(context);
    final labels = [
      l10n.discover,
      l10n.astrologers,
      l10n.interests,
      l10n.alerts,
      l10n.profile,
    ];
    // Header identity: prefer the matrimony profile, fall back to the auth
    // user document, then a friendly default.
    final myProfile = ref.watch(myProfileProvider).valueOrNull;
    final myUser = ref.watch(currentUserProvider).valueOrNull;
    final displayName =
        myProfile?.fullName ?? myUser?.displayName ?? 'Welcome';
    final photoUrl = myProfile?.profilePhotoUrl ?? myUser?.photoUrl;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleSpacing: 12,
        title: Row(
          children: [
            // Profile image (left)
            GestureDetector(
              onTap: () => setState(() => _selectedIndex = 4),
              child: CircleAvatar(
                radius: 19,
                backgroundColor: Colors.white24,
                backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                    ? NetworkImage(photoUrl)
                    : null,
                child: (photoUrl == null || photoUrl.isEmpty)
                    ? Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            // User name beside the image
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('வணக்கம் 🙏',
                      style: TextStyle(
                          fontSize: 11, color: Colors.white.withOpacity(0.8))),
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => context.push('/chats'),
            tooltip: 'Chats',
          ),
          // Notification icon (top-right)
          IconButton(
            icon: unread > 0
                ? Badge(
                    label: Text('$unread'),
                    child: const Icon(Icons.notifications_none))
                : const Icon(Icons.notifications_none),
            onPressed: () => setState(() => _selectedIndex = 3),
            tooltip: 'Notifications',
          ),
          const SizedBox(width: 4),
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
            label: labels[i],
          ),
        ),
      ),
    );
  }
}
