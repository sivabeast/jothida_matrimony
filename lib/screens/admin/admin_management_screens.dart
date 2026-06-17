import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/dev_config.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_account_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/data_states.dart';

/// Admin management section screens, registered under the admin ShellRoute:
///   /admin/astrologers · /admin/ratings · /admin/banners
///   /admin/premium · /admin/analytics · /admin/settings
///
/// These provide the navigable Super Admin sections requested for the
/// dashboard. Sections backed by existing providers (Analytics) show live
/// data; the rest present their actions and are ready to be wired to backend
/// queries/mutations.

// ─────────────────────────────────────────────────────────────────────────────
// Shared building blocks
// ─────────────────────────────────────────────────────────────────────────────

Widget _adminScaffold({
  required String title,
  required IconData icon,
  required String subtitle,
  required List<Widget> children,
}) {
  return Scaffold(
    backgroundColor: AppColors.scaffoldBg,
    appBar: AppBar(
      title: Text(title),
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AdminHeader(icon: icon, title: title, subtitle: subtitle),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}

class _AdminHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _AdminHeader(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.gold, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: c.withOpacity(0.12),
          child: Icon(icon, color: c),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }
}

/// Neutral "coming soon" notice for sections that are navigable but not yet
/// built out. Deliberately worded so it never reads like a backend/connection
/// error to the admin.
void _soon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$feature is coming soon.')));
}

// ─────────────────────────────────────────────────────────────────────────────
// 🔮 Astrologer Management
// ─────────────────────────────────────────────────────────────────────────────

/// Astrologer verification + management, split into two tabs:
///   ⏳ Pending Verification  (status != approved)
///   ✅ Verified Astrologers  (status == approved)
/// Reads the `astrologers` collection in realtime, supports search by name /
/// location / specialization, a full details modal, a zoomable certificate
/// viewer, and Approve / Reject / Suspend / Remove-Verification actions that
/// write `status` back to Firestore (the lists re-bucket automatically).
class AstrologerManagementScreen extends ConsumerStatefulWidget {
  const AstrologerManagementScreen({super.key});

  @override
  ConsumerState<AstrologerManagementScreen> createState() =>
      _AstrologerManagementScreenState();
}

