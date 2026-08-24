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
/// Admin-only moderation actions that are NOT profile fields — verify/reject,
/// Aadhaar verification, suspend, delete — live on the User Details page,
/// where they belong.
class AdminEditProfileScreen extends ConsumerWidget {
  final String uid;
  const AdminEditProfileScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(adminProfileByUserIdProvider(uid));

    return profileAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (e, _) => _message(
        context,
        icon: Icons.error_outline,
        text: 'Could not load this member\'s profile.\n$e',
      ),
      data: (profile) {
        if (profile == null) {
          // Nothing to edit: this account never created a matrimony profile.
          // "Create Profiles" is the flow for that, and it needs its own login
          // credentials step, so the admin is pointed back rather than dropped
          // into an edit wizard with no document behind it.
          return _message(
            context,
            icon: Icons.person_off_outlined,
            text: 'This account has not created a matrimony profile yet, '
                'so there is nothing to edit.',
          );
        }
        return ProfileCreationScreen(
          editProfileId: profile.id,
          ownerUserId: uid,
        );
      },
    );
  }

  Widget _message(BuildContext context,
          {required IconData icon, required String text}) =>
      Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: const Text('Edit Profile'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 14),
                Text(text,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[700])),
              ],
            ),
          ),
        ),
      );
}
