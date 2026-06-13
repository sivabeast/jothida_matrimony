import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/common/data_states.dart';

enum _UserFilter { all, active, suspended, premium }

extension on _UserFilter {
  String get label => switch (this) {
        _UserFilter.all => 'All',
        _UserFilter.active => 'Active',
        _UserFilter.suspended => 'Suspended',
        _UserFilter.premium => 'Premium',
      };
}

bool _isPremium(UserModel u) =>
    u.membershipType != 'free' || u.hasActiveSubscription;

/// Admin → Users. Search, filter (Active / Suspended / Premium), view details,
/// suspend / activate and delete users. Users are active on signup — there is
/// no approval step here.
class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _UserFilter _filter = _UserFilter.all;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(UserModel u) {
    final q = _query.trim().toLowerCase();
    final name = (u.displayName ?? '').toLowerCase();
    final email = (u.email ?? '').toLowerCase();
    if (q.isNotEmpty && !name.contains(q) && !email.contains(q)) return false;
    switch (_filter) {
      case _UserFilter.active:
        return !u.isBlocked;
      case _UserFilter.suspended:
        return u.isBlocked;
      case _UserFilter.premium:
        return _isPremium(u);
      case _UserFilter.all:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);

    return Column(
      children: [
        _searchBar(),
        _filterChips(),
        Expanded(
          child: usersAsync.when(
            loading: () => const LoadingState(message: 'Loading users...'),
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
                return EmptyState(
                  icon: Icons.people_outline,
                  message: _query.isEmpty && _filter == _UserFilter.all
                      ? 'No users found'
                      : 'No users match this search/filter',
                );
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

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search by name or email…',
            prefixIcon: const Icon(Icons.search, color: AppColors.primary),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () =>
                        setState(() { _query = ''; _searchCtrl.clear(); }),
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

  Widget _filterChips() => SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          children: [
            for (final f in _UserFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f.label),
                  selected: _filter == f,
                  showCheckmark: false,
                  selectedColor: AppColors.primary.withOpacity(0.14),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: _filter == f ? AppColors.primary : Colors.black87,
                    fontWeight:
                        _filter == f ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                      color:
                          _filter == f ? AppColors.primary : Colors.grey[300]!),
                  onSelected: (_) => setState(() => _filter = f),
                ),
              ),
          ],
        ),
      );
}

class _UserCard extends ConsumerWidget {
  final UserModel user;
  const _UserCard({required this.user});

  String get _name => (user.displayName?.trim().isNotEmpty ?? false)
      ? user.displayName!.trim()
      : (user.email ?? user.uid);

  Color get _roleColor {
    switch (user.role) {
      case 'admin':
      case 'super_admin':
        return AppColors.primary;
      case 'astrologer':
        return Colors.purple;
      default:
        return Colors.blue;
    }
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

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User'),
        content: Text(
            'Permanently delete $_name and their profile data? This cannot be undone.'),
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
    await _act(
        context, ref,
        () => ref.read(adminActionsProvider.notifier).deleteUser(user.uid),
        'User deleted.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = _isPremium(user);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _roleColor.withOpacity(0.15),
            backgroundImage: (user.photoUrl?.isNotEmpty ?? false)
                ? NetworkImage(user.photoUrl!)
                : null,
            child: (user.photoUrl?.isEmpty ?? true)
                ? Text(_name.isNotEmpty ? _name[0].toUpperCase() : '?',
                    style: TextStyle(
                        color: _roleColor, fontWeight: FontWeight.bold))
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
                      child: Text(_name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    if (premium) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.workspace_premium,
                          size: 14, color: AppColors.gold),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(user.email ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 4),
                _chip(
                  user.isBlocked ? 'SUSPENDED' : user.role.toUpperCase(),
                  user.isBlocked ? AppColors.error : _roleColor,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'view':
                  _showDetails(context);
                  break;
                case 'suspend':
                  await _act(
                      context, ref,
                      () => ref
                          .read(adminActionsProvider.notifier)
                          .blockUser(user.uid),
                      'User suspended.');
                  break;
                case 'activate':
                  await _act(
                      context, ref,
                      () => ref
                          .read(adminActionsProvider.notifier)
                          .unblockUser(user.uid),
                      'User reactivated.');
                  break;
                case 'delete':
                  await _confirmDelete(context, ref);
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'view',
                  child: ListTile(
                      leading: Icon(Icons.visibility_outlined),
                      title: Text('View Details'),
                      contentPadding: EdgeInsets.zero)),
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
              const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                      leading: Icon(Icons.delete_outline, color: AppColors.error),
                      title: Text('Delete',
                          style: TextStyle(color: AppColors.error)),
                      contentPadding: EdgeInsets.zero)),
            ],
          ),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: _roleColor.withOpacity(0.15),
                  backgroundImage: (user.photoUrl?.isNotEmpty ?? false)
                      ? NetworkImage(user.photoUrl!)
                      : null,
                  child: (user.photoUrl?.isEmpty ?? true)
                      ? Text(_name.isNotEmpty ? _name[0].toUpperCase() : '?',
                          style: TextStyle(
                              color: _roleColor, fontWeight: FontWeight.bold))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _row('Email', user.email ?? '—'),
            _row('Phone', user.phone ?? '—'),
            _row('Gender', user.gender ?? '—'),
            _row('Role', user.role),
            _row('Membership', user.membershipType),
            _row('Status', user.isBlocked ? 'Suspended' : 'Active'),
            _row('Joined', _fmtDate(user.createdAt)),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 96,
                child: Text(label,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
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

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
}
