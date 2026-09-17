import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/account_identity.dart';
import '../../core/utils/login_identifier.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/firebase/admin_account_service.dart';
import '../../widgets/admin/account_access_card.dart';
import '../../widgets/admin/login_conflict_dialog.dart';

/// The last Account Health scan. Kept while the admin works through the list;
/// Rescan invalidates it. Never a live stream — a scan reads every account.
final accountScanProvider = FutureProvider.autoDispose<AccountScanReport>(
    (ref) => ref.read(adminAccountServiceProvider).scanAccounts());

final _reviewedKeysProvider = FutureProvider.autoDispose<Set<String>>((ref) =>
    ref.read(firestoreServiceProvider).reviewedAccountIssueKeys().catchError(
        (Object _) => <String>{}));

/// Admin → Account Health (Authentication Management).
///
/// Cross-checks accounts, profiles, the mobile-number registry, the
/// one-profile ownership records and — when the account backend is deployed —
/// Firebase Authentication itself, and lists every inconsistency in its own
/// section: duplicate phone numbers, deleted or unlinked logins, profiles whose
/// login is gone, multiple profiles on one account, missing profiles.
///
/// NOTHING is changed by the scan. Each case is resolved individually, after
/// the admin has seen the phone number, Firebase UID, profile status and
/// account status, and every permanent action asks for a typed confirmation.
/// Accounts are never merged automatically on a matching phone number.
class AccountHealthScreen extends ConsumerStatefulWidget {
  const AccountHealthScreen({super.key});

  @override
  ConsumerState<AccountHealthScreen> createState() =>
      _AccountHealthScreenState();
}

class _AccountHealthScreenState extends ConsumerState<AccountHealthScreen> {
  bool _showReviewed = false;

  static const _order = [
    AccountIssueType.duplicatePhone,
    AccountIssueType.multipleProfiles,
    AccountIssueType.profileWithoutAccount,
    AccountIssueType.staleLoginIndex,
    AccountIssueType.authWithoutAccount,
    AccountIssueType.accountWithoutAuth,
    AccountIssueType.loginIndexMismatch,
    AccountIssueType.missingOwnershipRecord,
  ];

