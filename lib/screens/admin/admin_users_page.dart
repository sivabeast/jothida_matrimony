import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/profile_completion.dart';
import '../../models/profile_model.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/data_states.dart';

/// Admin → Users. Manages MATRIMONY USERS only.
///
/// - TABS: All / Male / Female / Incomplete (users doc without a joined
///   matrimony profile), each with a LIVE count in its label.
/// - SEARCH: one debounced field matching the user (name / email / phone /
///   uid) AND the joined matrimony profile (Tamil + English name, profile id,
///   religion, caste, city, district, state, education, occupation).
/// - FILTERS: status chips with LIVE counts applied WITHIN the active tab —
///   All · Approved · Pending · Rejected · Suspended · Recently Joined ·
///   Recently Updated. (Male/Female moved up into the tab bar.)
/// - SORT: Newest first (default) · Name A-Z · Last login · Completion %.
/// - STICKY HEADER: the search row + tab bar + filter chips are a pinned
///   SliverPersistentHeader; only the summary card and the list scroll.
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
                      fontFamily: 'Poppins',
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

/// Display name resolution shared by the row card, sorting and CSV export:
/// profile fullName > user displayName > email > uid.
String _displayNameOf(UserModel u, ProfileModel? p) {
  if (p != null && p.fullName.trim().isNotEmpty) return p.fullName.trim();
  final dn = u.displayName?.trim() ?? '';
  if (dn.isNotEmpty) return dn;
  return u.email ?? u.uid;
}

// ── Date formatting (tiny local helpers — no intl dependency) ────────────────

const _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _shortDate(DateTime d) => '${d.day} ${_kMonths[d.month - 1]} ${d.year}';

/// Compact relative time, e.g. "2d ago".
String _relativeTime(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}

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
// Tabs / filters / sort
// ─────────────────────────────────────────────────────────────────────────────

/// Primary segmentation. "Incomplete" = logged-in users (users doc) with NO
/// joined matrimony profile document.
enum _UserTab {
  all('All', Icons.people_outline),
  male('Male', Icons.male),
  female('Female', Icons.female),
  incomplete('Incomplete', Icons.person_off_outlined);

  final String label;
  final IconData emptyIcon;
  const _UserTab(this.label, this.emptyIcon);
}

/// Secondary status filter, applied within the active tab. (Male/Female were
/// promoted to tabs.)
enum _UserFilter {
  all('All'),
  approved('Approved'),
  pending('Pending'),
  rejected('Rejected'),
  suspended('Suspended'),
  recentJoined('Recently Joined'),
  recentUpdated('Recently Updated');

  final String label;
  const _UserFilter(this.label);
}

enum _UserSort {
  newest('Newest first'),
  nameAz('Name A-Z'),
  lastLogin('Last login'),
  completion('Completion %');

  final String label;
  const _UserSort(this.label);
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
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  // Pinned-header row heights (fixed so the SliverPersistentHeader extent is
  // exact — each row is wrapped in a SizedBox of the same height).
  static const double _kSearchRowH = 62; // 8 top pad + 48 row + 6 bottom pad
  static const double _kTabBarH = 46; // kTextTabBarHeight
  static const double _kChipsH = 46;
  static const double _kSelectionH = 40;

  final _searchCtrl = TextEditingController();
  late final TabController _tabCtrl;
  Timer? _debounce;
  String _query = '';
  _UserFilter _filter = _UserFilter.all;
  _UserSort _sort = _UserSort.newest;

