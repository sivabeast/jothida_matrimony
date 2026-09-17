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
import '../../models/password_reset_request.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/firebase/admin_account_service.dart';
import '../../widgets/admin/account_access_card.dart';
import '../../widgets/admin/login_conflict_dialog.dart';

final _resetRequestsProvider =
    StreamProvider.autoDispose<List<PasswordResetRequest>>((ref) =>
        ref.read(passwordResetRequestServiceProvider).watchAll());

/// The account(s) that hold a request's mobile number — resolved by the ADMIN,
/// never supplied by the requester.
final _requestAccountsProvider = FutureProvider.autoDispose
    .family<LoginInspection, String>((ref, mobile) =>
        ref.read(adminAccountServiceProvider).inspectMobile(mobile));

/// Admin → Password Reset Requests (admin-assisted recovery).
///
/// A member who cannot recover by OTP files a request with their registered
/// number and a short description — never a password or OTP. The admin:
///
///  1. opens a pending request and marks it Under Review;
///  2. verifies the person (call / WhatsApp the REGISTERED number);
///  3. identifies the account — resolved here from the number, with UID,
///     profile and account status;
///  4. resets securely: a Firebase reset e-mail to a real address, or a
///     one-time temporary password (backend) that the member must change at
///     next sign-in;
///  5. marks it Resolved — or Rejected with a note.
class PasswordResetRequestsScreen extends ConsumerStatefulWidget {
  const PasswordResetRequestsScreen({super.key});

  @override
  ConsumerState<PasswordResetRequestsScreen> createState() =>
      _PasswordResetRequestsScreenState();
}

class _PasswordResetRequestsScreenState
    extends ConsumerState<PasswordResetRequestsScreen> {
  PasswordResetStatus? _filter = PasswordResetStatus.pending;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_resetRequestsProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                _filterChip(null, 'All', async.valueOrNull),
                for (final s in PasswordResetStatus.values)
                  _filterChip(s, s.label, async.valueOrNull),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load requests: $e',
                      textAlign: TextAlign.center),
                ),
              ),
              data: (all) {
                final list = [
                  for (final r in all)
                    if (_filter == null || r.status == _filter) r,
                ];
                if (list.isEmpty) {
                  return const Center(child: Text('No requests.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _RequestCard(request: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(PasswordResetStatus? status, String label,
      List<PasswordResetRequest>? all) {
    final count =
        all?.where((r) => status == null || r.status == status).length;
    final selected = _filter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(count == null ? label : '$label ($count)'),
        selected: selected,
        showCheckmark: false,
        selectedColor: AppColors.primary.withValues(alpha: 0.14),
        onSelected: (_) => setState(() => _filter = status),
      ),
    );
  }
}

Color _statusColor(PasswordResetStatus s) => switch (s) {
      PasswordResetStatus.pending => AppColors.warning,
      PasswordResetStatus.underReview => AppColors.info,
      PasswordResetStatus.resolved => AppColors.success,
      PasswordResetStatus.rejected => AppColors.error,
    };

class _RequestCard extends ConsumerStatefulWidget {
  final PasswordResetRequest request;
  const _RequestCard({required this.request});

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _expanded = false;
  bool _busy = false;