  void _rescan() {
    ref.invalidate(accountScanProvider);
    ref.invalidate(_reviewedKeysProvider);
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(accountScanProvider);
    final reviewed = ref.watch(_reviewedKeysProvider).valueOrNull ?? const {};
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: scan.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 12),
              Text('Scanning accounts, profiles and logins…'),
            ],
          ),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined,
                    size: 48, color: AppColors.error),
                const SizedBox(height: 10),
                Text('The scan could not complete.\n$e',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                    onPressed: _rescan,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again')),
              ],
            ),
          ),
        ),
        data: (report) => RefreshIndicator(
          onRefresh: () async => _rescan(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _header(report),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _showReviewed,
                onChanged: (v) => setState(() => _showReviewed = v),
                title: const Text('Show cases marked as reviewed'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              for (final type in _order)
                _section(type, report, reviewed),
              _missingProfiles(report),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AccountScanReport r) {
    Widget tile(String label, String value) => Expanded(
          child: Column(
            children: [
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Account Health',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: 'Rescan',
                onPressed: _rescan,
                icon: const Icon(Icons.refresh, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            tile('Accounts', '${r.accounts}'),
            tile('Profiles', '${r.profiles}'),
            tile('Firebase logins',
                r.authChecked ? '${r.authAccounts}' : '—'),
            tile('Cases', '${r.issues.length}'),
          ]),
          const SizedBox(height: 10),
          Text(
            r.authChecked
                ? 'Firebase Authentication was checked.'
                : 'Firebase Authentication was NOT checked — the account '
                    'backend (Cloud Functions, Blaze plan) is not deployed. '
                    'Deleted / unlinked login checks need it.',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _section(
      AccountIssueType type, AccountScanReport report, Set<String> reviewed) {
    final all = report.of(type);
    final visible = [
      for (final i in all)
        if (_showReviewed || !reviewed.contains(i.key)) i,
    ];
    final authOnly = type == AccountIssueType.authWithoutAccount ||
        type == AccountIssueType.accountWithoutAuth ||
        type == AccountIssueType.loginIndexMismatch;
    final open = all.where((i) => !reviewed.contains(i.key)).length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        initiallyExpanded: open > 0,
        leading: Icon(
          open == 0 ? Icons.check_circle_outline : Icons.warning_amber_rounded,
          color: open == 0 ? AppColors.success : AppColors.warning,
        ),
        title: Text(type.title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          authOnly && !report.authChecked
              ? 'Needs the account backend'
              : '$open open · ${all.length - open} reviewed',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(type.description,
                style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          ),
          if (type == AccountIssueType.missingOwnershipRecord && open > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _repairAllOwnership(all),
                  icon: const Icon(Icons.build_outlined, size: 18),
                  label: Text('Record ownership for all ${all.length}'),
                ),
              ),
            ),
          for (final issue in visible)
            ListTile(
              dense: true,
              title: Text(
                issue.mobile.isNotEmpty
                    ? '+91 ${issue.mobile}'
                    : issue.uids.isEmpty
                        ? issue.key
                        : issue.uids.join(', '),
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(issue.detail,
                  style: const TextStyle(fontSize: 12)),
              trailing: reviewed.contains(issue.key)
                  ? const Chip(
                      label: Text('Reviewed', style: TextStyle(fontSize: 10)))
                  : const Icon(Icons.chevron_right),
              onTap: () => _openIssue(issue, reviewed.contains(issue.key)),
            ),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text('Nothing to review.',
                  style: TextStyle(fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  Widget _missingProfiles(AccountScanReport report) {
    final uids = report.membersWithoutProfileUids;
    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        leading: const Icon(Icons.person_off_outlined, color: Colors.blueGrey),
        title: const Text('Missing profile records',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('${uids.length} signed-up members have no profile',
            style: const TextStyle(fontSize: 12)),
        children: [
          for (final uid in uids.take(200))
            ListTile(
              dense: true,
              title: Text(uid, style: const TextStyle(fontSize: 12.5)),
              trailing: TextButton(
                onPressed: () =>
                    context.push('/admin/user/$uid/create-profile'),
                child: const Text('Create profile'),
              ),
              onTap: () => context.push('/admin/user/$uid'),
            ),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  String get _adminUid =>
      ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ?? '';
  AdminAccountService get _service => ref.read(adminAccountServiceProvider);

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(text),
          backgroundColor: error ? AppColors.error : null));
  }

  Future<bool> _guard(Future<void> Function() action, String done) async {
    try {
      await action();
      _snack(done);
      _rescan();
      return true;
    } on AuthException catch (e) {
      _snack(e.message, error: true);
    } on LoginConflictException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('Action failed: $e', error: true);
    }
    return false;
  }

  Future<void> _repairAllOwnership(List<AccountIssue> issues) async {
    final ok = await confirmDestructiveAction(
      context,
      title: 'Record profile ownership?',
      facts: const [],
      explanation:
          'Writes the one-profile-per-account record for ${issues.length} '
          'account(s), each pointing at the ONE profile it already owns. No '
          'profile, login or other data is changed or deleted.',
      actionLabel: 'Record',
      typedConfirmation: false,
    );
    if (ok != true) return;
    await _guard(() async {
      for (final i in issues) {
        if (i.uids.length == 1 && i.profileIds.length == 1) {
          await _service.repairProfileOwner(i.uids.first, i.profileIds.first);
        }
      }
    }, 'Ownership recorded.');
  }

  Future<void> _openIssue(AccountIssue issue, bool isReviewed) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, controller) => _IssueSheet(
          issue: issue,
          isReviewed: isReviewed,
          scrollController: controller,
          onAction: (action) async {
            Navigator.pop(sheetContext);
            await action();
          },
          actions: _IssueActions(this),
        ),
      ),
    );
  }
}

/// The per-case actions, kept on the screen state so they share its snackbar,
/// rescan and admin identity.
class _IssueActions {
  final _AccountHealthScreenState s;
  _IssueActions(this.s);

  BuildContext get context => s.context;

  Future<void> markReviewed(AccountIssue issue, bool reviewed) => s._guard(
        () => reviewed
            ? s.ref.read(firestoreServiceProvider).clearAccountIssueReview(issue.key)
            : s.ref.read(firestoreServiceProvider).markAccountIssueReviewed(
                issue.key,
                adminUid: s._adminUid),
        reviewed ? 'Case re-opened.' : 'Marked as reviewed — left as is.',
      );

  Future<void> releaseNumber(AccountIssue issue) async {
    final ok = await confirmDestructiveAction(
      context,
      title: 'Release +91 ${issue.mobile}?',
      facts: const [],
      explanation:
          'Removes only the leftover mobile-number registration of a deleted '
          'login, so a new login can use the number. No account, profile or '
          'data is touched.',
      actionLabel: 'Release',
      typedConfirmation: false,
    );
    if (ok != true) return;
    await s._guard(
        () => s._service.releaseStaleNumber(issue.mobile, adminUid: s._adminUid),
        'Number released.');
  }

  Future<void> deleteLogin(ExistingLogin account, bool authChecked) async {
    final ok = await confirmDestructiveAction(
      context,
      title: 'Delete this login?',
      facts: [AccountFactsCard(account: account, authChecked: authChecked)],
      explanation:
          'The account can no longer sign in. Its profile and data are kept '
          'and the login can be restored from User Details.',
      actionLabel: 'Delete login',
    );
    if (ok != true) return;
    await s._guard(
        () async =>
            await s._service.deleteLogin(account.uid, adminUid: s._adminUid),
        'Login removed.');
  }

  Future<void> deleteUnlinkedAuth(ExistingLogin account) async {
    final ok = await confirmDestructiveAction(
      context,
      title: 'Delete unlinked Firebase login?',
      facts: [AccountFactsCard(account: account, authChecked: true)],
      explanation:
          'Nothing in the app belongs to this Firebase login. It is deleted '
          'permanently.',
      actionLabel: 'Delete',
    );
    if (ok != true) return;
    await s._guard(
        () async =>
            await s._service.deleteMember(account.uid, adminUid: s._adminUid),
        'Firebase login deleted.');
  }

  Future<void> deleteProfiles(AccountIssue issue) async {
    final ok = await confirmDestructiveAction(
      context,
      title: 'Delete ${issue.profileIds.length} orphaned profile(s)?',
      facts: const [],
      explanation:
          'These profiles belong to a login that no longer exists. They are '
          'deleted permanently. To keep them, restore the login instead.',
      actionLabel: 'Delete profiles',
    );
    if (ok != true) return;
    await s._guard(() async {
      for (final id in issue.profileIds) {
        await s.ref.read(firestoreServiceProvider).deleteProfileById(id);
      }
    }, 'Profiles deleted.');
  }

  Future<void> keepOneProfile(AccountIssue issue, String keepId) async {
    final others = [for (final id in issue.profileIds) if (id != keepId) id];
    final ok = await confirmDestructiveAction(
      context,
      title: 'Keep one profile?',
      facts: const [],
      explanation:
          'Keeps profile $keepId and PERMANENTLY deletes ${others.join(', ')}. '
          'The kept profile is recorded as this account\'s only profile.',
      actionLabel: 'Keep & delete others',
    );
    if (ok != true) return;
    await s._guard(
        () => s._service.keepOneProfile(issue.uids.first,
            keepProfileId: keepId,
            deleteProfileIds: others,
            adminUid: s._adminUid),
        'Duplicate profiles resolved.');
  }

  Future<void> restoreLogin(String uid) async {
    final mobile = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create login for this account'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Creates the login under the SAME Firebase UID, so the existing '
                'profile and data stay linked. Needs the account backend.',
                style: TextStyle(fontSize: 12.5),
              ),
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
                decoration:
                    const InputDecoration(labelText: 'E-mail (optional)'),
              ),
              TextFormField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: Validators.password,
              ),
            ],
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
            child: const Text('Create login'),
          ),
        ],
      ),
    );
    if (go != true) return;
    await s._guard(
        () async => await s._service.provisionMemberAccount(
              name: '',
              mobile: mobile.text,
              email: email.text,
              password: password.text,
              targetUid: uid,
            ),
        'Login created for the existing account.');
  }
}

