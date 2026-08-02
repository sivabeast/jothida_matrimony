import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/data_states.dart';

/// Admin → Users. Manages MATRIMONY USERS only.
///
/// - SEARCH: one debounced field matching the user (name / email / phone /
///   uid) AND the joined matrimony profile (Tamil + English name, profile id,
///   religion, caste, city, district, state, education, occupation).
/// - FILTERS: single-select chips with LIVE counts computed from the
///   `allUsersProvider` / `profilesByUserIdProvider` streams (no one-shot
///   stats dependency) — All · Male · Female · Approved · Pending · Rejected ·
///   Suspended · Recently Joined · Recently Updated.
/// - BULK ACTIONS: a checklist toggle enters multi-select mode (checkboxes +
///   Select All) with a bottom bar: Approve / Reject / Delete / Export CSV /
///   Notify selected.
///
/// (Horoscope-analysis staff are managed under admin → Employees.)
class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context) => const _UsersTab();
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared bits
// ─────────────────────────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  const _SummaryCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.75)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$value',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      height: 1.1)),
              Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Filter chip carrying a label + count badge, e.g. "Pending (12)".
class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _CountChip(
      {required this.label,
      required this.count,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label ($count)'),
        selected: selected,
        showCheckmark: false,
        selectedColor: AppColors.primary.withValues(alpha: 0.14),
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          color: selected ? AppColors.primary : Colors.black87,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          fontSize: 13,
        ),
        side: BorderSide(
            color: selected ? AppColors.primary : Colors.grey[300]!),
        onSelected: (_) => onTap(),
      ),
    );
  }
}

Widget _chip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 9.5, fontWeight: FontWeight.bold)),
    );

// ── CSV helpers (mirrors admin_export.dart, whose helpers are private) ───────

