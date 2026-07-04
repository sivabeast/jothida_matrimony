import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_checklist_tab.dart';
import 'wedding_contacts_tab.dart';
import 'wedding_documents_tab.dart';
import 'wedding_guests_tab.dart';
import 'wedding_overview_tab.dart';

/// The collaborative Wedding Workspace — unlocked ONLY after both partners
/// confirm "Marriage Fixed". Bride, groom and their invited family members
/// plan the wedding together here: shared checklist with task assignment,
/// countdown, documents, family contacts and the guest list.
class WeddingWorkspaceScreen extends ConsumerStatefulWidget {
  const WeddingWorkspaceScreen({super.key});

  @override
  ConsumerState<WeddingWorkspaceScreen> createState() =>
      _WeddingWorkspaceScreenState();
}

class _WeddingWorkspaceScreenState
    extends ConsumerState<WeddingWorkspaceScreen> {
  bool _sweepRan = false;

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
      error: (e, _) => _scaffold(
        isFamily: isFamily,
        body: _message(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load the Wedding Workspace',
          subtitle: 'Please check your connection and try again.\n$e',
        ),
      ),
      data: (wedding) {
        if (wedding == null || !wedding.isFixed) {
          return _scaffold(
            isFamily: isFamily,
            body: _message(
              icon: Icons.lock_outline,
              title: 'Wedding Workspace is locked',
              subtitle: wedding == null
                  ? 'The workspace unlocks after both partners confirm '
                      '"Marriage Fixed" on an accepted match.'
                  : 'Waiting for both partners to confirm "Marriage Fixed". '
                      'Once confirmed, the workspace unlocks for the couple '
                      'and their invited family members.',
            ),
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
          return _scaffold(
            isFamily: isFamily,
            body: _message(
              icon: Icons.no_accounts_outlined,
              title: "You don't have access.",
              subtitle:
                  'Only the couple and their invited family members can open '
                  'this Wedding Workspace.',
            ),
          );
        }

        return DefaultTabController(
          length: 5,
          child: Scaffold(
            backgroundColor: AppColors.scaffoldBg,
            appBar: AppBar(
              title: const Text('Wedding Workspace'),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              actions: [if (isFamily) _logoutAction()],
              bottom: const TabBar(
                isScrollable: true,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: AppColors.gold,
                labelStyle:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: [
                  Tab(text: 'Overview'),
                  Tab(text: 'Checklist'),
                  Tab(text: 'Documents'),
                  Tab(text: 'Contacts'),
                  Tab(text: 'Guests'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                WeddingOverviewTab(wedding: wedding, identity: identity),
                WeddingChecklistTab(wedding: wedding, identity: identity),
                WeddingDocumentsTab(wedding: wedding, identity: identity),
                WeddingContactsTab(wedding: wedding, identity: identity),
                WeddingGuestsTab(wedding: wedding, identity: identity),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Family users live ONLY on this screen, so they sign out from here.
  Widget _logoutAction() {
    return IconButton(
      tooltip: 'Logout',
      icon: const Icon(Icons.logout),
      onPressed: () async {
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
        await ref.read(authNotifierProvider.notifier).signOut();
        router.go('/login');
      },
    );
  }

  Scaffold _scaffold({required Widget body, required bool isFamily}) =>
      Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: const Text('Wedding Workspace'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [if (isFamily) _logoutAction()],
        ),
        body: body,
      );

  Widget _message(
      {required IconData icon,
      required String title,
      required String subtitle}) {
    return Center(
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
          ],
        ),
      ),
    );
  }
}

/// Shared "who did what" caption used across workspace tabs.
String weddingByLine(String name, DateTime at) =>
    '$name · ${at.day}/${at.month}/${at.year}';
