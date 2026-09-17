import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/account_identity.dart';
import '../../core/utils/profile_status.dart';
import '../../services/firebase/admin_account_service.dart';

/// What the admin decided when a login could not simply be created.
sealed class LoginResolution {
  const LoginResolution();
}

/// Create a new login after all — releasing a stale registry entry, or
/// replacing an unused Firebase login (backend), which the admin confirmed.
class CreateNewLogin extends LoginResolution {
  final bool releaseStaleIndex;
  final String replaceOrphanUid;
  const CreateNewLogin({this.releaseStaleIndex = false, this.replaceOrphanUid = ''});
}

/// Create the profile for the EXISTING account instead of a new login.
class LinkExistingAccount extends LoginResolution {
  final ExistingLogin account;
  const LinkExistingAccount(this.account);
}

/// Spark plan: prove ownership of the leftover login with its password.
class ReclaimWithPassword extends LoginResolution {
  final String currentPassword;
  const ReclaimWithPassword(this.currentPassword);
}

/// Stop and open the existing account (or Account Health when [uid] is '').
class OpenExistingAccount extends LoginResolution {
  final String uid;
  const OpenExistingAccount(this.uid);
}

/// Explains a [LoginConflictException] with the facts the admin needs — phone
/// number, Firebase UID, profile status, account status — and offers only the
/// actions that are safe for that case. Nothing destructive happens without an
/// explicit confirmation inside the dialog.
Future<LoginResolution?> showLoginConflictDialog(
  BuildContext context,
  LoginConflictException conflict, {
  bool allowLinkExisting = true,
}) {
  return showDialog<LoginResolution>(
    context: context,
    builder: (_) => _LoginConflictDialog(
        conflict: conflict, allowLinkExisting: allowLinkExisting),
  );
}

class _LoginConflictDialog extends StatefulWidget {
  final LoginConflictException conflict;
  final bool allowLinkExisting;
  const _LoginConflictDialog(
      {required this.conflict, required this.allowLinkExisting});

  @override
  State<_LoginConflictDialog> createState() => _LoginConflictDialogState();
}

class _LoginConflictDialogState extends State<_LoginConflictDialog> {
  bool _verified = false;
  bool _confirmed = false;
  bool _obscure = true;
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  LoginConflictException get c => widget.conflict;

  List<ExistingLogin> get _accounts {
    final inspection = c.inspection;
    final list = <ExistingLogin>[
      if (c.account != null) c.account!,
      if (inspection != null)
        for (final a in inspection.accounts)
          if (a.uid != c.account?.uid) a,
    ];
    return list;
  }

  bool get _authChecked =>
      c.inspection?.authChecked ?? (c.account?.authExists != null);

  String get _title => switch (c.kind) {
        LoginConflictKind.phoneInUse => 'Mobile number already in use',
        LoginConflictKind.emailInUse => 'E-mail already in use',
        LoginConflictKind.staleIndex => 'Number held by a deleted login',
        LoginConflictKind.authRecordStillExists => 'Old Firebase login found',
      };

