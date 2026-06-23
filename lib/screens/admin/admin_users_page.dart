import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_account_model.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/common/data_states.dart';

/// Admin → Users. Two tabs:
///  • **Users**       — matrimony users, plan-wise counts (Free/Basic/Premium).
///  • **Astrologers** — **verified** astrologers only, plan-wise counts.
/// Each tab shows a total summary card and filter chips with live count badges.
class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.primary,
              labelStyle: TextStyle(fontWeight: FontWeight.bold),
              tabs: [
                Tab(text: 'Users'),
                Tab(text: 'Astrologers'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [_UsersTab(), _AstrologersTab()],
            ),
          ),
        ],
      ),
    );
  }
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
            colors: [color, color.withOpacity(0.75)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
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

/// Filter chip carrying a label + count badge, e.g. "Free (850)".
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
        selectedColor: AppColors.primary.withOpacity(0.14),
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

Widget _searchBar(TextEditingController c, String query, ValueChanged<String> onChanged,
        VoidCallback onClear) =>
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: c,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Search by name or email…',
          prefixIcon: const Icon(Icons.search, color: AppColors.primary),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18), onPressed: onClear),
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

Widget _chip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 9.5, fontWeight: FontWeight.bold)),
    );

// ─────────────────────────────────────────────────────────────────────────────
// Users tab
// ─────────────────────────────────────────────────────────────────────────────
enum _UserPlan { all, free, basic, premium }

String userPlanOf(UserModel u) {
  final m = u.membershipType.toLowerCase();
  if (m == 'premium') return 'premium';
  if (m == 'basic' || m == 'medium') return 'basic';
  return 'free';
}