  // Multi-select mode.
  bool _selectMode = false;
  bool _busy = false;
  final Set<String> _selected = <String>{};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _UserTab.values.length, vsync: this);
    // Rebuild on tap AND on swipe-settle so counts + list follow the tab.
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Search + tab + filter predicates ───────────────────────────────────────

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

  bool _tabMatches(_UserTab t, UserModel u, ProfileModel? p) => switch (t) {
        _UserTab.all => true,
        _UserTab.male => (p?.gender ?? '').trim().toLowerCase() == 'male',
        _UserTab.female => (p?.gender ?? '').trim().toLowerCase() == 'female',
        _UserTab.incomplete => p == null,
      };

  bool _filterMatches(
      _UserFilter f, UserModel u, ProfileModel? p, DateTime cutoff) {
    switch (f) {
      case _UserFilter.all:
        return true;
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

  /// In-place sort of the visible rows per the active [_sort] mode.
  void _sortUsers(List<UserModel> list, Map<String, ProfileModel> profiles) {
    switch (_sort) {
      case _UserSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _UserSort.nameAz:
        list.sort((a, b) => _displayNameOf(a, profiles[a.uid])
            .toLowerCase()
            .compareTo(_displayNameOf(b, profiles[b.uid]).toLowerCase()));
      case _UserSort.lastLogin:
        final epoch = DateTime.fromMillisecondsSinceEpoch(0);
        list.sort((a, b) =>
            (b.lastLoginAt ?? epoch).compareTo(a.lastLoginAt ?? epoch));
      case _UserSort.completion:
        // Profile-less rows sort last (-1 < 0%).
        final pct = <String, int>{
          for (final u in list)
            u.uid: profiles[u.uid] == null
                ? -1
                : computeProfileCompletion(profiles[u.uid]).percent,
        };
        list.sort((a, b) => pct[b.uid]!.compareTo(pct[a.uid]!));
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
    final profilesAsync = ref.watch(profilesByUserIdProvider);
    final profiles =
        profilesAsync.valueOrNull ?? const <String, ProfileModel>{};

    final all = usersAsync.valueOrNull ?? const <UserModel>[];
    final cutoff = DateTime.now().subtract(const Duration(days: 7));

    // The users↔profiles join drives the tabs (Incomplete = no joined
    // profile), so wait for BOTH streams before rendering rows — otherwise
    // every user would flash through the Incomplete tab.
    final loading = (usersAsync.isLoading && !usersAsync.hasValue) ||
        (profilesAsync.isLoading && !profilesAsync.hasValue);

    // Search first; tab counts are computed on the searched set so each tab
    // label shows a LIVE count of what opening it would display.
    final searched =
        all.where((u) => _queryMatches(u, profiles[u.uid])).toList();
    final tabCounts = <int>[
      for (final t in _UserTab.values)
        searched.where((u) => _tabMatches(t, u, profiles[u.uid])).length,
    ];

    final tab = _UserTab.values[_tabCtrl.index];
    final inTab =
        searched.where((u) => _tabMatches(tab, u, profiles[u.uid])).toList();

    // Status-chip counts + the active filter, both within the active tab.
    final counts = <_UserFilter, int>{
      for (final f in _UserFilter.values)
        f: inTab
            .where((u) => _filterMatches(f, u, profiles[u.uid], cutoff))
            .length,
    };
    final visible = inTab
        .where((u) => _filterMatches(_filter, u, profiles[u.uid], cutoff))
        .toList();
    _sortUsers(visible, profiles);

    final headerH = _kSearchRowH +
        _kTabBarH +
        _kChipsH +
        (_selectMode ? _kSelectionH : 0.0);

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _SummaryCard(
                    label: 'Total Users',
                    value: all.length,
                    icon: Icons.groups,
                    color: AppColors.primary),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedHeaderDelegate(
                  height: headerH,
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Column(
                      children: [
                        SizedBox(height: _kSearchRowH, child: _buildToolbar()),
                        SizedBox(
                            height: _kTabBarH, child: _buildTabBar(tabCounts)),
                        SizedBox(
                            height: _kChipsH, child: _buildFilterRow(counts)),
                        if (_selectMode)
                          SizedBox(
                              height: _kSelectionH,
                              child: _buildSelectionHeader(visible)),
                      ],
                    ),
                  ),
                ),
              ),
              if (loading)
                _buildSkeletonSliver()
              else if (usersAsync.hasError && !usersAsync.hasValue)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorStateView(
                    message: 'Connection Error — unable to load users.',
                    onRetry: () => ref.invalidate(allUsersProvider),
                  ),
                )
              else if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: _query.isNotEmpty ? Icons.search_off : tab.emptyIcon,
                    message: _emptyMessage(tab),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverList.separated(
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
                        borderRadius: BorderRadius.circular(16),
                        child: _UserCard(
                          user: u,
                          profile: profiles[u.uid],
                          selectMode: _selectMode,
                          selected: _selected.contains(u.uid),
                          onToggle: _busy ? null : () => _toggleUid(u.uid),
                        ),
                      );
                    },
                  ),
                ),
            ],
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

  String _emptyMessage(_UserTab tab) {
    if (_query.isNotEmpty || _filter != _UserFilter.all) {
      return 'No users match this search / filter';
    }
    return switch (tab) {
      _UserTab.all => 'No registered users yet',
      _UserTab.male => 'No male profiles yet',
      _UserTab.female => 'No female profiles yet',
      _UserTab.incomplete => 'Every registered user has a profile',
    };
  }

  /// Six static grey placeholder rows shown while the streams warm up.
  Widget _buildSkeletonSliver() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      sliver: SliverList.separated(
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, __) => const _SkeletonCard(),
      ),
    );
  }

  /// Search field + sort menu + the multi-select mode toggle.
  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
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
          _buildSortButton(),
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

  Widget _buildSortButton() {
    return PopupMenuButton<_UserSort>(
      tooltip: 'Sort: ${_sort.label}',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (s) => setState(() => _sort = s),
      itemBuilder: (_) => [
        for (final s in _UserSort.values)
          PopupMenuItem<_UserSort>(
            value: s,
            height: 40,
            child: Row(
              children: [
                Icon(
                    s == _sort
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: s == _sort ? AppColors.primary : Colors.grey[400]),
                const SizedBox(width: 10),
                Text(s.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          s == _sort ? FontWeight.w600 : FontWeight.normal,
                      color: s == _sort ? AppColors.primary : Colors.black87,
                    )),
              ],
            ),
          ),
      ],
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Icon(Icons.sort_rounded,
            color: AppColors.primary, size: 22),
      ),
    );
  }

  Widget _buildTabBar(List<int> tabCounts) {
    return TabBar(
      controller: _tabCtrl,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: AppColors.primary,
      unselectedLabelColor: Colors.grey[600],
      labelStyle: const TextStyle(
          fontSize: 13.5, fontWeight: FontWeight.w600, fontFamily: 'Poppins'),
      unselectedLabelStyle:
          const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
      indicatorColor: AppColors.primary,
      indicatorWeight: 2.5,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.grey[300],
      dividerHeight: 1,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tabs: [
        for (var i = 0; i < _UserTab.values.length; i++)
          Tab(text: '${_UserTab.values[i].label} (${tabCounts[i]})'),
      ],
    );
  }

  Widget _buildFilterRow(Map<_UserFilter, int> counts) {
    return ListView(
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
              tristate: true,
              value: allState,
              activeColor: AppColors.primary,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: _busy ? null : (_) => _toggleSelectAll(visible),
            ),
          ),
          const SizedBox(width: 6),
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

