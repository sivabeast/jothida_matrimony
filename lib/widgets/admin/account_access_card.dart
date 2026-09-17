import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/account_identity.dart';
import '../../core/utils/profile_save_error.dart';
import '../../core/utils/login_identifier.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/utils/validators.dart';
import '../../models/profile_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/firebase/admin_account_service.dart';
import 'login_conflict_dialog.dart';

/// Colour of a [MemberAccountStatus] chip.
Color memberStatusColor(MemberAccountStatus s) => switch (s) {
      MemberAccountStatus.profileNotCreated => Colors.blueGrey,
      MemberAccountStatus.profileIncomplete => AppColors.warning,
      MemberAccountStatus.profileCompleted => AppColors.success,
      MemberAccountStatus.authDeleted => AppColors.error,
      MemberAccountStatus.needsReview => AppColors.alertHigh,
    };

/// Admin → User Details → **Login & Access**.
///
/// Everything about the member's LOGIN, kept apart from their matrimony
/// profile: Firebase UID, registered phone, authentication and profile status,
/// and the actions — Check Login, Create Profile, Delete Login, Restore Login,
/// Temporary Password. Every destructive action first shows the account's
/// facts and asks for an explicit confirmation.
class AccountAccessCard extends ConsumerStatefulWidget {
  final UserModel user;
  final ProfileModel? profile;

  /// The profile lookup has not answered yet — no profile actions until it has.
  final bool profileLoading;

  const AccountAccessCard({
    super.key,
    required this.user,
    required this.profile,
    this.profileLoading = false,
  });

  @override
  ConsumerState<AccountAccessCard> createState() => _AccountAccessCardState();
}

class _AccountAccessCardState extends ConsumerState<AccountAccessCard> {
  bool _busy = false;
  LoginInspection? _inspection;

  UserModel get user => widget.user;
  String get _adminUid =>
      ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ?? '';
  AdminAccountService get _service => ref.read(adminAccountServiceProvider);