  @override
  Widget build(BuildContext context) {
    final live = [for (final a in _accounts) if (a.isLive) a];
    final single = live.length == 1 ? live.first : c.account;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.manage_accounts_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(_title, style: const TextStyle(fontSize: 17))),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c.message, style: const TextStyle(height: 1.4)),
              const SizedBox(height: 12),
              for (final a in _accounts) ...[
                AccountFactsCard(account: a, authChecked: _authChecked),
                const SizedBox(height: 8),
              ],
              ..._body(single),
            ],
          ),
        ),
      ),
      actions: _actions(single, live.length),
    );
  }

  List<Widget> _body(ExistingLogin? single) {
    switch (c.kind) {
      case LoginConflictKind.phoneInUse:
      case LoginConflictKind.emailInUse:
        if (single == null || !_canLink(single)) {
          return [
            _note(single != null && single.profileCount > 0
                ? 'This account already has a matrimony profile. A second '
                    'profile is never created — open the account and edit its '
                    'profile instead.'
                : 'Resolve the duplicate records in Account Health first.'),
          ];
        }
        return [
          _note('Create this profile for the EXISTING account instead. Its '
              'login and password stay as they are — no second account is '
              'created.'),
          CheckboxListTile(
            value: _verified,
            onChanged: (v) => setState(() => _verified = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I have verified that this person owns this account (for example '
              'by calling the registered mobile number).',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ];
      case LoginConflictKind.staleIndex:
        return [
          _note('The account this number was registered to no longer exists. '
              'Releasing the number removes only that leftover registration — '
              'no profile, chat or document is touched.'),
          CheckboxListTile(
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Release the number and create a new login',
                style: TextStyle(fontSize: 13)),
          ),
        ];
      case LoginConflictKind.authRecordStillExists:
        final orphan = c.account;
        if (_authChecked && orphan != null) {
          return [
            _note('Nothing in the app belongs to this Firebase login (no '
                'account record, no profile). It can be deleted permanently '
                'and replaced by the new login.'),
            CheckboxListTile(
              value: _confirmed,
              onChanged: (v) => setState(() => _confirmed = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                  'Permanently delete Firebase login ${orphan.uid} and create '
                  'the new one',
                  style: const TextStyle(fontSize: 13)),
            ),
          ];
        }
        return [
          _note('The account backend (Cloud Functions) is not deployed, so the '
              'app cannot see or delete this login. It deletes itself the next '
              'time someone signs in with it, or immediately once the backend '
              'is deployed.\n\nIf you know its CURRENT password, verify it here '
              'to replace it now.'),
          const SizedBox(height: 8),
          TextField(
            controller: _password,
            obscureText: _obscure,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Current password of the old login',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ];
    }
  }

  bool _canLink(ExistingLogin a) =>
      widget.allowLinkExisting &&
      a.profileCount == 0 &&
      (a.role.isEmpty || a.role == 'user');

  List<Widget> _actions(ExistingLogin? single, int liveCount) {
    final cancel = TextButton(
        onPressed: () => Navigator.pop(context), child: const Text('Cancel'));
    switch (c.kind) {
      case LoginConflictKind.phoneInUse:
      case LoginConflictKind.emailInUse:
        return [
          cancel,
          if (single != null)
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, OpenExistingAccount(single.uid)),
              child: const Text('Open account'),
            )
          else
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, const OpenExistingAccount('')),
              child: const Text('Open Account Health'),
            ),
          if (single != null && _canLink(single))
            ElevatedButton(
              onPressed: _verified
                  ? () => Navigator.pop(context, LinkExistingAccount(single))
                  : null,
              style: _primary,
              child: const Text('Use existing account'),
            ),
        ];
      case LoginConflictKind.staleIndex:
        return [
          cancel,
          ElevatedButton(
            onPressed: _confirmed
                ? () => Navigator.pop(
                    context, const CreateNewLogin(releaseStaleIndex: true))
                : null,
            style: _primary,
            child: const Text('Release & create'),
          ),
        ];
      case LoginConflictKind.authRecordStillExists:
        final orphan = c.account;
        if (_authChecked && orphan != null) {
          return [
            cancel,
            ElevatedButton(
              onPressed: _confirmed
                  ? () => Navigator.pop(
                      context, CreateNewLogin(replaceOrphanUid: orphan.uid))
                  : null,
              style: _danger,
              child: const Text('Delete old & create'),
            ),
          ];
        }
        return [
          cancel,
          ElevatedButton(
            onPressed: _password.text.isEmpty
                ? null
                : () => Navigator.pop(
                    context, ReclaimWithPassword(_password.text)),
            style: _primary,
            child: const Text('Verify & continue'),
          ),
        ];
    }
  }

  static final _primary = ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary, foregroundColor: Colors.white);
  static final _danger = ElevatedButton.styleFrom(
      backgroundColor: AppColors.error, foregroundColor: Colors.white);

  Widget _note(String text) => Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4)),
      );
}

/// Phone number, Firebase UID, profile status and account status of one
/// account — the facts every destructive admin action shows before it runs.
class AccountFactsCard extends StatelessWidget {
  final ExistingLogin account;

  /// Whether Firebase Auth itself was checked (backend deployed).
  final bool authChecked;

  const AccountFactsCard(
      {super.key, required this.account, required this.authChecked});

  String get _profile {
    if (account.profileCount > 1) {
      return '${account.profileCount} profiles — needs review';
    }
    if (account.profileCount == 0) return 'Profile Not Created';
    final status = account.profileStatus.trim().isEmpty
        ? ''
        : ' · ${profileStatusLabel(account.profileStatus)}';
    return '${account.profileName.isEmpty ? 'Profile' : account.profileName}$status';
  }

  String get _accountStatus {
    if (account.tombstoneMode == LoginTombstone.modeDeleted) {
      return 'Deleted by an admin';
    }
    if (!account.hasAccountRecord) return 'No account record';
    return switch (account.access) {
      LoginAccessState.active => 'Active',
      LoginAccessState.disabled => 'Login disabled (data kept)',
      LoginAccessState.deleted => 'Firebase login deleted (data kept)',
    };
  }

  String get _firebaseLogin {
    if (!authChecked || account.authExists == null) {
      return 'Unknown — backend not deployed';
    }
    if (account.authExists == false) return 'Does not exist';
    final providers =
        account.providers.isEmpty ? '' : ' (${account.providers.join(', ')})';
    return 'Exists$providers';
  }

  @override
  Widget build(BuildContext context) {
    Widget row(String k, String v, {bool copy = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 112,
                  child: Text(k,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
              Expanded(
                child: copy
                    ? InkWell(
                        onTap: () => Clipboard.setData(ClipboardData(text: v)),
                        child: Text(v,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      )
                    : Text(v,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (account.name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(account.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          row('Phone', account.mobile.isEmpty ? '—' : '+91 ${account.mobile}'),
          row('Firebase UID', account.uid, copy: true),
          row('Profile', _profile),
          row('Account', _accountStatus),
          row('Firebase login', _firebaseLogin),
          if (account.role.isNotEmpty && account.role != 'user')
            row('Role', account.role),
        ],
      ),
    );
  }
}