/// Fixed-extent pinned header for the search row + tab bar + filter chips.
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  const _PinnedHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      SizedBox.expand(child: child);

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
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

  String get _name => _displayNameOf(user, profile);

  /// Prefer the matrimony profile photo, then the auth account photo.
  String? get _photoUrl {
    final pp = profile?.profilePhotoUrl;
    if (pp != null && pp.isNotEmpty) return pp;
    final up = user.photoUrl;
    if (up != null && up.isNotEmpty) return up;
    return null;
  }

  String get _shortUid =>
      user.uid.length <= 10 ? user.uid : '${user.uid.substring(0, 10)}…';

  Color _statusColor(String s) => switch (s) {
        'approved' => AppColors.success,
        'pending' => AppColors.warning,
        'rejected' => AppColors.error,
        _ => AppColors.info,
      };

  void _copyUid(BuildContext context) {
    Clipboard.setData(ClipboardData(text: user.uid));
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(const SnackBar(content: Text('User ID copied')));
  }

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
    final completion =
        profile == null ? null : computeProfileCompletion(profile).percent;
    final photo = _photoUrl;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: selectMode && selected
            ? Border.all(color: AppColors.primary, width: 1.4)
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
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
            radius: 24,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            backgroundImage: photo != null ? NetworkImage(photo) : null,
            child: photo == null
                ? Text(_name.isNotEmpty ? _name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins'))
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
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        fontFamily: 'Poppins')),
                const SizedBox(height: 2),
                Text(user.email ?? user.phone ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                const SizedBox(height: 5),
                // Short uid — long-press copies the FULL uid.
                GestureDetector(
                  onLongPress: () => _copyUid(context),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tag, size: 10, color: Colors.grey[500]),
                        const SizedBox(width: 2),
                        Text(_shortUid,
                            style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 0.3,
                                color: Colors.grey[600])),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    // Membership — subscriptions were removed app-wide, every
                    // member is on the free plan.
                    _chip('FREE', AppColors.goldDark),
                    _chip(user.isBlocked ? 'SUSPENDED' : 'ACTIVE',
                        user.isBlocked ? AppColors.error : AppColors.success),
                    if (status.isNotEmpty)
                      _chip(status.toUpperCase(), _statusColor(status)),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Icon(Icons.event_outlined,
                        size: 11.5, color: Colors.grey[500]),
                    const SizedBox(width: 3),
                    Text('Joined ${_shortDate(user.createdAt)}',
                        style:
                            TextStyle(fontSize: 10.5, color: Colors.grey[600])),
                    const SizedBox(width: 10),
                    Icon(Icons.schedule_outlined,
                        size: 11.5, color: Colors.grey[500]),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                          user.lastLoginAt == null
                              ? 'Never logged in'
                              : 'Seen ${_relativeTime(user.lastLoginAt!)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10.5, color: Colors.grey[600])),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (completion != null)
            _CompletionRing(percent: completion)
          else
            _chip('No profile', Colors.blueGrey),
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