class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();
  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _UserPlan _filter = _UserPlan.all;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(UserModel u) {
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty &&
        !(u.displayName ?? '').toLowerCase().contains(q) &&
        !(u.email ?? '').toLowerCase().contains(q)) {
      return false;
    }
    return switch (_filter) {
      _UserPlan.all => true,
      _UserPlan.free => userPlanOf(u) == 'free',
      _UserPlan.basic => userPlanOf(u) == 'basic',
      _UserPlan.premium => userPlanOf(u) == 'premium',
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final stats = ref.watch(adminStatsProvider).valueOrNull;
    final usersAsync = ref.watch(allUsersProvider);

    int n(String k) => (stats?[k] as num?)?.toInt() ?? 0;
    final total = n('totalUsers');
    final basic = n('basicPlanUsers') + n('mediumPlanUsers');
    final premium = n('premiumPlanUsers');
    final free = (total - basic - premium).clamp(0, total);

    return Column(
      children: [
        _SummaryCard(
            label: 'Total Users',
            value: total,
            icon: Icons.groups,
            color: AppColors.primary),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: [
              _CountChip(
                  label: 'All',
                  count: total,
                  selected: _filter == _UserPlan.all,
                  onTap: () => setState(() => _filter = _UserPlan.all)),
              _CountChip(
                  label: 'Free',
                  count: free,
                  selected: _filter == _UserPlan.free,
                  onTap: () => setState(() => _filter = _UserPlan.free)),
              _CountChip(
                  label: 'Basic',
                  count: basic,
                  selected: _filter == _UserPlan.basic,
                  onTap: () => setState(() => _filter = _UserPlan.basic)),
              _CountChip(
                  label: 'Premium',
                  count: premium,
                  selected: _filter == _UserPlan.premium,
                  onTap: () => setState(() => _filter = _UserPlan.premium)),
            ],
          ),
        ),
        _searchBar(_searchCtrl, _query, (v) => setState(() => _query = v),
            () => setState(() {
                  _query = '';
                  _searchCtrl.clear();
                })),
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
            data: (all) {
              final users = all.where(_matches).toList();
              if (users.isEmpty) {
                return const EmptyState(
                    icon: Icons.people_outline,
                    message: 'No users match this filter');
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: users.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _UserCard(user: users[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UserCard extends ConsumerWidget {
  final UserModel user;
  const _UserCard({required this.user});

  String get _name => (user.displayName?.trim().isNotEmpty ?? false)
      ? user.displayName!.trim()
      : (user.email ?? user.uid);

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
    final plan = userPlanOf(user);
    final planColor = plan == 'premium'
        ? AppColors.premiumPlan
        : plan == 'basic'
            ? AppColors.basicPlan
            : Colors.grey;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary.withOpacity(0.12),
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
                Text(user.email ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _chip(plan.toUpperCase(), planColor),
                    if (user.isBlocked) ...[
                      const SizedBox(width: 6),
                      _chip('SUSPENDED', AppColors.error),
                    ],
                  ],
                ),
              ],
            ),
          ),
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
// Astrologers tab (verified only)
// ─────────────────────────────────────────────────────────────────────────────
enum _AstroPlan { all, free, basic, premium }

/// Free = no active subscription · Basic = Starter/Basic tiers ·
/// Premium = Pro/Elite tiers.
String astroPlanOf(AstrologerAccount a) {
  if (!a.subscriptionActive) return 'free';
  final p = a.subscriptionPlan.toLowerCase();
  if (p == 'pro' || p == 'elite') return 'premium';
  return 'basic';
}

class _AstrologersTab extends ConsumerStatefulWidget {
  const _AstrologersTab();
  @override
  ConsumerState<_AstrologersTab> createState() => _AstrologersTabState();
}

class _AstrologersTabState extends ConsumerState<_AstrologersTab>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _AstroPlan _filter = _AstroPlan.all;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(AstrologerAccount a) {
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty &&
        !a.fullName.toLowerCase().contains(q) &&
        !a.email.toLowerCase().contains(q)) {
      return false;
    }
    return switch (_filter) {
      _AstroPlan.all => true,
      _AstroPlan.free => astroPlanOf(a) == 'free',
      _AstroPlan.basic => astroPlanOf(a) == 'basic',
      _AstroPlan.premium => astroPlanOf(a) == 'premium',
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final astrosAsync = ref.watch(allAstrologersProvider);

    return astrosAsync.when(
      loading: () => const LoadingState(message: 'Loading astrologers…'),
      error: (e, _) => ErrorStateView(
        message: 'Connection Error — unable to load astrologers.',
        onRetry: () => ref.invalidate(allAstrologersProvider),
      ),
      data: (all) {
        // Verified astrologers only — pending/rejected live on the
        // Astrologers verification page, not here.
        final verified =
            all.where((a) => a.status == VerificationStatus.approved).toList();
        final total = verified.length;
        final free = verified.where((a) => astroPlanOf(a) == 'free').length;
        final basic = verified.where((a) => astroPlanOf(a) == 'basic').length;
        final premium =
            verified.where((a) => astroPlanOf(a) == 'premium').length;
        final shown = verified.where(_matches).toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));

        return Column(
          children: [
            _SummaryCard(
                label: 'Total Verified Astrologers',
                value: total,
                icon: Icons.auto_awesome,
                color: const Color(0xFF7C5CFC)),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                children: [
                  _CountChip(
                      label: 'All',
                      count: total,
                      selected: _filter == _AstroPlan.all,
                      onTap: () => setState(() => _filter = _AstroPlan.all)),
                  _CountChip(
                      label: 'Free',
                      count: free,
                      selected: _filter == _AstroPlan.free,
                      onTap: () => setState(() => _filter = _AstroPlan.free)),
                  _CountChip(
                      label: 'Basic',
                      count: basic,
                      selected: _filter == _AstroPlan.basic,
                      onTap: () => setState(() => _filter = _AstroPlan.basic)),
                  _CountChip(
                      label: 'Premium',
                      count: premium,
                      selected: _filter == _AstroPlan.premium,
                      onTap: () =>
                          setState(() => _filter = _AstroPlan.premium)),
                ],
              ),
            ),
            _searchBar(_searchCtrl, _query, (v) => setState(() => _query = v),
                () => setState(() {
                      _query = '';
                      _searchCtrl.clear();
                    })),
            Expanded(
              child: shown.isEmpty
                  ? const EmptyState(
                      icon: Icons.auto_awesome_outlined,
                      message: 'No astrologers match this filter')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: shown.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) =>
                          _AstrologerCard(astrologer: shown[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _AstrologerCard extends ConsumerWidget {
  final AstrologerAccount astrologer;
  const _AstrologerCard({required this.astrologer});

  String get _location {
    final parts = [
      astrologer.district.isNotEmpty ? astrologer.district : astrologer.city,
      astrologer.state,
    ].where((p) => p.trim().isNotEmpty).toList();
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = astroPlanOf(astrologer);
    final planColor = plan == 'premium'
        ? AppColors.premiumPlan
        : plan == 'basic'
            ? AppColors.basicPlan
            : Colors.grey;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF7C5CFC).withOpacity(0.12),
            backgroundImage: astrologer.photoUrl.isNotEmpty
                ? NetworkImage(astrologer.photoUrl)
                : null,
            child: astrologer.photoUrl.isEmpty
                ? Text(
                    astrologer.fullName.isNotEmpty
                        ? astrologer.fullName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: Color(0xFF7C5CFC),
                        fontWeight: FontWeight.bold))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                          astrologer.fullName.isEmpty
                              ? 'Unnamed'
                              : astrologer.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.star_rounded,
                        color: Color(0xFFFFB300), size: 15),
                    Text(astrologer.rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(_location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 5),
                _chip(plan.toUpperCase(), planColor),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final messenger = ScaffoldMessenger.of(context);
              if (v == 'suspend') {
                await ref
                    .read(adminActionsProvider.notifier)
                    .suspendAstrologer(astrologer.id);
                final st = ref.read(adminActionsProvider);
                messenger.showSnackBar(SnackBar(
                  content: Text(st.hasError
                      ? 'Action failed.'
                      : '${astrologer.fullName} moved back to pending review.'),
                  backgroundColor: st.hasError ? AppColors.error : null,
                ));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'suspend',
                  child: ListTile(
                      leading: Icon(Icons.pause_circle_outline),
                      title: Text('Suspend'),
                      contentPadding: EdgeInsets.zero)),
            ],
          ),
        ],
      ),
    );
  }
}