class _AstrologerManagementScreenState
    extends ConsumerState<AstrologerManagementScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(AstrologerAccount a) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final loc = [a.city, a.state, a.country].join(' ').toLowerCase();
    return a.fullName.toLowerCase().contains(q) ||
        a.mobile.toLowerCase().contains(q) ||
        a.email.toLowerCase().contains(q) ||
        loc.contains(q) ||
        a.expertise.any((e) => e.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[Admin] AstrologerManagement build — /admin/astrologers');

    // Role guard (defence in depth — the router already blocks non-admins).
    final isAdmin = kBypassAuth ||
        (ref.watch(currentUserProvider).valueOrNull?.isAdmin ?? false);
    if (!isAdmin) {
      debugPrint('[Admin] ⛔ non-admin blocked from Astrologer Management');
      return Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: const Text('Astrologer Management'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: const EmptyState(
          icon: Icons.lock_outline,
          message: 'Permission Denied\nOnly an admin can manage astrologers.',
        ),
      );
    }

    final astrologersAsync = ref.watch(allAstrologersProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: const Text('Astrologer Management'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          bottom: TabBar(
            indicatorColor: AppColors.gold,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(text: '⏳ Pending Verification'),
              Tab(text: '✅ Verified'),
            ],
          ),
        ),
        body: Column(
          children: [
            _searchBar(),
            Expanded(
              child: astrologersAsync.when(
                loading: () =>
                    const LoadingState(message: 'Loading astrologers...'),
                error: (e, st) {
                  debugPrint('[Admin] ❌ astrologers load failed: $e');
                  return ErrorStateView(
                    message: 'Connection Error — unable to load astrologers.',
                    onRetry: () => ref.invalidate(allAstrologersProvider),
                  );
                },
                data: (list) {
                  debugPrint('[Admin] loaded ${list.length} astrologers');
                  final pending = list
                      .where((a) =>
                          a.status != VerificationStatus.approved &&
                          _matches(a))
                      .toList();
                  final verified = list
                      .where((a) =>
                          a.status == VerificationStatus.approved &&
                          _matches(a))
                      .toList();
                  return TabBarView(
                    children: [
                      _tabList(
                        items: pending,
                        emptyIcon: Icons.hourglass_empty,
                        emptyMsg: _query.isEmpty
                            ? 'No astrologers awaiting verification'
                            : 'No pending astrologers match "$_query"',
                        builder: (a) => _PendingCard(
                            account: a, onView: () => _showDetails(a)),
                      ),
                      _tabList(
                        items: verified,
                        emptyIcon: Icons.verified_outlined,
                        emptyMsg: _query.isEmpty
                            ? 'No verified astrologers yet'
                            : 'No verified astrologers match "$_query"',
                        builder: (a) => _VerifiedCard(
                            account: a, onView: () => _showDetails(a)),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabList({
    required List<AstrologerAccount> items,
    required IconData emptyIcon,
    required String emptyMsg,
    required Widget Function(AstrologerAccount) builder,
  }) {
    if (items.isEmpty) {
      return EmptyState(icon: emptyIcon, message: emptyMsg);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: items.length,
      itemBuilder: (_, i) => builder(items[i]),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search name, phone, email, location…',
          prefixIcon: const Icon(Icons.search, color: AppColors.primary),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    _query = '';
                    _searchCtrl.clear();
                  }),
                ),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
          ),
        ),
      ),
    );
  }

  void _showDetails(AstrologerAccount account) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AstrologerDetailsSheet(account: account),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared action helpers (used by cards + details sheet)
// ─────────────────────────────────────────────────────────────────────────────

/// Maps a raw error to a short, user-facing label.
String _friendlyError(Object? e) {
  if (e is FirebaseException) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permission Denied — you cannot perform this action.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Connection Error — please check your network and try again.';
      case 'not-found':
        return 'This astrologer record no longer exists.';
    }
  }
  return 'Could not complete the action. Please try again.';
}

/// Runs an admin action and shows a success/error SnackBar.
Future<void> _runAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action,
  String successMsg,
) async {
  final messenger = ScaffoldMessenger.of(context);
  await action();
  final result = ref.read(adminActionsProvider);
  messenger.hideCurrentSnackBar();
  if (result.hasError) {
    messenger.showSnackBar(SnackBar(
      content: Text(_friendlyError(result.error)),
      backgroundColor: AppColors.error,
    ));
  } else {
    messenger.showSnackBar(SnackBar(content: Text(successMsg)));
  }
}

/// Prompts for an optional reason, then rejects the astrologer. [title] /
/// [actionLabel] let the same dialog serve both "Reject" and "Suspend".
Future<void> _confirmReject(
  BuildContext context,
  WidgetRef ref,
  AstrologerAccount account, {
  String title = 'Reject Astrologer',
  String actionLabel = 'Reject',
  String successMsg = 'Astrologer rejected.',
}) async {
  final controller = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Reason (optional — shown to the astrologer)',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
  if (reason == null) return; // cancelled
  if (!context.mounted) return;
  await _runAction(
    context,
    ref,
    () => ref
        .read(adminActionsProvider.notifier)
        .rejectAstrologer(account.id, reason: reason),
    successMsg,
  );
}

String _accountLocation(AstrologerAccount a) =>
    [a.city, a.state].where((s) => s.trim().isNotEmpty).join(', ');

String _fmtDate(DateTime? d) => d == null
    ? '—'
    : '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

// ─────────────────────────────────────────────────────────────────────────────
// Pending astrologer card
// ─────────────────────────────────────────────────────────────────────────────

