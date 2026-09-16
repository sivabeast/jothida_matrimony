import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/account_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../../repositories/auth_repository.dart';
import '../errors/auth_exception.dart';
import '../navigation/root_navigator.dart';
import '../theme/app_colors.dart';
import 'account_deletion_flow.dart';
import 'l10n_ext.dart';

/// Confirms, then PERMANENTLY deletes the signed-in account — the member's data
/// and the Firebase Authentication user — and only then returns to Login.
///
/// Shared by Settings and the dedicated Delete Account page (§14) so both
/// entry points behave identically. The order and its reasons live in
/// [AccountDeletionFlow]; this function is the screen side of it:
///
///  * the member is NOT signed out before the Auth user is deleted;
///  * the password prompt appears only when Firebase would require a recent
///    sign-in (Google accounts get the Google picker instead);
///  * on any failure the member stays signed in, on this screen, with a message
///    that says what did not happen — never a success message;
///  * the success message is shown only after the Auth user is really gone.
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

  // Captured before any async gap. The ROOT navigator and messenger outlive
  // this screen, which the router replaces once the account is gone.
  final rootNav = Navigator.of(context, rootNavigator: true);
  final messenger = rootScaffoldMessengerKey.currentState;
  final router = GoRouter.of(context);
  final repo = ref.read(authRepositoryProvider);
  final isAstrologer =
      ref.read(currentUserProvider).valueOrNull?.isAstrologer ?? false;

  void snack(String message) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // Blocking progress while deleting. Held as a route object so it is closed
  // exactly once and only while it is still on the navigator (the router may
  // already have replaced the pages beneath it after the Auth user went).
  final progress = DialogRoute<void>(
    context: rootNav.context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  rootNav.push(progress);
  void closeProgress() {
    if (progress.isActive) rootNav.removeRoute(progress);
  }

  Future<bool> reauthenticate(ReauthMethod method) async {
    switch (method) {
      case ReauthMethod.password:
        return await _promptPassword(rootNav.context, l10n, repo) ?? false;
      case ReauthMethod.google:
        try {
          return await repo.reauthenticateWithGoogle();
        } on AuthException catch (e) {
          snack(e.code == 'user-mismatch'
              ? l10n.deleteAccountGoogleMismatch
              : _reauthErrorText(l10n, e));
          return false;
        }
      case ReauthMethod.unsupported:
        return false;
    }
  }

  try {
    final result = await ref
        .read(accountControllerProvider.notifier)
        .deleteAccount(isAstrologer: isAstrologer, reauthenticate: reauthenticate);
    closeProgress();
    switch (result.outcome) {
      case AccountDeletionOutcome.deleted:
        // `go` REPLACES the whole navigation stack, so Back cannot return into
        // the deleted account.
        router.go('/login');
        snack(l10n.accountDeletedSuccess);
      case AccountDeletionOutcome.cancelled:
        snack(l10n.deleteAccountNotDeleted);
      case AccountDeletionOutcome.reauthUnsupported:
        snack(l10n.deleteAccountSignInAgain);
      case AccountDeletionOutcome.notSignedIn:
        snack(l10n.couldNotDeleteAccount);
        router.go('/login');
      case AccountDeletionOutcome.dataNotDeleted:
        snack(l10n.deleteAccountDataNotDeleted);
      case AccountDeletionOutcome.loginNotDeleted:
        snack(l10n.deleteAccountLoginNotDeleted);
    }
  } catch (e, st) {
    // Still signed in; nothing is reported as deleted.
    debugPrint('[accountDeletion] deleteAccount failed: $e\n$st');
    closeProgress();
    snack(l10n.couldNotDeleteAccount);
  }
}

/// Asks for the account password and re-authenticates with it. Returns true
/// once Firebase accepted it, false when the member cancelled. A wrong password
/// keeps the prompt open with an error, so the member can simply try again.
Future<bool?> _promptPassword(
  BuildContext context,
  AppLocalizations l10n,
  AuthRepository repo,
) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasswordReauthDialog(l10n: l10n, repo: repo),
  );
}

String _reauthErrorText(AppLocalizations l10n, AuthException e) {
  switch (e.code) {
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-mismatch':
      return l10n.deleteAccountWrongPassword;
    case 'too-many-requests':
      return l10n.deleteAccountTooManyAttempts;
    case 'network-request-failed':
    case 'network_error':
    case 'timeout':
      return l10n.deleteAccountNetworkError;
    default:
      return l10n.couldNotDeleteAccount;
  }
}

class _PasswordReauthDialog extends StatefulWidget {
  final AppLocalizations l10n;
  final AuthRepository repo;
  const _PasswordReauthDialog({required this.l10n, required this.repo});

  @override
  State<_PasswordReauthDialog> createState() => _PasswordReauthDialogState();
}

class _PasswordReauthDialogState extends State<_PasswordReauthDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _controller.text;
    if (password.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.reauthenticateWithPassword(password);
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      debugPrint('[accountDeletion] password re-authentication failed: '
          '${e.code}');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _reauthErrorText(widget.l10n, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(l10n.deleteAccountConfirmPasswordTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.deleteAccountConfirmPasswordBody),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: _obscure,
              enabled: !_busy,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l10n.password,
                errorText: _error,
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(l10n.deleteAccount),
          ),
        ],
      ),
    );
  }
}