  PasswordResetRequest get r => widget.request;
  String get _adminUid =>
      ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ?? '';

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(text),
          backgroundColor: error ? AppColors.error : null));
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      _snack(done);
    } on AuthException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      debugPrint('[Admin] action failed: $e');
      _snack(describeAdminActionError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _note(String title, {bool required = false}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: c,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: required ? 'Note (required)' : 'Note (optional)',
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: required && c.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setStatus(PasswordResetStatus status,
      {bool askNote = false, bool noteRequired = false, String resolution = ''}) async {
    var note = '';
    if (askNote) {
      final entered = await _note('${status.label} — note', required: noteRequired);
      if (entered == null) return;
      note = entered;
    }
    await _run(
      () => ref.read(passwordResetRequestServiceProvider).updateStatus(
            r.id,
            status: status,
            adminUid: _adminUid,
            note: note,
            resolution: resolution,
          ),
      'Request marked ${status.label}.',
    );
  }

  Future<void> _sendResetEmail(ExistingLogin account) async {
    final email = LoginIdentifier.realEmailOrEmpty(account.email);
    if (email.isEmpty) return;
    final ok = await confirmDestructiveAction(
      context,
      title: 'Send a password reset e-mail?',
      facts: [AccountFactsCard(account: account, authChecked: false)],
      explanation:
          'Firebase sends its reset link to ${maskEmail(email)} — the address '
          'registered on the account, never one given in the request.',
      actionLabel: 'Send',
      typedConfirmation: false,
    );
    if (ok != true) return;
    await _run(() async {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      await ref.read(passwordResetRequestServiceProvider).updateStatus(r.id,
          status: PasswordResetStatus.resolved,
          adminUid: _adminUid,
          note: 'Reset e-mail sent to the registered address',
          resolution: 'reset-email');
    }, 'Reset e-mail sent and the request resolved.');
  }

  Future<void> _temporaryPassword(ExistingLogin account, bool authChecked) async {
    final ok = await confirmDestructiveAction(
      context,
      title: 'Set a temporary password?',
      facts: [AccountFactsCard(account: account, authChecked: authChecked)],
      explanation:
          'Only after you have verified the person through the REGISTERED '
          'number. A one-time password is shown once; every session is signed '
          'out and the member must set a new password at next sign-in. The '
          'request is resolved automatically.',
      actionLabel: 'Generate',
      typedConfirmation: false,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final temp = await ref
          .read(adminAccountServiceProvider)
          .setTemporaryPassword(account.uid, requestId: r.id);
      if (!mounted) return;
      await showTemporaryPasswordDialog(context,
          mobile: r.mobile, password: temp, memberName: account.name);
    } on AuthException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      debugPrint('[Admin] action failed: $e');
      _snack(describeAdminActionError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(r.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: r.needsReview
            ? Border.all(color: AppColors.alertHigh, width: 1.2)
            : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('+91 ${r.mobile}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(r.status.label.toUpperCase(),
                    style: TextStyle(
                        color: color,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onLongPress: () => Clipboard.setData(ClipboardData(text: r.id)),
            child: Text('Request ${r.id} · ${_date(r.createdAt)}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
          ),
          if (r.name.isNotEmpty)
            Text('Name given: ${r.name}', style: const TextStyle(fontSize: 13)),
          if (r.needsReview)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'OTP recovery refused: this number belongs to more than one '
                'profile. Resolve it in Account Health.',
                style: TextStyle(fontSize: 12.5, color: AppColors.alertHigh),
              ),
            ),
          if (r.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(r.description, style: const TextStyle(fontSize: 13)),
            ),
          if (r.adminNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Admin note: ${r.adminNote}',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                label: Text(_expanded ? 'Hide account' : 'Identify account'),
              ),
              const Spacer(),
              if (_busy)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          if (_expanded) _accountSection(),
          const Divider(),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (r.status == PasswordResetStatus.pending)
                _btn('Under review', Icons.visibility_outlined,
                    () => _setStatus(PasswordResetStatus.underReview)),
              _btn('Call', Icons.call_outlined,
                  () => launchUrl(phoneCallUri(r.mobile))),
              _btn('WhatsApp', Icons.chat_outlined,
                  () => launchUrl(whatsappUri(r.mobile),
                      mode: LaunchMode.externalApplication)),
              if (r.status.isOpen) ...[
                _btn('Resolve', Icons.check_circle_outline,
                    () => _setStatus(PasswordResetStatus.resolved,
                        askNote: true, resolution: 'manual')),
                _btn('Reject', Icons.block_outlined,
                    () => _setStatus(PasswordResetStatus.rejected,
                        askNote: true, noteRequired: true),
                    danger: true),
              ] else
                _btn('Re-open', Icons.undo,
                    () => _setStatus(PasswordResetStatus.underReview)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountSection() {
    final async = ref.watch(_requestAccountsProvider(r.mobile));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('Could not identify the account: $e',
          style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
      data: (inspection) {
        final live = inspection.liveAccounts;
        if (live.isEmpty) {
          return const Text(
            'No live account uses this number. Do not reset anything — reject '
            'the request, or check Account Health.',
            style: TextStyle(fontSize: 12.5),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (live.length > 1)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'More than one account uses this number. Verify WHICH one '
                  'belongs to the person before resetting anything.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.alertHigh),
                ),
              ),
            for (final account in live) ...[
              AccountFactsCard(
                  account: account, authChecked: inspection.authChecked),
              Wrap(
                spacing: 6,
                children: [
                  TextButton(
                    onPressed: () => context.push('/admin/user/${account.uid}'),
                    child: const Text('Open account'),
                  ),
                  if (r.status.isOpen &&
                      LoginIdentifier.realEmailOrEmpty(account.email).isNotEmpty)
                    TextButton(
                      onPressed: _busy ? null : () => _sendResetEmail(account),
                      child: const Text('Send reset e-mail'),
                    ),
                  if (r.status.isOpen)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _temporaryPassword(
                              account, inspection.authChecked),
                      child: const Text('Temporary password'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ],
        );
      },
    );
  }

  Widget _btn(String label, IconData icon, VoidCallback onTap,
          {bool danger = false}) =>
      OutlinedButton.icon(
        onPressed: _busy ? null : onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12.5)),
        style: OutlinedButton.styleFrom(
          foregroundColor: danger ? AppColors.error : AppColors.primary,
          side: BorderSide(
              color: danger ? AppColors.error : AppColors.primary),
          visualDensity: VisualDensity.compact,
        ),
      );
}