class _PendingCard extends ConsumerWidget {
  final AstrologerAccount account;
  final VoidCallback onView;
  const _PendingCard({required this.account, required this.onView});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(adminActionsProvider).isLoading;
    final rejected = account.status == VerificationStatus.rejected;
    final statusColor = rejected ? AppColors.error : AppColors.warning;
    final location = _accountLocation(account);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onView,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _largeAvatar(account),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.fullName.isEmpty ? '(no name)' : account.fullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      if (account.expertise.isNotEmpty)
                        _cardLine(Icons.auto_awesome, account.expertise.first,
                            iconColor: AppColors.gold,
                            textColor: AppColors.primary),
                      if (location.isNotEmpty)
                        _cardLine(Icons.location_on_outlined, location),
                      _cardLine(Icons.schedule,
                          '${account.experienceYears} years experience'),
                      const SizedBox(height: 10),
                      _statusChip(account.status.label, statusColor),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _IconAction(
                icon: Icons.visibility_outlined,
                color: AppColors.primary,
                tooltip: 'View details',
                onTap: onView,
              ),
              const SizedBox(width: 12),
              if (!rejected) ...[
                _IconAction(
                  icon: Icons.close,
                  color: AppColors.error,
                  tooltip: 'Reject',
                  onTap:
                      busy ? null : () => _confirmReject(context, ref, account),
                ),
                const SizedBox(width: 12),
              ],
              _IconAction(
                icon: Icons.check,
                color: AppColors.success,
                tooltip: 'Approve',
                filled: true,
                onTap: busy
                    ? null
                    : () => _runAction(
                          context,
                          ref,
                          () => ref
                              .read(adminActionsProvider.notifier)
                              .approveAstrologer(account.id),
                          'Astrologer approved & verified.',
                        ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Verified astrologer card
// ─────────────────────────────────────────────────────────────────────────────

class _VerifiedCard extends ConsumerWidget {
  final AstrologerAccount account;
  final VoidCallback onView;
  const _VerifiedCard({required this.account, required this.onView});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(adminActionsProvider).isLoading;
    final location = _accountLocation(account);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onView,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _largeAvatar(account),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                                account.fullName.isEmpty
                                    ? '(no name)'
                                    : account.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.verified,
                              color: AppColors.success, size: 17),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.star, size: 14, color: AppColors.gold),
                        const SizedBox(width: 4),
                        Text(account.rating.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text('  ·  ${account.reviewCount} reviews',
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.grey[500])),
                      ]),
                      if (account.expertise.isNotEmpty)
                        _cardLine(Icons.auto_awesome, account.expertise.first,
                            iconColor: AppColors.gold,
                            textColor: AppColors.primary),
                      if (location.isNotEmpty)
                        _cardLine(Icons.location_on_outlined, location),
                      _cardLine(Icons.schedule,
                          '${account.experienceYears} years  ·  ₹${account.consultationFee.toStringAsFixed(0)}'),
                      const SizedBox(height: 10),
                      _statusChip('✅ Verified Astrologer', AppColors.success),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _IconAction(
                icon: Icons.visibility_outlined,
                color: AppColors.primary,
                tooltip: 'View details',
                onTap: onView,
              ),
              const SizedBox(width: 12),
              _IconAction(
                icon: Icons.pause_circle_outline,
                color: AppColors.error,
                tooltip: 'Suspend',
                onTap: busy
                    ? null
                    : () => _confirmReject(
                          context,
                          ref,
                          account,
                          title: 'Suspend Astrologer',
                          actionLabel: 'Suspend',
                          successMsg:
                              'Astrologer suspended — hidden from users.',
                        ),
              ),
              const SizedBox(width: 12),
              _IconAction(
                icon: Icons.gpp_maybe_outlined,
                color: AppColors.warning,
                tooltip: 'Remove verification',
                onTap: busy
                    ? null
                    : () => _runAction(
                          context,
                          ref,
                          () => ref
                              .read(adminActionsProvider.notifier)
                              .suspendAstrologer(account.id),
                          'Verification removed — back to pending.',
                        ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _avatar(AstrologerAccount account, double radius) => CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withOpacity(0.1),
      backgroundImage:
          account.photoUrl.isNotEmpty ? NetworkImage(account.photoUrl) : null,
      child: account.photoUrl.isEmpty
          ? Text(
              account.fullName.isNotEmpty
                  ? account.fullName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.7))
          : null,
    );

Widget _statusChip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
    );