/// Small circular profile-completion gauge with the percent in the middle.
/// Uses the same [computeProfileCompletion] as the Home completion card, so
/// admin and member always see the SAME number.
class _CompletionRing extends StatelessWidget {
  final int percent;
  const _CompletionRing({required this.percent});

  Color get _color => percent >= 80
      ? AppColors.success
      : (percent >= 40 ? AppColors.warning : AppColors.error);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Profile $percent% complete',
      child: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(
                value: percent.clamp(0, 100) / 100,
                strokeWidth: 3.5,
                strokeCap: StrokeCap.round,
                backgroundColor: Colors.grey[200],
                color: _color,
              ),
            ),
            Text('$percent%',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: _color)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading skeleton
// ─────────────────────────────────────────────────────────────────────────────

/// Static grey placeholder row matching the shape of [_UserCard] (no shimmer
/// package — plain rounded boxes).
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  Widget _bar(double w, double h, [double r = 6]) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(r),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration:
                BoxDecoration(color: Colors.grey[200], shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(150, 12),
                const SizedBox(height: 8),
                _bar(110, 10),
                const SizedBox(height: 10),
                Row(children: [
                  _bar(44, 16, 20),
                  const SizedBox(width: 6),
                  _bar(58, 16, 20),
                ]),
                const SizedBox(height: 10),
                _bar(170, 9),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 38,
            height: 38,
            decoration:
                BoxDecoration(color: Colors.grey[200], shape: BoxShape.circle),
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
