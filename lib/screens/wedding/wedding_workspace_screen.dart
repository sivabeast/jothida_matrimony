import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_gallery_page.dart';
import 'wedding_section_pages.dart';
import 'wedding_shared_tab.dart';
import 'wedding_side_tab.dart';
import 'wedding_vendors_page.dart';

/// The Wedding Workspace — a SEPARATE app experience (own navigation, own
/// look) unlocked after both partners confirm "Marriage Fixed". The moment a
/// user lands here they should feel "I am now inside the Wedding Workspace".
///
///   • Bottom navigation: Bride Side · Shared (default) · Groom Side.
///   • Top menu: Dashboard, Documents, Gallery, Vendors, Family Contacts,
///     Guest List, Settings, Switch to Matrimony, Logout.
///
/// Participants: the couple (bride/groom, matrimony users) and their invited
/// family members (Gmail-invited Family Users, locked to this workspace).
class WeddingWorkspaceScreen extends ConsumerStatefulWidget {
  const WeddingWorkspaceScreen({super.key});

  @override
  ConsumerState<WeddingWorkspaceScreen> createState() =>
      _WeddingWorkspaceScreenState();
}

class _WeddingWorkspaceScreenState
    extends ConsumerState<WeddingWorkspaceScreen> {
  bool _sweepRan = false;
  int _tab = 1; // Shared is the default page.

  @override
  Widget build(BuildContext context) {
    final weddingAsync = ref.watch(activeWeddingProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isFamily = user?.isFamily ?? false;

    return weddingAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (e, _) => _messageScaffold(
        isFamily: isFamily,
        icon: Icons.cloud_off_outlined,
        title: 'Could not load the Wedding Workspace',
        subtitle: 'Please check your connection and try again.\n$e',
      ),
      data: (wedding) {
        if (wedding == null || !wedding.isFixed) {
          return _messageScaffold(
            isFamily: isFamily,
            icon: Icons.lock_outline,
            title: 'Wedding Workspace is locked',
            subtitle: wedding == null
                ? 'The workspace unlocks after both partners confirm '
                    '"Marriage Fixed" on an accepted match.'
                : 'Waiting for both partners to confirm "Marriage Fixed". '
                    'Once confirmed, the workspace unlocks for the couple '
                    'and their invited family members.',
            showExitToMatrimony: !isFamily,
          );
        }

        // Auto-Married sweep: once per screen build cycle, if the wedding
        // date has passed, the signed-in couple member's profile is marked
        // Married (removed from matchmaking, interests disabled).
        if (!_sweepRan) {
          _sweepRan = true;
          Future.microtask(() => ref
              .read(weddingControllerProvider.notifier)
              .runMarriedSweepIfDue(wedding));
        }

        final identity = ref.watch(weddingIdentityProvider(wedding));
        if (identity == null) {
          return _messageScaffold(
            isFamily: isFamily,
            icon: Icons.no_accounts_outlined,
            title: "You don't have access.",
            subtitle:
                'Only the couple and their invited family members can open '
                'this Wedding Workspace.',
          );
        }

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: _buildAppBar(wedding, identity, isFamily),
          body: IndexedStack(
            index: _tab,
            children: [
              WeddingSideTab(side: 'bride', wedding: wedding, identity: identity),
              WeddingSharedTab(wedding: wedding, identity: identity),
              WeddingSideTab(side: 'groom', wedding: wedding, identity: identity),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: Colors.grey[500],
            selectedLabelStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            items: const [
              BottomNavigationBarItem(
                  icon: Text('👰', style: TextStyle(fontSize: 22)),
                  label: 'Bride Side'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.favorite), label: 'Shared'),
              BottomNavigationBarItem(
                  icon: Text('🤵', style: TextStyle(fontSize: 22)),
                  label: 'Groom Side'),
            ],
          ),
        );
      },
    );
  }

  // ── App bar + top menu ────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(
      WeddingModel wedding, WeddingIdentity identity, bool isFamily) {
    final groom = wedding.coupleIds
        .where((u) => wedding.sideOf(u) == 'groom')
        .map(wedding.nameOf)
        .join();
    final bride = wedding.coupleIds
        .where((u) => wedding.sideOf(u) == 'bride')
        .map(wedding.nameOf)
        .join();

    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Wedding Workspace',
              style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          Text(
            '$groom ❤ $bride'
            '${wedding.isPostponed ? '  ·  Postponed' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11.5, color: Colors.white.withOpacity(0.85)),
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Menu',
          icon: const Icon(Icons.menu),
          onSelected: (v) => _onMenu(v, wedding, identity),
          itemBuilder: (_) => [
            _menuItem('dashboard', Icons.dashboard_outlined, 'Dashboard'),
            _menuItem('documents', Icons.folder_outlined, 'Documents'),
            _menuItem('gallery', Icons.photo_library_outlined, 'Gallery'),
            _menuItem('vendors', Icons.storefront_outlined, 'Vendors'),
            _menuItem('contacts', Icons.contacts_outlined, 'Family Contacts'),
            _menuItem('guests', Icons.groups_outlined, 'Guest List'),
            _menuItem('settings', Icons.settings_outlined, 'Settings'),
            if (identity.isCouple && !isFamily)
              _menuItem('switch', Icons.swap_horiz, 'Switch to Matrimony'),
            _menuItem('logout', Icons.logout, 'Logout'),
          ],
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 13.5)),
        ],
      ),
    );
  }

  void _onMenu(String value, WeddingModel wedding, WeddingIdentity identity) {
    switch (value) {
      case 'dashboard':
        _push(const WeddingDashboardPage());
      case 'documents':
        _push(const WeddingDocumentsPage(scope: null));
      case 'gallery':
        _push(const WeddingGalleryPage(scope: null));
      case 'vendors':
        _push(const WeddingVendorsPage());
      case 'contacts':
        _push(const WeddingContactsPage(sideFilter: null));
      case 'guests':
        _push(const WeddingGuestsPage());
      case 'settings':
        _push(const WeddingSettingsPage());
      case 'switch':
        _switchToMatrimony();
      case 'logout':
        _logout();
    }
  }

  /// Sub-pages use a plain Navigator push so the go_router location stays on
  /// /wedding-workspace — family accounts (locked to this location) can then
  /// browse every workspace page freely.
  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _switchToMatrimony() async {
    ref.read(entryModeProvider.notifier).state = WeddingEntryMode.matrimony;
    await WeddingEntryMode.save(WeddingEntryMode.matrimony);
    if (!mounted) return;
    context.go('/home');
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Do you want to logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final router = GoRouter.of(context);
    await WeddingEntryMode.save(null);
    await ref.read(authNotifierProvider.notifier).signOut();
    router.go('/login');
  }

  // ── Locked / error states ─────────────────────────────────────────────────

  Scaffold _messageScaffold({
    required bool isFamily,
    required IconData icon,
    required String title,
    required String subtitle,
    bool showExitToMatrimony = false,
  }) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Wedding Workspace'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout),
              onPressed: _logout),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13.5)),
              if (showExitToMatrimony) ...[
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Go to Matrimony'),
                  onPressed: _switchToMatrimony,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared "who did what" caption used across workspace pages.
String weddingByLine(String name, DateTime at) =>
    '$name · ${at.day}/${at.month}/${at.year}';
