import 'dart:async' show TimeoutException;

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/admin_provider.dart';
import '../profile/profile_creation_screen.dart';

/// Admin → Edit User Profile (`/admin/user/:uid/edit`).
///
/// This screen deliberately contains NO form of its own. It resolves the
/// member's profile document from their uid and then hands off to
/// [ProfileCreationScreen] in edit mode — the very same wizard the member
/// used to create the profile and uses to edit it (§13/§15).
///
/// The admin therefore sees exactly the finalized profile structure: the same
/// sections, the same fields, the same order, the same validation. The old
/// admin-only editor (a separate flat form with its own subset of fields, its
/// own dropdowns and its own save shape) is gone, so admin and member can no
/// longer drift apart.
///
/// [ProfileCreationScreen.ownerUserId] carries the MEMBER's uid, so photos,
/// the `userId` field and the gated contact record are all written under the
/// profile's owner rather than under the signed-in admin.
///
/// FOUR distinct states — the old screen had only "loading" and "no profile",
/// and showed "no profile" whenever the first (cached) answer was empty:
///
///  * **loading** — a spinner, never a premature "no profile";
///  * **found** — the wizard, seeded with the member's saved profile;
///  * **no profile** — only when the SERVER confirmed there is none and none
///    of the member's profile pointers leads to one;
///  * **error** — network / permission failures, with Retry. They are never
///    taken as proof that the member has no profile.
///
/// The profile is resolved once ([adminEditProfileTargetProvider]), not
/// streamed, so nothing can rebuild the wizard under the admin's unsaved edits.
///
/// Admin-only moderation actions that are NOT profile fields — verify/reject,
/// Aadhaar verification, suspend, delete — live on the User Details page,
/// where they belong.
class AdminEditProfileScreen extends ConsumerWidget {
  final String uid;
  const AdminEditProfileScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = uid.trim();
    if (member.isEmpty) {
      return _AdminEditMessage(
        icon: Icons.person_search_outlined,
        title: 'No member selected',
        text: 'Open Edit Profile from a member in Users.',
        onBack: () => _back(context),
      );
    }

    final target = ref.watch(adminEditProfileTargetProvider(member));
    return target.when(
      // Retry must show the spinner again, not the stale error.
      skipLoadingOnRefresh: false,
      loading: () => const Scaffold(
        key: ValueKey('admin-edit-loading'),
        backgroundColor: AppColors.scaffoldBg,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
      error: (e, _) => _AdminEditMessage(
        key: const ValueKey('admin-edit-error'),
        icon: Icons.cloud_off_outlined,
        title: 'Could not load this member\'s profile',
        text: describeAdminProfileLoadError(e),
        onBack: () => _back(context),
        primaryLabel: 'Retry',
        primaryIcon: Icons.refresh,
        onPrimary: () => ref.invalidate(adminEditProfileTargetProvider(member)),
      ),
      data: (profile) {
        if (profile == null) {
          // Confirmed by the server: this account has no matrimony profile.
          // An empty profile is NOT created here — "Create Profiles" is the
          // admin flow for a new member, and it needs its own login step.
          return _AdminEditMessage(
            key: const ValueKey('admin-edit-no-profile'),
            icon: Icons.person_off_outlined,
            title: 'No matrimony profile yet',
            text:
                'This account has not created a matrimony profile yet, '
                'so there is nothing to edit.',
            onBack: () => _back(context),
            primaryLabel: 'View User Details',
            primaryIcon: Icons.person_search_outlined,
            onPrimary: () => context.pushReplacement('/admin/user/$member'),
          );
        }
        final owner = profile.userId.trim();
        if (owner.isNotEmpty && owner != member) {
          // Defence in depth — the lookup already refuses this.
          return _AdminEditMessage(
            key: const ValueKey('admin-edit-mismatch'),
            icon: Icons.gpp_maybe_outlined,
            title: 'Profile does not belong to this member',
            text:
                'The profile found (${profile.id}) is owned by another '
                'account, so it was not opened.',
            onBack: () => _back(context),
          );
        }
        return ProfileCreationScreen(
          key: ValueKey('admin-edit-${profile.id}'),
          editProfileId: profile.id,
          ownerUserId: member,
        );
      },
    );
  }