/// Large rounded-square profile image (~84px) with a coloured initial fallback.
Widget _largeAvatar(AstrologerAccount account, {double size = 84}) {
  final initial =
      account.fullName.isNotEmpty ? account.fullName[0].toUpperCase() : '?';
  return ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: SizedBox(
      width: size,
      height: size,
      child: account.photoUrl.isNotEmpty
          ? Image.network(
              account.photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _avatarFallback(initial, size),
            )
          : _avatarFallback(initial, size),
    ),
  );
}

Widget _avatarFallback(String initial, double size) => Container(
      color: AppColors.primary.withOpacity(0.10),
      alignment: Alignment.center,
      child: Text(initial,
          style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: size * 0.4)),
    );

/// One compact icon + text line used in the card info column.
Widget _cardLine(IconData icon, String text, {Color? iconColor, Color? textColor}) =>
    Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 13, color: iconColor ?? Colors.grey[500]),
          const SizedBox(width: 5),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5, color: textColor ?? Colors.grey[600])),
          ),
        ],
      ),
    );

/// A rounded, icon-only action button. [filled] gives it a solid colour fill
/// (used for the primary "Approve" action); otherwise it's a soft tinted
/// circle. A null [onTap] renders it disabled (greyed).
class _IconAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final bool filled;
  final VoidCallback? onTap;
  const _IconAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.filled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final base = enabled ? color : Colors.grey;
    final bg = filled ? base : base.withOpacity(0.12);
    final fg = filled ? Colors.white : base;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, color: fg, size: 22),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Details modal
// ─────────────────────────────────────────────────────────────────────────────

class _AstrologerDetailsSheet extends ConsumerWidget {
  final AstrologerAccount account;
  const _AstrologerDetailsSheet({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = account;
    final busy = ref.watch(adminActionsProvider).isLoading;
    final approved = a.status == VerificationStatus.approved;
    final hasCert = a.certFileName.trim().isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.scaffoldBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(3)),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _avatar(a, 36),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.fullName.isEmpty ? '(no name)' : a.fullName,
                                style: const TextStyle(
                                    fontSize: 19,
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            if (approved)
                              _statusChip('✅ Verified Astrologer',
                                  AppColors.success)
                            else
                              _statusChip(a.status.label,
                                  a.status == VerificationStatus.rejected
                                      ? AppColors.error
                                      : AppColors.warning),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _info(Icons.email_outlined, 'Email', a.email),
                  _info(Icons.phone_outlined, 'Mobile', a.mobile),
                  _info(Icons.location_on_outlined, 'Location',
                      _accountLocation(a)),
                  _info(Icons.language_outlined, 'Languages',
                      a.languages.isEmpty ? '—' : a.languages.join(', ')),
                  _info(Icons.auto_awesome_outlined, 'Specializations',
                      a.expertise.isEmpty ? '—' : a.expertise.join(', ')),
                  _info(Icons.work_history_outlined, 'Experience',
                      '${a.experienceYears} years'),
                  _info(Icons.currency_rupee, 'Consultation Fee',
                      '₹${a.consultationFee.toStringAsFixed(0)}'),
                  _info(Icons.event_outlined, 'Registered',
                      _fmtDate(a.createdAt)),
                  const SizedBox(height: 14),
                  const Text('📝 About',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.primary)),
                  const SizedBox(height: 6),
                  Text(a.about.trim().isEmpty ? 'No description provided.' : a.about,
                      style: const TextStyle(height: 1.5, fontSize: 13.5)),
                  const SizedBox(height: 18),
                  const Text('📄 Certificate',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.primary)),
                  const SizedBox(height: 8),
                  _CertificateBlock(account: a, hasCert: hasCert),
                  const SizedBox(height: 22),
                  _sheetActions(context, ref, approved, busy),
                  const SizedBox(height: 10),
                  // Permanent delete — hard cleanup, removes the astrologer
                  // everywhere (no soft-delete).
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed:
                          busy ? null : () => _confirmDelete(context, ref),
                      icon: const Icon(Icons.delete_forever, size: 18),
                      label: const Text('Delete Permanently'),
                      style:
                          TextButton.styleFrom(foregroundColor: AppColors.error),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Astrologer'),
        content: Text(
          'Permanently delete ${account.fullName.isEmpty ? 'this astrologer' : account.fullName}? '
          'Their profile, certificates, consultation requests and all reviews '
          'will be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _runAction(
      context,
      ref,
      () => ref.read(adminActionsProvider.notifier).deleteAstrologer(account.id),
      'Astrologer deleted permanently.',
    );
    if (context.mounted) Navigator.pop(context); // close the details sheet
  }

  Widget _sheetActions(
      BuildContext context, WidgetRef ref, bool approved, bool busy) {
    if (approved) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      await _confirmReject(context, ref, account,
                          title: 'Suspend Astrologer',
                          actionLabel: 'Suspend',
                          successMsg: 'Astrologer suspended — hidden from users.');
                      if (context.mounted) Navigator.pop(context);
                    },
              icon: const Icon(Icons.pause_circle_outline, size: 18),
              label: const Text('Suspend'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  minimumSize: const Size.fromHeight(48)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      await _runAction(
                          context,
                          ref,
                          () => ref
                              .read(adminActionsProvider.notifier)
                              .suspendAstrologer(account.id),
                          'Verification removed — back to pending.');
                      if (context.mounted) Navigator.pop(context);
                    },
              icon: const Icon(Icons.gpp_maybe_outlined, size: 18),
              label: const Text('Remove Verification'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48)),
            ),
          ),
        ],
      );
    }
    // Pending / rejected → Reject + Approve
    final rejected = account.status == VerificationStatus.rejected;
    return Row(
      children: [
        if (!rejected) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      await _confirmReject(context, ref, account);
                      if (context.mounted) Navigator.pop(context);
                    },
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Reject'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  minimumSize: const Size.fromHeight(48)),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: ElevatedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    await _runAction(
                        context,
                        ref,
                        () => ref
                            .read(adminActionsProvider.notifier)
                            .approveAstrologer(account.id),
                        'Astrologer approved & verified.');
                    if (context.mounted) Navigator.pop(context);
                  },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Approve'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ],
    );
  }

  Widget _info(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: AppColors.primary),
            const SizedBox(width: 10),
            SizedBox(
                width: 104,
                child: Text(label,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12.5))),
            Expanded(
                child: Text(value.trim().isEmpty ? '—' : value,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w500))),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Certificate block + viewer
