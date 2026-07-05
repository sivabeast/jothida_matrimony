import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_calendar_tab.dart';
import 'wedding_chat_page.dart';
import 'wedding_dashboard_tab.dart';
import 'wedding_expenses_page.dart';
import 'wedding_family_pages.dart';
import 'wedding_gallery_tab.dart';
import 'wedding_history_pages.dart';
import 'wedding_notes_page.dart';
import 'wedding_search_page.dart';
import 'wedding_section_pages.dart';
import 'wedding_tasks_tab.dart';
import 'wedding_vendors_page.dart';

/// The Wedding Workspace — the collaboration platform for the couple and
/// their invited family members, unlocked after mutual "Marriage Fixed".
///
/// Architecture: THREE independent workspaces — Bride, Shared, Groom — with
/// strict side visibility: every participant sees only THEIR side + Shared;
/// the opposite side's private content is never shown. The Bride and Groom
/// are Super Admins.
///
///   • Bottom navigation: Dashboard · Tasks · Gallery · Calendar.
///   • Header: "Bride ❤ Groom" + countdown, Search, and a right-side menu
///     drawer grouped into Planning / Family / Workspace / Settings.
class WeddingWorkspaceScreen extends ConsumerStatefulWidget {
  const WeddingWorkspaceScreen({super.key});

  @override
  ConsumerState<WeddingWorkspaceScreen> createState() =>
      _WeddingWorkspaceScreenState();
}

class _WeddingWorkspaceScreenState
    extends ConsumerState<WeddingWorkspaceScreen> {
  bool _sweepRan = false;
  int _tab = 0; // Dashboard is the control center and opening tab.

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
        icon: Icons.cloud_off_outlined,
        title: 'Could not load the Wedding Workspace',
        subtitle: 'Please check your connection and try again.\n$e',
      ),
      data: (wedding) {
        if (wedding == null || !wedding.isFixed) {
          return _messageScaffold(
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
            icon: Icons.no_accounts_outlined,
            title: "You don't have access.",
            subtitle:
                'Only the couple and their invited family members can open '
                'this Wedding Workspace.',
          );
        }

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: _buildAppBar(wedding, identity),
          endDrawer: _buildMenuDrawer(wedding, identity, isFamily),
          body: IndexedStack(
            index: _tab,
            children: [
              WeddingDashboardTab(wedding: wedding, identity: identity),
              WeddingTasksTab(wedding: wedding, identity: identity),
              WeddingGalleryTab(wedding: wedding, identity: identity),
              WeddingCalendarTab(wedding: wedding, identity: identity),
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
                  icon: Icon(Icons.dashboard_outlined),
                  activeIcon: Icon(Icons.dashboard),
                  label: 'Dashboard'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.task_alt_outlined),
                  activeIcon: Icon(Icons.task_alt),
                  label: 'Tasks'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.photo_library_outlined),
                  activeIcon: Icon(Icons.photo_library),
                  label: 'Gallery'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.calendar_month_outlined),
                  activeIcon: Icon(Icons.calendar_month),
                  label: 'Calendar'),
            ],
          ),
        );
      },
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(
      WeddingModel wedding, WeddingIdentity identity) {
    final bride = wedding.coupleIds
        .where((u) => wedding.sideOf(u) == 'bride')
        .map(wedding.nameOf)
        .join();
    final groom = wedding.coupleIds
        .where((u) => wedding.sideOf(u) == 'groom')
        .map(wedding.nameOf)
        .join();
    final date = wedding.weddingDate;
    final remaining = wedding.daysRemaining;
    final dateLine = date == null
        ? (wedding.isPostponed ? 'Postponed · new date pending' : null)
        : '${date.day}/${date.month}/${date.year}'
            '${remaining != null && remaining > 0 ? ' · $remaining days to go' : ''}'
            '${wedding.isPostponed ? ' · Postponed' : ''}';

    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$bride ❤️ $groom',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 15.5,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold),
          ),
          Text(
            dateLine == null
                ? 'Wedding Workspace'
                : 'Wedding Workspace · $dateLine',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10.5, color: Colors.white.withOpacity(0.85)),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search),
          onPressed: () => _push(const WeddingSearchPage()),
        ),
        Builder(
          builder: (ctx) => IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openEndDrawer(),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ── Right-side menu drawer ────────────────────────────────────────────────

  Widget _buildMenuDrawer(
      WeddingModel wedding, WeddingIdentity identity, bool isFamily) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Participant header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration:
                  const BoxDecoration(gradient: AppColors.primaryGradient),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: Text(
                      identity.name.isNotEmpty
                          ? identity.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(identity.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  Text(
                    identity.isSuperAdmin
                        ? '${identity.side == 'groom' ? 'Groom' : 'Bride'} · Super Admin'
                        : '${identity.sideLabel} · Family Member',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85), fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _menuGroup('Planning'),
                  _menuTile(Icons.storefront_outlined, 'Vendor Management',
                      () => _push(const WeddingVendorsPage())),
                  _menuTile(Icons.account_balance_wallet_outlined,
                      'Expense Tracker',
                      () => _push(const WeddingExpensesPage())),
                  _menuTile(Icons.sticky_note_2_outlined, 'Discussion Notes',
                      () => _push(const WeddingNotesPage())),

                  _menuGroup('Family'),
                  _menuTile(Icons.family_restroom_outlined, 'Family Members',
                      () => _push(const WeddingFamilyMembersPage())),
                  if (identity.isSuperAdmin)
                    _menuTile(Icons.admin_panel_settings_outlined,
                        'Permissions',
                        () => _push(const WeddingPermissionsPage())),
                  _menuTile(Icons.contacts_outlined, 'Shared Contacts',
                      () => _push(const WeddingContactsPage(
                          sideFilter: null, sharedOnly: true))),
                  _menuTile(Icons.forum_outlined, 'Family Chat',
                      () => _push(const WeddingChatPage())),
                  _menuTile(Icons.groups_outlined, 'Guest List',
                      () => _push(const WeddingGuestsPage())),

                  _menuGroup('Workspace'),
                  _menuTile(Icons.history_outlined, 'Activity Log',
                      () => _push(const WeddingActivityLogPage())),
                  _menuTile(Icons.published_with_changes_outlined,
                      'Decision History',
                      () => _push(const WeddingDecisionHistoryPage())),
                  _menuTile(Icons.notifications_outlined, 'Notifications',
                      () => _push(const WeddingNotificationsPage())),

                  _menuGroup('Settings'),
                  _menuTile(Icons.settings_outlined, 'Workspace Settings',
                      () => _push(const WeddingSettingsPage())),
                  _menuTile(Icons.person_outline, 'Profile',
                      () => _push(const WeddingProfilePage())),
                  if (identity.isCouple && !isFamily)
                    _menuTile(Icons.swap_horiz, 'Switch to Matrimony',
                        _switchToMatrimony),
                  _menuTile(Icons.logout, 'Logout', _logout,
                      color: AppColors.error),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuGroup(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
      child: Text(title.toUpperCase(),
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: Colors.grey[500])),
    );
  }

  Widget _menuTile(IconData icon, String label, VoidCallback onTap,
      {Color? color}) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -1),
      leading: Icon(icon, size: 21, color: color ?? AppColors.primary),
      title: Text(label,
          style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: color ?? Colors.black87)),
      onTap: () {
        Navigator.of(context).pop(); // close the drawer first
        onTap();
      },
    );
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

/// Scope label helper shared by workspace modules.
String weddingScopeLabel(String scope) => switch (scope) {
      'bride' => 'Bride',
      'groom' => 'Groom',
      _ => 'Shared',
    };