  static void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/admin/users');
    }
  }
}

/// Admin → a member with a login but NO profile → Create Profile
/// (`/admin/user/:uid/create-profile`).
///
/// The server is asked first whether the account really has no profile — the
/// same lookup as [AdminEditProfileScreen] — so this page can never create a
/// second one: an existing profile opens in the editor instead. The wizard then
/// writes the new profile under the member's OWN Firebase UID.
class AdminCreateMemberProfileScreen extends ConsumerWidget {
  final String uid;
  const AdminCreateMemberProfileScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = uid.trim();
    if (member.isEmpty) {
      return _AdminEditMessage(
        icon: Icons.person_search_outlined,
        title: 'No member selected',
        text: 'Open Create Profile from a member in Users.',
        onBack: () => AdminEditProfileScreen._back(context),
      );
    }
    final account = ref.watch(adminUserByUidProvider(member));
    final target = ref.watch(adminEditProfileTargetProvider(member));
    if (account.isLoading || target.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (target.hasError) {
      return _AdminEditMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not check this member',
        text: describeAdminProfileLoadError(target.error!),
        onBack: () => AdminEditProfileScreen._back(context),
        primaryLabel: 'Retry',
        primaryIcon: Icons.refresh,
        onPrimary: () => ref.invalidate(adminEditProfileTargetProvider(member)),
      );
    }
    final user = account.valueOrNull;
    if (user == null) {
      return _AdminEditMessage(
        icon: Icons.no_accounts_outlined,
        title: 'Account not found',
        text: 'There is no account record for this user id, so a profile '
            'cannot be linked to it. Review it in Account Health.',
        onBack: () => AdminEditProfileScreen._back(context),
      );
    }
    final existing = target.valueOrNull;
    if (existing != null) {
      return _AdminEditMessage(
        icon: Icons.person_outline,
        title: 'Profile already exists',
        text: 'This account already has a matrimony profile '
            '(${existing.fullName.isEmpty ? existing.id : existing.fullName}). '
            'An account can only have one — edit it instead.',
        onBack: () => AdminEditProfileScreen._back(context),
        primaryLabel: 'Edit Profile',
        primaryIcon: Icons.edit_outlined,
        onPrimary: () => context.pushReplacement('/admin/user/$member/edit'),
      );
    }
    if (const {'admin', 'super_admin', 'astrologer', 'family'}
        .contains(user.role)) {
      return _AdminEditMessage(
        icon: Icons.badge_outlined,
        title: 'Not a matrimony account',
        text: 'This is a ${user.role} account. Staff, admin and family accounts '
            'never have a matrimony profile.',
        onBack: () => AdminEditProfileScreen._back(context),
      );
    }
    return ProfileCreationScreen(
      key: ValueKey('admin-create-for-$member'),
      adminForMember: true,
      ownerUserId: member,
    );
  }
}

/// A human explanation of a failed profile load — the cause decides what the
/// admin can do about it.
String describeAdminProfileLoadError(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Permission denied. This account is not allowed to read member '
            'profiles — check that its role is admin and that the latest '
            'Firestore rules are deployed.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'The server could not be reached. Check the internet '
            'connection and try again.';
    }
    return 'Firestore error (${error.code}). Please try again.';
  }
  if (error is TimeoutException) {
    return 'The server took too long to answer. Check the internet connection '
        'and try again.';
  }
  return 'Something went wrong while loading the profile. Please try again.\n'
      '$error';
}

class _AdminEditMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onBack;
  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;

  const _AdminEditMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.onBack,
    this.primaryLabel,
    this.primaryIcon,
    this.onPrimary,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.scaffoldBg,
    appBar: AppBar(
      title: const Text('Edit Profile'),
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      leading: IconButton(icon: const Icon(Icons.close), onPressed: onBack),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: Colors.grey[400]),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 22),
              if (onPrimary != null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onPrimary,
                    icon: Icon(primaryIcon ?? Icons.arrow_forward),
                    label: Text(primaryLabel ?? ''),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextButton(onPressed: onBack, child: const Text('Back')),
            ],
          ),
        ),
      ),
    ),
  );
}
