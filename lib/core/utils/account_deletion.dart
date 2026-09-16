import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/account_provider.dart';
import '../../providers/auth_provider.dart';
import '../navigation/root_navigator.dart';
import '../theme/app_colors.dart';
import 'l10n_ext.dart';

/// Confirms, then permanently deletes the signed-in account (no admin
/// approval) and returns the user to the Login screen with the navigation
/// stack cleared.
///
/// Shared by Settings and the dedicated Delete Account page (§14) so both
/// entry points behave identically.
Future<void> confirmAndDeleteAccount(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.deleteAccount),
      content: Text(l10n.deleteAccountWarning),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.deleteAccount),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  // Capture BOTH before the async gap: `context` belongs to a screen that is
  // about to be torn down by the auth-state redirect. The ROOT messenger (not
  // this screen's) is used because the calling scaffold no longer exists by the
  // time we have a result to report.
  final messenger = rootScaffoldMessengerKey.currentState;
  final router = GoRouter.of(context);
  final couldNotDelete = context.l10n.couldNotDeleteAccount;
  final isAstrologer =
      ref.read(currentUserProvider).valueOrNull?.isAstrologer ?? false;

  // Blocking progress while we delete. PopScope stops the Android back button
  // from dismissing it mid-deletion.
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );

  var dialogOpen = true;
  void closeProgress() {
    if (!dialogOpen || !context.mounted) return;
    dialogOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  try {
    final result = await ref
        .read(accountControllerProvider.notifier)
        .deleteAccount(isAstrologer: isAstrologer);
    closeProgress();
    // `go` REPLACES the whole navigation stack, so Back cannot return to Home.
    // The router's redirect independently enforces this: the account is signed
    // out and its user document is gone, so every gated route sends it here.
    router.go('/login');
    if (!result.isComplete) {
      // Something survived — the Firebase Auth record (re-authentication was
      // refused), a Firestore collection that could not be cleared, or both.
      // Say so rather than silently implying a clean deletion; the combination
      // in `mayResurrect` is the one that can bring the old profile back at the
      // next sign-in, and it is logged in full so it can be finished off.
      debugPrint('[accountDeletion] INCOMPLETE — authDeleted='
          '${result.authDeleted}, residualData=${result.residualData}, '
          'failedSteps=${result.failedSteps.join(',')}, '
          'mayResurrect=${result.mayResurrect}');
      messenger?.showSnackBar(SnackBar(content: Text(couldNotDelete)));
    }
  } catch (e) {
    debugPrint('[accountDeletion] deleteAccount failed: $e');
    closeProgress();
    messenger?.showSnackBar(SnackBar(content: Text(couldNotDelete)));
  }
}