class _IssueSheet extends ConsumerStatefulWidget {
  final AccountIssue issue;
  final bool isReviewed;
  final ScrollController scrollController;
  final Future<void> Function(Future<void> Function() action) onAction;
  final _IssueActions actions;

  const _IssueSheet({
    required this.issue,
    required this.isReviewed,
    required this.scrollController,
    required this.onAction,
    required this.actions,
  });

  @override
  ConsumerState<_IssueSheet> createState() => _IssueSheetState();
}

class _IssueSheetState extends ConsumerState<_IssueSheet> {
  late final Future<List<LoginInspection>> _accounts = Future.wait([
    for (final uid in widget.issue.uids)
      ref.read(adminAccountServiceProvider).inspectMember(uid,
          mobile: widget.issue.mobile),
  ]);
  String? _keep;

  AccountIssue get issue => widget.issue;

  @override
  Widget build(BuildContext context) {
    final a = widget.actions;
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 12),
        Text(issue.type.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(issue.type.description,
            style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
        const SizedBox(height: 8),
        if (issue.mobile.isNotEmpty) Text('Phone: +91 ${issue.mobile}'),
        if (issue.detail.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(issue.detail, style: const TextStyle(fontSize: 12.5)),
          ),
        const SizedBox(height: 12),
        FutureBuilder<List<LoginInspection>>(
          future: _accounts,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Text('Could not load the accounts: ${snap.error}');
            }
            final inspections = snap.data ?? const [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final inspection in inspections)
                  for (final account in inspection.accounts)
                    if (issue.uids.contains(account.uid)) ...[
                      AccountFactsCard(
                          account: account,
                          authChecked: inspection.authChecked),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (account.hasAccountRecord)
                            TextButton(
                              onPressed: () => widget.onAction(() async =>
                                  context.push('/admin/user/${account.uid}')),
                              child: const Text('Open account'),
                            ),
                          if (issue.type == AccountIssueType.duplicatePhone &&
                              account.isLive &&
                              account.access.canSignIn)
                            TextButton(
                              onPressed: () => widget.onAction(() =>
                                  a.deleteLogin(account, inspection.authChecked)),
                              style: TextButton.styleFrom(
                                  foregroundColor: AppColors.error),
                              child: const Text('Delete this login'),
                            ),
                          if (issue.type == AccountIssueType.authWithoutAccount &&
                              inspection.authChecked)
                            TextButton(
                              onPressed: () => widget
                                  .onAction(() => a.deleteUnlinkedAuth(account)),
                              style: TextButton.styleFrom(
                                  foregroundColor: AppColors.error),
                              child: const Text('Delete Firebase login'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
              ],
            );
          },
        ),
        if (issue.type == AccountIssueType.multipleProfiles) ...[
          const Text('Choose the profile to KEEP:',
              style: TextStyle(fontWeight: FontWeight.w600)),
          for (final id in issue.profileIds)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _keep == id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: AppColors.primary,
              ),
              title: Text(id),
              trailing: TextButton(
                onPressed: () => widget
                    .onAction(() async => context.push('/profile/$id')),
                child: const Text('View'),
              ),
              onTap: () => setState(() => _keep = id),
            ),
          ElevatedButton(
            onPressed: _keep == null
                ? null
                : () => widget.onAction(() => a.keepOneProfile(issue, _keep!)),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: const Text('Keep selected, delete the others'),
          ),
        ],
        if (issue.type == AccountIssueType.staleLoginIndex)
          ElevatedButton.icon(
            onPressed: () => widget.onAction(() => a.releaseNumber(issue)),
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Release the number'),
          ),
        if (issue.type == AccountIssueType.profileWithoutAccount) ...[
          ElevatedButton.icon(
            onPressed: () =>
                widget.onAction(() => a.restoreLogin(issue.uids.first)),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Create login for this profile (same UID)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => widget.onAction(() => a.deleteProfiles(issue)),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete the orphaned profile(s)'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
          ),
        ],
        if (issue.type == AccountIssueType.accountWithoutAuth)
          ElevatedButton.icon(
            onPressed: () =>
                widget.onAction(() => a.restoreLogin(issue.uids.first)),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Create login (same UID)'),
          ),
        if (issue.type == AccountIssueType.missingOwnershipRecord)
          ElevatedButton.icon(
            onPressed: () => widget.onAction(() async {
              await widget.actions.s._guard(
                  () => ref.read(adminAccountServiceProvider).repairProfileOwner(
                      issue.uids.first, issue.profileIds.first),
                  'Ownership recorded.');
            }),
            icon: const Icon(Icons.build_outlined),
            label: const Text('Record ownership'),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () =>
              widget.onAction(() => a.markReviewed(issue, widget.isReviewed)),
          icon: Icon(widget.isReviewed ? Icons.undo : Icons.done_all),
          label: Text(widget.isReviewed
              ? 'Re-open this case'
              : 'Mark reviewed — leave as is'),
        ),
      ],
    );
  }
}
