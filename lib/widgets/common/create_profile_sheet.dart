import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';

/// Opens [route] for a signed-in member, or — for a visitor who is NOT logged
/// in (including guest browsing) — slides up the "Create Your Profile" sheet
/// instead.
///
/// A logged-out visitor must never reach a full profile page: they stay exactly
/// where they were (Search / Interests / Home), with that list still visible
/// behind the sheet, and closing it returns them to it untouched. No profile
/// data is loaded or shown by the sheet.
///
/// Members with an incomplete profile are NOT handled here — they continue
/// through the normal `MemberGate` on the profile route, which explains what
/// they still need to finish.
Future<void> openProfileOrPrompt(
  BuildContext context,
  WidgetRef ref,
  String route,
) async {
  final signedOut = ref.read(isGuestProvider) ||
      ref.read(firebaseAuthStreamProvider).valueOrNull == null;
  if (signedOut) {
    await showCreateProfileSheet(context);
    return;
  }
  if (context.mounted) context.push(route);
}

/// The bottom sheet itself: slides up from the bottom, covers only as much as
/// it needs, and leaves the page behind it visible and untouched.
Future<void> showCreateProfileSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      // Not a full-screen takeover — the sheet hugs its content.
      isScrollControlled: false,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _CreateProfileSheet(),
    );

class _CreateProfileSheet extends StatelessWidget {
  const _CreateProfileSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.14),
                      AppColors.gold.withValues(alpha: 0.20),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(Icons.lock_person_outlined,
                    size: 30, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Create Your Profile',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your profile to view full profile details and continue.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5, height: 1.4, color: Colors.grey[700]),
            ),
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/profile/create');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Create Profile',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/login');
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Login / Sign Up',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Not now',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13.5)),
            ),
          ],
        ),
      ),
    );
  }
}