  String get _mobile => LoginIdentifier.localMobile(user.phone ?? '') ?? '';

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.error : null,
      ));
  }

  Future<T?> _run<T>(Future<T> Function() action) async {
    setState(() => _busy = true);
    try {
      return await action();
    } on AuthException catch (e) {
      _snack(e.message, error: true);
    } on LoginConflictException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      debugPrint('[Admin] action failed: $e');
      _snack(describeAdminActionError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  Future<LoginInspection?> _inspect() => _run(() async {
        final result = await _service.inspectMember(user.uid, mobile: _mobile);
        if (mounted) setState(() => _inspection = result);
        return result;
      });

  ExistingLogin? get _self {
    for (final a in _inspection?.accounts ?? const <ExistingLogin>[]) {
      if (a.uid == user.uid) return a;
    }
    return null;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _checkLogin() async {
    final inspection = await _inspect();
    if (inspection == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Login check'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!inspection.authChecked)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'The account backend is not deployed, so Firebase '
                      'Authentication itself could not be checked. Shown: what '
                      'the app\'s database holds.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                for (final a in inspection.accounts) ...[
                  AccountFactsCard(
                      account: a, authChecked: inspection.authChecked),
                  const SizedBox(height: 8),
                ],
                Text(
                  inspection.index == null
                      ? 'No mobile-number login is registered to this account.'
                      : 'Mobile login: +91 ${inspection.index!.mobile}'
                          '${LoginIdentifier.isPhoneAuthEmail(inspection.index!.authEmail) ? '' : ' → ${inspection.index!.authEmail}'}',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  /// Delete Login — the member cannot sign in any more; ALL data is kept.
  Future<void> _deleteLogin() async {
    final inspection = _inspection ?? await _inspect();
    if (inspection == null || !mounted) return;
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete login?',
      facts: [
        for (final a in inspection.accounts)
          if (a.uid == user.uid)
            AccountFactsCard(account: a, authChecked: inspection.authChecked),
      ],
      explanation:
          'The member will no longer be able to sign in, and the mobile number '
          'is released. Their matrimony profile, chats, interests, horoscope '
          'documents and requests are KEPT, and the login can be restored.'
          '${inspection.authChecked ? '\n\nThe Firebase Authentication record is deleted permanently.' : '\n\nThe account backend is not deployed: the Firebase login cannot be deleted from the app, so it is blocked instead.'}',
      actionLabel: 'Delete login',
    );
    if (confirmed != true) return;
    final result = await _run(
        () => _service.deleteLogin(user.uid, adminUid: _adminUid));
    if (result == null) return;
    setState(() => _inspection = null);
    _snack(result.backendUnavailable
        ? 'Login disabled. The member can no longer sign in; their data is kept.'
        : 'Login deleted from Firebase Authentication. The member\'s data is kept.');
  }

  /// Restore Login — gives a removed login back under the SAME account.
  Future<void> _restoreLogin() async {
    final password = TextEditingController();
    final mobile = TextEditingController(text: _mobile);
    final email =
        TextEditingController(text: LoginIdentifier.realEmailOrEmpty(user.email));
    final formKey = GlobalKey<FormState>();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore login'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Restores the login of THIS account — its profile and data '
                  'stay linked. Leave the password empty to re-enable a login '
                  'that was only disabled (the member keeps their old '
                  'password). A new password needs the account backend.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: mobile,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Mobile number', prefixText: '+91 '),
                  validator: (v) => LoginIdentifier.localMobile(v ?? '') == null
                      ? 'Enter a valid 10-digit mobile number'
                      : null,
                ),
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration:
                      const InputDecoration(labelText: 'E-mail (optional)'),
                ),
                TextFormField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'New password (optional)'),
                  validator: (v) => (v ?? '').isEmpty
                      ? null
                      : Validators.password(v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    if (password.text.isEmpty) {
      final ok = await _run(() async {
        await _service.restoreDisabledLogin(user.uid, adminUid: _adminUid);
        return true;
      });
      if (ok == true) _snack('Login restored. The member can sign in again.');
    } else {
      final account = await _run(() => _service.provisionMemberAccount(
            name: user.displayName ?? '',
            mobile: mobile.text,
            email: email.text,
            password: password.text,
            targetUid: user.uid,
            profileCreated: widget.profile != null,
          ));
      if (account != null) {
        _snack('Login restored for this account with the new password.');
      }
    }
    if (mounted) setState(() => _inspection = null);
  }

  /// Temporary Password — admin-assisted recovery (backend only).
  Future<void> _temporaryPassword({String requestId = ''}) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Set a temporary password?',
      facts: [
        if (_self != null)
          AccountFactsCard(
              account: _self!, authChecked: _inspection?.authChecked ?? false),
      ],
      explanation:
          'A one-time password is generated and shown to you ONCE. Every '
          'session of this member is signed out, and they must choose a new '
          'password at their next sign-in. Only share it with the member '
          'through their registered number.',
      actionLabel: 'Generate',
      typedConfirmation: false,
    );
    if (confirmed != true) return;
    final temp = await _run(
        () => _service.setTemporaryPassword(user.uid, requestId: requestId));
    if (temp == null || temp.isEmpty || !mounted) return;
    await showTemporaryPasswordDialog(context,
        mobile: _mobile, password: temp, memberName: user.displayName ?? '');
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final status = classifyMemberAccount(user: user, profile: widget.profile);
    final access = user.loginAccess;
    final loginRemoved = !access.canSignIn;
    final self = _self;

    Widget row(String k, String v, {bool copy = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 150,
                child: Text(k,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ),
              Expanded(
                child: GestureDetector(
                  onLongPress: copy
                      ? () {
                          Clipboard.setData(ClipboardData(text: v));
                          _snack('Copied');
                        }
                      : null,
                  child: Text(v,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Login & Access',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              ),
              if (_busy)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(status.label, memberStatusColor(status)),
              _chip(
                  switch (access) {
                    LoginAccessState.active => 'LOGIN ACTIVE',
                    LoginAccessState.disabled => 'LOGIN DISABLED',
                    LoginAccessState.deleted => 'AUTH ACCOUNT DELETED',
                  },
                  access.canSignIn ? AppColors.success : AppColors.error),
              if (user.mustChangePassword)
                _chip('MUST CHANGE PASSWORD', AppColors.warning),
            ],
          ),
          const SizedBox(height: 8),
          row('Firebase UID', user.uid, copy: true),
          row('Registered Phone', _mobile.isEmpty ? '—' : '+91 $_mobile'),
          row('Login e-mail',
              LoginIdentifier.realEmailOrEmpty(user.email).isEmpty
                  ? (_mobile.isEmpty ? '—' : 'Mobile number login')
                  : user.email!.trim()),
          row(
              'Firebase login',
              self == null
                  ? 'Tap "Check login"'
                  : !(_inspection?.authChecked ?? false)
                      ? 'Unknown — backend not deployed'
                      : self.authExists == true
                          ? 'Exists (${self.providers.join(', ')})'
                          : 'Does not exist'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _action('Check login', Icons.fact_check_outlined, _checkLogin),
              if (!widget.profileLoading && widget.profile == null)
                _action('Create profile', Icons.person_add_alt_1,
                    () => context.push('/admin/user/${user.uid}/create-profile'),
                    filled: true),
              if (loginRemoved)
                _action('Restore login', Icons.lock_open_outlined, _restoreLogin)
              else ...[
                _action('Temporary password', Icons.password_outlined,
                    () => _temporaryPassword()),
                _action('Delete login', Icons.no_accounts_outlined,
                    _deleteLogin,
                    danger: true),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label.toUpperCase(),
            style: TextStyle(
                color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
      );

  Widget _action(String label, IconData icon, VoidCallback onTap,
      {bool danger = false, bool filled = false}) {
    final color = danger ? AppColors.error : AppColors.primary;
    if (filled) {
      return ElevatedButton.icon(
        onPressed: _busy ? null : onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
            backgroundColor: color, foregroundColor: Colors.white),
      );
    }
    return OutlinedButton.icon(
      onPressed: _busy ? null : onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
          foregroundColor: color, side: BorderSide(color: color)),
    );
  }
}

/// A confirmation that shows the account facts and — for anything permanent —
/// requires typing `DELETE`, so a mis-tap can never remove an account.
Future<bool?> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required List<Widget> facts,
  required String explanation,
  required String actionLabel,
  bool typedConfirmation = true,
}) {
  final typed = TextEditingController();
  return showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...facts,
                if (facts.isNotEmpty) const SizedBox(height: 10),
                Text(explanation,
                    style: const TextStyle(fontSize: 13, height: 1.4)),
                if (typedConfirmation) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: typed,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Type DELETE to confirm',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: !typedConfirmation || typed.text.trim() == 'DELETE'
                ? () => Navigator.pop(ctx, true)
                : null,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: Text(actionLabel),
          ),
        ],
      ),
    ),
  );
}

/// Shows a temporary password ONCE. It is never stored — closing the dialog
/// is the last time it exists on this device.
Future<void> showTemporaryPasswordDialog(
  BuildContext context, {
  required String mobile,
  required String password,
  String memberName = '',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Temporary password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Shown only once. Give it to the member through their REGISTERED '
            'number only. They must set their own password at next sign-in.',
            style: TextStyle(fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          SelectableText(password,
              style: const TextStyle(
                  fontSize: 22,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace')),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(text: password)),
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy'),
        ),
        if (mobile.isNotEmpty)
          TextButton.icon(
            onPressed: () {
              final name = memberName.trim().isEmpty ? '' : ' $memberName';
              final text = 'Namaskaram$name,\n\nYour Jothida Matrimony '
                  'temporary password is: $password\n\nSign in with your '
                  'mobile number and this password. You will be asked to set a '
                  'new password immediately.';
              launchUrl(
                Uri.parse('${whatsappUri(mobile)}?text=${Uri.encodeComponent(text)}'),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.chat_outlined, size: 18),
            label: const Text('WhatsApp'),
          ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