String _csvCell(Object? v) {
  final s = '$v';
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String _csv(List<List<Object?>> rows) =>
    rows.map((r) => r.map(_csvCell).join(',')).join('\n');

String _stamp() {
  final n = DateTime.now();
  return '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Filters
// ─────────────────────────────────────────────────────────────────────────────
enum _UserFilter {
  all('All'),
  male('Male'),
  female('Female'),
  approved('Approved'),
  pending('Pending'),
  rejected('Rejected'),
  suspended('Suspended'),
  recentJoined('Recently Joined'),
  recentUpdated('Recently Updated');

  final String label;
  const _UserFilter(this.label);
}

// ─────────────────────────────────────────────────────────────────────────────
// Users tab
// ─────────────────────────────────────────────────────────────────────────────
class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();
  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  _UserFilter _filter = _UserFilter.all;

  // Multi-select mode.
  bool _selectMode = false;
  bool _busy = false;
  final Set<String> _selected = <String>{};

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Search + filter predicates ─────────────────────────────────────────────

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = v.trim().toLowerCase());
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() => _query = '');
  }

  /// Case-insensitive substring match across the user AND its joined profile.
  bool _queryMatches(UserModel u, ProfileModel? p) {
    final q = _query;
    if (q.isEmpty) return true;
    bool has(String? s) => s != null && s.toLowerCase().contains(q);
    if (has(u.displayName) || has(u.email) || has(u.phone) || has(u.uid)) {
      return true;
    }
    if (p == null) return false;
    return has(p.fullName) ||
        has(p.fullNameTamil) ||
        has(p.id) ||
        has(p.religion) ||
        has(p.caste) ||
        has(p.city) ||
        has(p.district) ||
        has(p.state) ||
        has(p.education) ||
        has(p.occupation);
  }

  bool _filterMatches(
      _UserFilter f, UserModel u, ProfileModel? p, DateTime cutoff) {
    switch (f) {
      case _UserFilter.all:
        return true;
      case _UserFilter.male:
        return (p?.gender ?? '').trim().toLowerCase() == 'male';
      case _UserFilter.female:
        return (p?.gender ?? '').trim().toLowerCase() == 'female';
      case _UserFilter.approved:
        return (p?.status ?? '').trim().toLowerCase() == 'approved';
      case _UserFilter.pending:
        return (p?.status ?? '').trim().toLowerCase() == 'pending';
      case _UserFilter.rejected:
        return (p?.status ?? '').trim().toLowerCase() == 'rejected';
      case _UserFilter.suspended:
        return u.isBlocked;
      case _UserFilter.recentJoined:
        return u.createdAt.isAfter(cutoff);
      case _UserFilter.recentUpdated:
        return p != null && p.updatedAt.isAfter(cutoff);
    }
  }

  // ── Selection helpers ──────────────────────────────────────────────────────

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selected.clear();
    });
  }

  void _toggleUid(String uid) {
    setState(() {
      if (!_selected.remove(uid)) _selected.add(uid);
    });
  }

  void _toggleSelectAll(List<UserModel> visible) {
    setState(() {
      final allSelected = visible.isNotEmpty &&
          visible.every((u) => _selected.contains(u.uid));
      if (allSelected) {
        for (final u in visible) {
          _selected.remove(u.uid);
        }
      } else {
        _selected.addAll(visible.map((u) => u.uid));
      }
    });
  }

  void _finishBulk(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.clear();
      _selectMode = false;
    });
    _snack(message, error: error);
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.error : null,
    ));
  }

  // ── Bulk actions ───────────────────────────────────────────────────────────

  Map<String, ProfileModel> get _profilesNow =>
      ref.read(profilesByUserIdProvider).valueOrNull ??
      const <String, ProfileModel>{};

  Future<void> _bulkApprove() async {
    final uids = _selected.toList();
    final profiles = _profilesNow;
    setState(() => _busy = true);
    _snack('Approving ${uids.length} profile(s)…');
    final notifier = ref.read(adminActionsProvider.notifier);
    var ok = 0, failed = 0, skipped = 0;
    for (final uid in uids) {
      final p = profiles[uid];
      if (p == null) {
        skipped++;
        continue;
      }
      // Already-approved profiles are skipped — re-approving would blast a
      // fresh "Profile Approved" push at long-standing members.
      if (p.status == 'approved') {
        skipped++;
        continue;
      }
      await notifier.approveProfile(p.id, userId: uid);
      if (ref.read(adminActionsProvider).hasError) {
        failed++;
      } else {
        ok++;
      }
    }
    _finishBulk(_bulkSummary('Approved', ok, failed, skipped),
        error: ok == 0 && failed > 0);
  }

  Future<void> _bulkReject() async {
    final reason = await showDialog<String>(
        context: context,
        builder: (_) => _ReasonDialog(count: _selected.length));
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    final uids = _selected.toList();
    final profiles = _profilesNow;
    setState(() => _busy = true);
    _snack('Rejecting ${uids.length} profile(s)…');
    final notifier = ref.read(adminActionsProvider.notifier);
    var ok = 0, failed = 0, skipped = 0;
    for (final uid in uids) {
      final p = profiles[uid];
      if (p == null) {
        skipped++;
        continue;
      }
      await notifier.rejectProfile(p.id, reason.trim(), userId: uid);
      if (ref.read(adminActionsProvider).hasError) {
        failed++;
      } else {
        ok++;
      }
    }
    _finishBulk(_bulkSummary('Rejected', ok, failed, skipped),
        error: ok == 0 && failed > 0);
  }

  Future<void> _bulkDelete() async {
    final n = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete accounts?'),
        content: Text('This permanently deletes $n account(s). '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final uids = _selected.toList();
    setState(() => _busy = true);
    _snack('Deleting $n account(s)…');
    final notifier = ref.read(adminActionsProvider.notifier);
    var ok = 0, failed = 0;
    for (final uid in uids) {
      await notifier.deleteUser(uid);
      if (ref.read(adminActionsProvider).hasError) {
        failed++;
      } else {
        ok++;
      }
    }
    _finishBulk(_bulkSummary('Deleted', ok, failed, 0),
        error: ok == 0 && failed > 0);
  }

  Future<void> _bulkExport() async {
    final users = (ref.read(allUsersProvider).valueOrNull ?? const <UserModel>[])
        .where((u) => _selected.contains(u.uid))
        .toList();
    final profiles = _profilesNow;
    final rows = <List<Object?>>[
      ['uid', 'name', 'email', 'phone', 'gender', 'status', 'city', 'createdAt'],
      for (final u in users)
        [
          u.uid,
          (profiles[u.uid]?.fullName.trim().isNotEmpty ?? false)
              ? profiles[u.uid]!.fullName.trim()
              : (u.displayName ?? ''),
          u.email ?? '',
          u.phone ?? '',
          profiles[u.uid]?.gender ?? u.gender ?? '',
          u.isBlocked ? 'suspended' : (profiles[u.uid]?.status ?? ''),
          profiles[u.uid]?.city ?? '',
          u.createdAt.toIso8601String(),
        ],
    ];
    final csv = _csv(rows);
    setState(() => _busy = true);
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/users_export_${_stamp()}.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')],
          subject: 'users_export_${_stamp()}.csv');
      _finishBulk('Exported ${users.length} user(s) to CSV.');
    } catch (e) {
      debugPrint('[AdminUsers] CSV share failed, copying instead: $e');
      await Clipboard.setData(ClipboardData(text: csv));
      _finishBulk('Share unavailable — CSV for ${users.length} user(s) '
          'copied to clipboard.');
    }
  }

  Future<void> _bulkNotify() async {
    final result = await showDialog<(String, String)>(
        context: context,
        builder: (_) => _NotifyDialog(count: _selected.length));
    if (result == null || !mounted) return;
    final uids = _selected.toList();
    setState(() => _busy = true);
    _snack('Sending notification to ${uids.length} user(s)…');
    try {
      await ref.read(firestoreServiceProvider).createNotificationsBatch(
            uids: uids,
            title: result.$1,
            body: result.$2,
            type: 'admin_update',
          );
      _finishBulk('Notification sent to ${uids.length} user(s).');
    } catch (e) {
      debugPrint('[AdminUsers] bulk notify failed: $e');
      _finishBulk('Could not send the notification. Please try again.',
          error: true);
    }
  }

  String _bulkSummary(String verb, int ok, int failed, int skipped) {
    final parts = <String>['$verb $ok profile(s).'];
    if (failed > 0) parts.add('$failed failed.');
    if (skipped > 0) parts.add('$skipped skipped (no profile).');
    return parts.join(' ');
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final usersAsync = ref.watch(allUsersProvider);
    final profiles = ref.watch(profilesByUserIdProvider).valueOrNull ??
        const <String, ProfileModel>{};

    final all = usersAsync.valueOrNull ?? const <UserModel>[];
    final cutoff = DateTime.now().subtract(const Duration(days: 7));

    // Search first, then chip counts + the active filter on the searched set,
    // so every chip shows a LIVE count of what selecting it would display.
    final searched =
        all.where((u) => _queryMatches(u, profiles[u.uid])).toList();
    final counts = <_UserFilter, int>{
      for (final f in _UserFilter.values)
        f: searched
            .where((u) => _filterMatches(f, u, profiles[u.uid], cutoff))
            .length,
    };
    final visible = searched
        .where((u) => _filterMatches(_filter, u, profiles[u.uid], cutoff))
        .toList();

    return Column(
      children: [
        _SummaryCard(
            label: 'Total Users',
            value: all.length,
            icon: Icons.groups,
            color: AppColors.primary),
        _buildToolbar(),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: [
              for (final f in _UserFilter.values)
                _CountChip(
                    label: f.label,
                    count: counts[f] ?? 0,
                    selected: _filter == f,
                    onTap: () => setState(() => _filter = f)),
            ],
          ),
        ),
        if (_selectMode) _buildSelectionHeader(visible),
        Expanded(
          child: usersAsync.when(
            loading: () => const LoadingState(message: 'Loading users…'),
            error: (e, _) {
              debugPrint('[AdminUsers] load failed: $e');
              return ErrorStateView(
                message: 'Connection Error — unable to load users.',
                onRetry: () => ref.invalidate(allUsersProvider),
              );
            },
            data: (_) {
              if (visible.isEmpty) {
                return const EmptyState(
                    icon: Icons.people_outline,
                    message: 'No users match this search / filter');
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final u = visible[i];
                  return InkWell(
                    onTap: _busy
                        ? null
                        : () => _selectMode
                            ? _toggleUid(u.uid)
                            : ctx.push('/admin/user/${u.uid}'),
                    borderRadius: BorderRadius.circular(14),
                    child: _UserCard(
                      user: u,
                      profile: profiles[u.uid],
                      selectMode: _selectMode,
                      selected: _selected.contains(u.uid),
                      onToggle: _busy ? null : () => _toggleUid(u.uid),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (_selectMode)
          _BulkActionBar(
            count: _selected.length,
            busy: _busy,
            onApprove: _bulkApprove,
            onReject: _bulkReject,
            onDelete: _bulkDelete,
            onExport: _bulkExport,
            onNotify: _bulkNotify,
          ),
      ],
    );
  }

  /// Search field + the multi-select mode toggle.
  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search name, email, phone, caste, city…',
                prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _clearSearch),
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
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: _selectMode ? 'Exit selection' : 'Select multiple',
            onPressed: _busy ? null : _toggleSelectMode,
            style: IconButton.styleFrom(
              backgroundColor:
                  _selectMode ? AppColors.primary : Colors.white,
              foregroundColor:
                  _selectMode ? Colors.white : AppColors.primary,
              side: BorderSide(
                  color: _selectMode ? AppColors.primary : Colors.grey[300]!),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(_selectMode ? Icons.close : Icons.checklist),
          ),
        ],
      ),
    );
  }

  /// "Select all" tristate + live selected count (multi-select mode only).
  Widget _buildSelectionHeader(List<UserModel> visible) {
    final selVisible =
        visible.where((u) => _selected.contains(u.uid)).length;
    final bool? allState = (visible.isEmpty || selVisible == 0)
        ? false
        : (selVisible == visible.length ? true : null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      child: Row(
        children: [
          Checkbox(
            tristate: true,
            value: allState,
            activeColor: AppColors.primary,
            onChanged: _busy ? null : (_) => _toggleSelectAll(visible),
          ),
          const Text('Select all', style: TextStyle(fontSize: 13)),
          const Spacer(),
          Text('${_selected.length} selected',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Row card
// ─────────────────────────────────────────────────────────────────────────────
class _UserCard extends ConsumerWidget {
  final UserModel user;
  final ProfileModel? profile;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onToggle;
  const _UserCard(
      {required this.user,
      this.profile,
      this.selectMode = false,
      this.selected = false,
      this.onToggle});

  String get _name {
    final p = profile;
    if (p != null && p.fullName.trim().isNotEmpty) return p.fullName.trim();
    if (user.displayName?.trim().isNotEmpty ?? false) {
      return user.displayName!.trim();
    }
    return user.email ?? user.uid;
  }

  Color _statusColor(String s) => switch (s) {
        'approved' => AppColors.success,
        'pending' => AppColors.warning,
        'rejected' => AppColors.error,
        _ => AppColors.info,
      };

  Future<void> _act(BuildContext context, WidgetRef ref,
      Future<void> Function() action, String okMsg) async {
    final messenger = ScaffoldMessenger.of(context);
    await action();
    final st = ref.read(adminActionsProvider);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError ? 'Action failed. Please try again.' : okMsg),
      backgroundColor: st.hasError ? AppColors.error : null,
    ));
    ref.invalidate(allUsersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = (profile?.status ?? '').trim().toLowerCase();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: selectMode && selected
            ? Border.all(color: AppColors.primary, width: 1.4)
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
        ],
      ),
      child: Row(
        children: [
          if (selectMode)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Checkbox(
                value: selected,
                activeColor: AppColors.primary,
                onChanged: onToggle == null ? null : (_) => onToggle!(),
              ),
            ),
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            backgroundImage: (user.photoUrl?.isNotEmpty ?? false)
                ? NetworkImage(user.photoUrl!)
                : null,
            child: (user.photoUrl?.isEmpty ?? true)
                ? Text(_name.isNotEmpty ? _name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.bold))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(user.email ?? user.phone ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _chip(user.isBlocked ? 'SUSPENDED' : 'ACTIVE',
                        user.isBlocked ? AppColors.error : AppColors.success),
                    if (status.isNotEmpty)
                      _chip(status.toUpperCase(), _statusColor(status)),
                  ],
                ),
              ],
            ),
          ),
          if (!selectMode)
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'suspend':
                    await _act(
                        context,
                        ref,
                        () => ref
                            .read(adminActionsProvider.notifier)
                            .blockUser(user.uid),
                        'User suspended.');
                  case 'activate':
                    await _act(
                        context,
                        ref,
                        () => ref
                            .read(adminActionsProvider.notifier)
                            .unblockUser(user.uid),
                        'User reactivated.');
                }
              },
              itemBuilder: (_) => [
                if (user.isBlocked)
                  const PopupMenuItem(
                      value: 'activate',
                      child: ListTile(
                          leading: Icon(Icons.lock_open_outlined),
                          title: Text('Activate'),
                          contentPadding: EdgeInsets.zero))
                else
                  const PopupMenuItem(
                      value: 'suspend',
                      child: ListTile(
                          leading: Icon(Icons.block_outlined),
                          title: Text('Suspend'),
                          contentPadding: EdgeInsets.zero)),
              ],
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bulk action bar + dialogs
// ─────────────────────────────────────────────────────────────────────────────
class _BulkActionBar extends StatelessWidget {
  final int count;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;
  final VoidCallback onExport;
  final VoidCallback onNotify;
  const _BulkActionBar(
      {required this.count,
      required this.busy,
      required this.onApprove,
      required this.onReject,
      required this.onDelete,
      required this.onExport,
      required this.onNotify});

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0 && !busy;
    return Material(
      elevation: 10,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const LinearProgressIndicator(
                  minHeight: 2, color: AppColors.primary),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  _BulkButton(
                      icon: Icons.check_circle_outline,
                      label: 'Approve',
                      color: AppColors.success,
                      onTap: enabled ? onApprove : null),
                  _BulkButton(
                      icon: Icons.cancel_outlined,
                      label: 'Reject',
                      color: AppColors.warning,
                      onTap: enabled ? onReject : null),
                  _BulkButton(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      color: AppColors.error,
                      onTap: enabled ? onDelete : null),
                  _BulkButton(
                      icon: Icons.ios_share,
                      label: 'Export',
                      color: AppColors.info,
                      onTap: enabled ? onExport : null),
                  _BulkButton(
                      icon: Icons.campaign_outlined,
                      label: 'Notify',
                      color: AppColors.primary,
                      onTap: enabled ? onNotify : null),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _BulkButton(
      {required this.icon,
      required this.label,
      required this.color,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600)),
        style: TextButton.styleFrom(
          foregroundColor: color,
          disabledForegroundColor: Colors.grey[400],
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
    );
  }
}

/// Single reason for a bulk reject — applied to every selected profile.
class _ReasonDialog extends StatefulWidget {
  final int count;
  const _ReasonDialog({required this.count});
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reject ${widget.count} profile(s)'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLines: 3,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: 'Rejection reason (shown to the member)…',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
          onPressed: _ctrl.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

/// Title + message for a bulk in-app notification (type `admin_update`).
class _NotifyDialog extends StatefulWidget {
  final int count;
  const _NotifyDialog({required this.count});
  @override
  State<_NotifyDialog> createState() => _NotifyDialogState();
}

class _NotifyDialogState extends State<_NotifyDialog> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _titleCtrl.text.trim().isNotEmpty && _bodyCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Notify ${widget.count} user(s)'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtrl,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Message',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(
                  context, (_titleCtrl.text.trim(), _bodyCtrl.text.trim()))
              : null,
          child: const Text('Send'),
        ),
      ],
    );
  }
}

// (The Astrologers tab + its cards were removed — the Users page now manages
// matrimony users only; horoscope-analysis staff live under admin → Employees.)