// ─────────────────────────────────────────────────────────────────────────────

class _CertificateBlock extends StatelessWidget {
  final AstrologerAccount account;
  final bool hasCert;
  const _CertificateBlock({required this.account, required this.hasCert});

  Future<void> _download(BuildContext context) async {
    final uri = Uri.tryParse(account.certFileName);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the certificate link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!hasCert) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: Colors.grey[500]),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No certificate uploaded by this astrologer.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }
    final certMeta = [
      if (account.certName.isNotEmpty) account.certName,
      if (account.certOrg.isNotEmpty) account.certOrg,
      if (account.certNumber.isNotEmpty) 'No. ${account.certNumber}',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  certMeta.isEmpty ? 'Uploaded certificate' : certMeta,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => _CertificateViewer(
                        url: account.certFileName, name: account.fullName),
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _download(context),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Download'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Full-screen zoomable certificate viewer (image). For PDFs / non-image URLs
/// the inline preview fails gracefully and the admin can open it externally.
class _CertificateViewer extends StatelessWidget {
  final String url;
  final String name;
  const _CertificateViewer({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(name.isEmpty ? 'Certificate' : '$name · Certificate',
              style: const TextStyle(fontSize: 15)),
          actions: [
            IconButton(
              tooltip: 'Open / Download',
              icon: const Icon(Icons.open_in_new),
              onPressed: () async {
                final uri = Uri.tryParse(url);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
        body: PhotoView(
          imageProvider: NetworkImage(url),
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 4,
          loadingBuilder: (_, __) => const Center(
              child: CircularProgressIndicator(color: Colors.white)),
          errorBuilder: (_, __, ___) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.picture_as_pdf_outlined,
                    color: Colors.white54, size: 64),
                const SizedBox(height: 12),
                const Text(
                  'Preview not available (file may be a PDF).',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(url);
                    if (uri != null) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open externally'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ⭐ Rating Management
// ─────────────────────────────────────────────────────────────────────────────

class RatingManagementScreen extends StatelessWidget {
  const RatingManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[Admin] RatingManagement build — /admin/ratings');
    return _adminScaffold(
      title: 'Rating Management',
      icon: Icons.star_rate_rounded,
      subtitle: 'View and moderate user ratings',
      children: [
        _ActionTile(
          icon: Icons.reviews_outlined,
          title: 'View All Ratings',
          subtitle: 'See every rating left on the platform',
          onTap: () => _soon(context, 'View All Ratings'),
        ),
        _ActionTile(
          icon: Icons.gavel_outlined,
          title: 'Moderate Ratings',
          subtitle: 'Hide or remove inappropriate ratings',
          color: AppColors.error,
          onTap: () => _soon(context, 'Moderate Ratings'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 📢 Banner Management (working in-memory demo)
// ─────────────────────────────────────────────────────────────────────────────

class BannerManagementScreen extends StatefulWidget {
  const BannerManagementScreen({super.key});

  @override
  State<BannerManagementScreen> createState() => _BannerManagementScreenState();
}

class _BannerManagementScreenState extends State<BannerManagementScreen> {
  // In-memory list (demo). Wire to Firestore `banners` collection to persist.
  final List<String> _banners = [
    'Perfect Match · Written in the Stars',
    'Find Your Life Partner',
  ];

  Future<void> _edit({int? index}) async {
    final controller =
        TextEditingController(text: index == null ? '' : _banners[index]);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index == null ? 'Add Banner' : 'Edit Banner'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Banner title / image label',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    setState(() {
      if (index == null) {
        _banners.add(result);
      } else {
        _banners[index] = result;
      }
    });
  }

  void _delete(int index) {
    setState(() => _banners.removeAt(index));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Banner deleted')));
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[Admin] BannerManagement build — /admin/banners');
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Banner Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add Banner'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _AdminHeader(
            icon: Icons.view_carousel,
            title: 'Banner Management',
            subtitle: 'Add, edit and delete home banners',
          ),
          const SizedBox(height: 16),
          if (_banners.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No banners. Tap “Add Banner”.')),
            ),
          ..._banners.asMap().entries.map((e) {
            final i = e.key;
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x22800020),
                  child: Icon(Icons.image_outlined, color: AppColors.primary),
                ),
                title: Text(e.value,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          color: AppColors.primary),
                      onPressed: () => _edit(index: i),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.error),
                      onPressed: () => _delete(i),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 💎 Premium Management
// ─────────────────────────────────────────────────────────────────────────────

class PremiumManagementScreen extends StatelessWidget {
  const PremiumManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[Admin] PremiumManagement build — /admin/premium');
    return _adminScaffold(
      title: 'Premium Management',
      icon: Icons.workspace_premium,
      subtitle: 'Premium users and subscriptions',
      children: [
        _ActionTile(
          icon: Icons.people_alt_outlined,
          title: 'View Premium Users',
          subtitle: 'List members on a paid plan',
          color: AppColors.gold,
          onTap: () => _soon(context, 'View Premium Users'),
        ),
        _ActionTile(
          icon: Icons.card_membership_outlined,
          title: 'Manage Subscriptions',
          subtitle: 'Extend, refund or cancel subscriptions',
          onTap: () => _soon(context, 'Manage Subscriptions'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 📈 Analytics (live stats from adminStatsProvider)
// ─────────────────────────────────────────────────────────────────────────────

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[Admin] Analytics build — /admin/analytics');
    final statsAsync = ref.watch(adminStatsProvider);
    return _adminScaffold(
      title: 'Analytics',
      icon: Icons.insights,
      subtitle: 'Users, growth and revenue',
      children: [
        statsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: LoadingState(),
          ),
          error: (e, _) {
            debugPrint('[Admin] analytics stats load failed: $e');
            return const Padding(
              padding: EdgeInsets.all(24),
              child: ErrorStateView(message: 'No analytics data available.'),
            );
          },
          data: (s) => Column(
            children: [
              Row(children: [
                Expanded(
                    child: _MiniStat('Total Users', '${s['totalUsers'] ?? 0}',
                        Icons.people, Colors.blue)),
                const SizedBox(width: 12),
                Expanded(
                    child: _MiniStat('New Registrations',
                        '${s['newToday'] ?? s['totalUsers'] ?? 0}',
                        Icons.person_add, AppColors.success)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _MiniStat('Profiles', '${s['totalProfiles'] ?? 0}',
                        Icons.badge_outlined, AppColors.primary)),
                const SizedBox(width: 12),
                Expanded(
                    child: _MiniStat('Revenue (₹)', '${s['revenue'] ?? 0}',
                        Icons.payments_outlined, AppColors.gold)),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _ActionTile(
          icon: Icons.trending_up,
          title: 'Daily Active Users',
          subtitle: 'Track engagement over time',
          onTap: () => _soon(context, 'Daily Active Users chart'),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MiniStat(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ⚙️ Admin Settings
// ─────────────────────────────────────────────────────────────────────────────

/// Settings hub — every platform control lives here, so the other tabs stay
/// focused. Real management screens are linked directly; not-yet-built controls
/// show a neutral "coming soon" notice.
class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[Admin] AdminSettings build — /admin/settings');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _AdminHeader(
          icon: Icons.settings,
          title: 'Settings',
          subtitle: 'Platform controls & configuration',
        ),
        const SizedBox(height: 16),
        _ActionTile(
          icon: Icons.view_carousel,
          title: 'Banner Management',
          subtitle: 'Home screen banners',
          onTap: () => context.go('/admin/banners'),
        ),
        _ActionTile(
          icon: Icons.workspace_premium,
          title: 'Subscription Plans',
          subtitle: 'Premium plans & subscriptions',
          color: AppColors.gold,
          onTap: () => context.go('/admin/premium'),
        ),
        _ActionTile(
          icon: Icons.support_agent,
          title: 'Support Tickets',
          subtitle: 'User help requests & complaints',
          onTap: () => context.go('/admin/support'),
        ),
        _ActionTile(
          icon: Icons.star_rate_rounded,
          title: 'Ratings Management',
          subtitle: 'Moderate astrologer ratings',
          onTap: () => context.go('/admin/ratings'),
        ),
        _ActionTile(
          icon: Icons.report_problem_outlined,
          title: 'Reported Profiles',
          subtitle: 'Review user reports & moderation',
          color: AppColors.error,
          onTap: () => context.go('/admin/reports'),
        ),
        _ActionTile(
          icon: Icons.delete_sweep_outlined,
          title: 'Account Deletion Requests',
          subtitle: 'Approve or reject deletions',
          color: AppColors.error,
          onTap: () => context.go('/admin/deletion-requests'),
        ),
        const Divider(height: 28),
        _ActionTile(
          icon: Icons.notifications_outlined,
          title: 'Notification Settings',
          subtitle: 'Push & email preferences',
          onTap: () => _soon(context, 'Notification Settings'),
        ),
        _ActionTile(
          icon: Icons.tune,
          title: 'Platform Settings',
          subtitle: 'Maintenance mode, feature flags',
          onTap: () => _soon(context, 'Platform Settings'),
        ),
        _ActionTile(
          icon: Icons.app_settings_alt_outlined,
          title: 'App Configuration',
          subtitle: 'Versions & static content',
          onTap: () => _soon(context, 'App Configuration'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 🎫 Support Tickets
// ─────────────────────────────────────────────────────────────────────────────

class SupportTicketsScreen extends StatelessWidget {
  const SupportTicketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[Admin] SupportTickets build — /admin/support');
    return _adminScaffold(
      title: 'Support Tickets',
      icon: Icons.support_agent,
      subtitle: 'User help requests and complaints',
      children: [
        _ActionTile(
          icon: Icons.inbox_outlined,
          title: 'Open Tickets',
          subtitle: 'Review and respond to user issues',
          onTap: () => _soon(context, 'Open Tickets'),
        ),
        _ActionTile(
          icon: Icons.done_all,
          title: 'Resolved Tickets',
          subtitle: 'History of closed support requests',
          color: AppColors.success,
          onTap: () => _soon(context, 'Resolved Tickets'),
        ),
      ],
    );
  }
}
