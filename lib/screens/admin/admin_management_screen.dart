import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_account_model.dart';
import '../../models/astrologer_certificate.dart';
import '../../models/profile_model.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../screens/family/family_tree_screen.dart';
import '../../widgets/common/data_states.dart';

// ── Tab models ────────────────────────────────────────────────────────────────
enum _Primary { users, astrologers }

enum _UserPlan { all, free, basic, medium, premium }

enum _AstroCat { all, free, basic, premium, verified }

extension on _UserPlan {
  String get label => switch (this) {
        _UserPlan.all => 'All',
        _UserPlan.free => 'Free Plan',
        _UserPlan.basic => 'Basic Plan',
        _UserPlan.medium => 'Medium Plan',
        _UserPlan.premium => 'Premium Plan',
      };
  String? get membership => switch (this) {
        _UserPlan.all => null,
        _UserPlan.free => 'free',
        _UserPlan.basic => 'basic',
        _UserPlan.medium => 'medium',
        _UserPlan.premium => 'premium',
      };
}

extension on _AstroCat {
  String get label => switch (this) {
        _AstroCat.all => 'All',
        _AstroCat.free => 'Free Plan',
        _AstroCat.basic => 'Basic Plan',
        _AstroCat.premium => 'Premium Plan',
        _AstroCat.verified => 'Verified',
      };
}

/// Plan badge (label + colour) for a user's `membershipType`.
(String, Color) _userPlanStyle(String m) => switch (m) {
      'premium' => ('Premium', AppColors.premiumPlan),
      'medium' => ('Medium', AppColors.warning),
      'basic' => ('Basic', Color(0xFF2F80ED)),
      _ => ('Free', Colors.grey),
    };

/// Astrologer subscription ('' | monthly | yearly) → Free / Basic / Premium.
(String, Color) _astroPlanStyle(String p) => switch (p) {
      'yearly' => ('Premium', AppColors.premiumPlan),
      'monthly' => ('Basic', Color(0xFF2F80ED)),
      _ => ('Free', Colors.grey),
    };

/// Unified Admin → Management page. One screen manages both **Users** and
/// **Astrologers** via a primary segmented toggle, each with its own secondary
/// plan/category tabs, a shared search bar, optional filters, pull-to-refresh
/// and client-side pagination.
class AdminManagementScreen extends ConsumerStatefulWidget {
  /// 'users' (default) or 'astrologers' — which primary tab opens first. Lets
  /// the Users / Astrologers bottom-nav destinations deep-link the same screen.
  final String initialTab;
  const AdminManagementScreen({super.key, this.initialTab = 'users'});

  @override
  ConsumerState<AdminManagementScreen> createState() =>
      _AdminManagementScreenState();
}

class _AdminManagementScreenState extends ConsumerState<AdminManagementScreen> {
  final _searchCtrl = TextEditingController();
  late _Primary _primary;
  String _query = '';
  _UserPlan _userPlan = _UserPlan.all;
  _AstroCat _astroCat = _AstroCat.all;

  static const _pageSize = 15;
  int _visible = _pageSize;

  @override
  void initState() {
    super.initState();
    _primary =
        widget.initialTab == 'astrologers' ? _Primary.astrologers : _Primary.users;
  }

  @override
  void didUpdateWidget(covariant AdminManagementScreen old) {
    super.didUpdateWidget(old);
    // Re-deep-link when the bottom-nav destination changes the initial tab.
    if (old.initialTab != widget.initialTab) {
      setState(() {
        _primary = widget.initialTab == 'astrologers'
            ? _Primary.astrologers
            : _Primary.users;
        _resetPaging();
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _resetPaging() => _visible = _pageSize;

  Future<void> _refresh() async {
    if (_primary == _Primary.users) {
      ref.invalidate(allUsersProvider);
      ref.invalidate(allProfilesProvider);
      ref.invalidate(profilesByUserIdProvider);
    } else {
      ref.invalidate(allAstrologersProvider);
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _searchBar(),
        _primaryToggle(),
        const SizedBox(height: 8),
        _secondaryTabs(),
        const SizedBox(height: 4),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _refresh,
            child: _primary == _Primary.users
                ? _usersList()
                : _astrologersList(),
          ),
        ),
      ],
    );
  }

  // ── Search ──────────────────────────────────────────────────────────────────
  Widget _searchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() {
            _query = v;
            _resetPaging();
          }),
          decoration: InputDecoration(
            hintText: _primary == _Primary.users
                ? 'Search name, email or phone…'
                : 'Search name, phone or location…',
            prefixIcon: const Icon(Icons.search, color: AppColors.primary),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      _query = '';
                      _searchCtrl.clear();
                      _resetPaging();
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

  // ── Primary segmented toggle (Users | Astrologers) ───────────────────────────
  Widget _primaryToggle() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            children: [
              _segment('Users', Icons.people, _primary == _Primary.users,
                  () => _switchPrimary(_Primary.users)),
              _segment('Astrologers', Icons.auto_awesome,
                  _primary == _Primary.astrologers,
                  () => _switchPrimary(_Primary.astrologers)),
            ],
          ),
        ),
      );

  void _switchPrimary(_Primary p) {
    if (_primary == p) return;
    setState(() {
      _primary = p;
      _resetPaging();
    });
  }

  Widget _segment(String label, IconData icon, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 17, color: active ? Colors.white : Colors.grey[600]),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: active ? Colors.white : Colors.grey[700],
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Secondary category tabs ──────────────────────────────────────────────────
  Widget _secondaryTabs() {
    final chips = _primary == _Primary.users
        ? [
            for (final p in _UserPlan.values)
              _catChip(p.label, _userPlan == p, () {
                setState(() {
                  _userPlan = p;
                  _resetPaging();
                });
              })
          ]
        : [
            for (final c in _AstroCat.values)
              _catChip(c.label, _astroCat == c, () {
                setState(() {
                  _astroCat = c;
                  _resetPaging();
                });
              })
          ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: chips,
      ),
    );
  }

  Widget _catChip(String label, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: active,
          showCheckmark: false,
          selectedColor: AppColors.primary.withOpacity(0.14),
          backgroundColor: Colors.white,
          labelStyle: TextStyle(
            color: active ? AppColors.primary : Colors.black87,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
          side: BorderSide(color: active ? AppColors.primary : Colors.grey[300]!),
          onSelected: (_) => onTap(),
        ),
      );

  // ── Users list ───────────────────────────────────────────────────────────────
  Widget _usersList() {
    final usersAsync = ref.watch(allUsersProvider);
    final profileMap =
        ref.watch(profilesByUserIdProvider).valueOrNull ?? const {};

    return usersAsync.when(
      loading: () => const LoadingState(message: 'Loading users...'),
      error: (e, _) {
        debugPrint('[AdminManagement] users load failed: $e');
        return ErrorStateView(
          message: 'Connection Error — unable to load users.',
          onRetry: () => ref.invalidate(allUsersProvider),
        );
      },
      data: (all) {
        final filtered =
            all.where((u) => _userMatches(u, profileMap[u.uid])).toList();
        if (filtered.isEmpty) {
          return _empty(Icons.people_outline, 'No matching users found.');
        }
        final shown = filtered.take(_visible).toList();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: shown.length + (filtered.length > shown.length ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            if (i >= shown.length) {
              return _loadMore(filtered.length - shown.length);
            }
            final u = shown[i];
            return _UserCard(
              user: u,
              profile: profileMap[u.uid],
              onChanged: _refresh,
            );
          },
        );
      },
    );
  }

  bool _userMatches(UserModel u, ProfileModel? p) {
    // Astrologer accounts are managed under the Astrologers tab — keep them out
    // of the Users list so the same person never appears in both.
    if (u.role == 'astrologer') return false;

    // Plan tab.
    final plan = _userPlan.membership;
    if (plan != null && u.membershipType != plan) return false;

    // Search (name / email / phone).
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final name = ((p?.fullName.trim().isNotEmpty ?? false)
              ? p!.fullName
              : (u.displayName ?? ''))
          .toLowerCase();
      final email = (u.email ?? '').toLowerCase();
      final phone = (u.phone ?? p?.contact.mobileNumber ?? '').toLowerCase();
      if (!name.contains(q) && !email.contains(q) && !phone.contains(q)) {
        return false;
      }
    }
    return true;
  }

  // ── Astrologers list ─────────────────────────────────────────────────────────
  Widget _astrologersList() {
    final astroAsync = ref.watch(allAstrologersProvider);
    return astroAsync.when(
      loading: () => const LoadingState(message: 'Loading astrologers...'),
      error: (e, _) {
        debugPrint('[AdminManagement] astrologers load failed: $e');
        return ErrorStateView(
          message: 'Connection Error — unable to load astrologers.',
          onRetry: () => ref.invalidate(allAstrologersProvider),
        );
      },
      data: (all) {
        final filtered = all.where(_astroMatches).toList()
          ..sort((a, b) => (b.createdAt ?? DateTime(0))
              .compareTo(a.createdAt ?? DateTime(0)));
        if (filtered.isEmpty) {
          return _empty(
              Icons.auto_awesome_outlined, 'No matching astrologers found.');
        }
        final shown = filtered.take(_visible).toList();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: shown.length + (filtered.length > shown.length ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            if (i >= shown.length) {
              return _loadMore(filtered.length - shown.length);
            }
            return _AstroCard(astrologer: shown[i], onChanged: _refresh);
          },
        );
      },
    );
  }

  bool _astroMatches(AstrologerAccount a) {
    // Category tab.
    switch (_astroCat) {
      case _AstroCat.all:
        break;
      case _AstroCat.verified:
        if (a.status != VerificationStatus.approved) return false;
        break;
      case _AstroCat.free:
        if (a.subscriptionPlan.isNotEmpty) return false;
        break;
      case _AstroCat.basic:
        if (a.subscriptionPlan != 'monthly') return false;
        break;
      case _AstroCat.premium:
        if (a.subscriptionPlan != 'yearly') return false;
        break;
    }

    // Search (name / phone / location).
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final loc = '${a.city} ${a.district} ${a.state}'.toLowerCase();
      if (!a.fullName.toLowerCase().contains(q) &&
          !a.mobile.toLowerCase().contains(q) &&
          !loc.contains(q)) {
        return false;
      }
    }
    return true;
  }

  // ── Shared bits ──────────────────────────────────────────────────────────────
  Widget _loadMore(int remaining) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Center(
          child: OutlinedButton(
            onPressed: () => setState(() => _visible += _pageSize),
            style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary)),
            child: Text('Load More ($remaining)'),
          ),
        ),
      );

  Widget _empty(IconData icon, String msg) => ListView(
        // ListView so RefreshIndicator still works on an empty result.
        children: [
          const SizedBox(height: 80),
          EmptyState(icon: icon, message: msg),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// USER CARD
// ─────────────────────────────────────────────────────────────────────────────
class _UserCard extends ConsumerWidget {
  final UserModel user;
  final ProfileModel? profile;
  final Future<void> Function() onChanged;
  const _UserCard(
      {required this.user, required this.profile, required this.onChanged});

  String get _name => (profile?.fullName.trim().isNotEmpty ?? false)
      ? profile!.fullName.trim()
      : (user.displayName?.trim().isNotEmpty ?? false)
          ? user.displayName!.trim()
          : (user.email ?? user.uid);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo =
        profile?.profilePhotoUrl?.trim().isNotEmpty == true
            ? profile!.profilePhotoUrl!
            : (user.photoUrl ?? '');
    final age = profile?.age ?? 0;
    final gender = profile?.gender ?? user.gender ?? '';
    final district =
        [profile?.district ?? '', profile?.city ?? '', profile?.state ?? '']
            .firstWhere((s) => s.trim().isNotEmpty, orElse: () => '');
    final (planLabel, planColor) = _userPlanStyle(user.membershipType);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openProfile(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.primary.withOpacity(0.12),
                  backgroundImage:
                      photo.isNotEmpty ? NetworkImage(photo) : null,
                  child: photo.isEmpty
                      ? Text(_name[0].toUpperCase(),
                          style: const TextStyle(
                              color: AppColors.primary,
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
                            child: Text(_name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                          if (user.isBlocked) ...[
                            const SizedBox(width: 6),
                            _miniChip('SUSPENDED', AppColors.error),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (age > 0) '$age yrs',
                          if (gender.isNotEmpty) gender,
                        ].join(' • '),
                        style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
                      ),
                      if (district.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 13, color: Colors.grey[500]),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(district,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600])),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                _planBadge(planLabel, planColor),
                _menu(context, ref),
              ],
            ),
            const Divider(height: 18),
            Row(
              children: [
                Expanded(
                  child: _kv(Icons.mail_outline, user.email ?? '—'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                    child: _kv(Icons.call_outlined,
                        user.phone ?? profile?.contact.mobileNumber ?? '—')),
                _kv(Icons.event_outlined, _fmtDate(user.createdAt)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (v) => _onAction(context, ref, v),
        itemBuilder: (_) => [
          _item('view', Icons.visibility_outlined, 'View Profile'),
          _item('edit', Icons.edit_outlined, 'Edit User'),
          if (user.isBlocked)
            _item('activate', Icons.lock_open_outlined, 'Activate')
          else
            _item('suspend', Icons.block_outlined, 'Suspend User'),
          _item('delete', Icons.delete_outline, 'Delete User',
              color: AppColors.error),
        ],
      );

  Future<void> _onAction(
      BuildContext context, WidgetRef ref, String v) async {
    switch (v) {
      case 'view':
        _openProfile(context);
        break;
      case 'edit':
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Inline edit is coming soon.')));
        break;
      case 'suspend':
        await _run(context, ref,
            () => ref.read(adminActionsProvider.notifier).blockUser(user.uid),
            'User suspended.');
        break;
      case 'activate':
        await _run(context, ref,
            () => ref.read(adminActionsProvider.notifier).unblockUser(user.uid),
            'User reactivated.');
        break;
      case 'delete':
        await _confirmDelete(context, ref);
        break;
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(context,
        'Delete User', 'Are you sure you want to permanently delete $_name?');
    if (ok != true || !context.mounted) return;
    await _run(
        context,
        ref,
        () => ref.read(adminActionsProvider.notifier).deleteUser(user.uid),
        'User permanently deleted.');
  }

  Future<void> _run(BuildContext context, WidgetRef ref,
      Future<void> Function() action, String okMsg) async {
    final messenger = ScaffoldMessenger.of(context);
    await action();
    final st = ref.read(adminActionsProvider);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError ? 'Action failed. Please try again.' : okMsg),
      backgroundColor: st.hasError ? AppColors.error : null,
    ));
    await onChanged();
  }

  void _openProfile(BuildContext context) {
    showAdminUserProfile(context, user, profile, onChanged);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ASTROLOGER CARD
// ─────────────────────────────────────────────────────────────────────────────
class _AstroCard extends ConsumerWidget {
  final AstrologerAccount astrologer;
  final Future<void> Function() onChanged;
  const _AstroCard({required this.astrologer, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = astrologer;
    final verified = a.status == VerificationStatus.approved;
    final (planLabel, planColor) = _astroPlanStyle(a.subscriptionPlan);
    final location = [a.district, a.city, a.state]
        .firstWhere((s) => s.trim().isNotEmpty, orElse: () => '');

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showAdminAstrologerProfile(context, a, onChanged),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.gold.withOpacity(0.15),
              backgroundImage:
                  a.photoUrl.isNotEmpty ? NetworkImage(a.photoUrl) : null,
              child: a.photoUrl.isEmpty
                  ? const Icon(Icons.auto_awesome, color: AppColors.gold)
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
                            a.fullName.isEmpty ? 'Astrologer' : a.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      if (verified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified,
                            size: 15, color: AppColors.success),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 13, color: AppColors.gold),
                      const SizedBox(width: 2),
                      Text('${a.rating.toStringAsFixed(1)} (${a.reviewCount})',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[700])),
                      const SizedBox(width: 10),
                      Icon(Icons.work_history_outlined,
                          size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 2),
                      Text('${a.experienceYears} yrs',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[700])),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.design_services_outlined,
                          size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 2),
                      Text('${a.services.length} services',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600])),
                      if (location.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.location_on_outlined,
                            size: 13, color: Colors.grey[500]),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600])),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _planBadge(planLabel, planColor),
                      const SizedBox(width: 6),
                      _miniChip(
                          verified ? 'VERIFIED' : a.status.name.toUpperCase(),
                          verified ? AppColors.success : AppColors.warning),
                    ],
                  ),
                ],
              ),
            ),
            _menu(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _menu(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (v) => _onAction(context, ref, v),
        itemBuilder: (_) => [
          _item('view', Icons.visibility_outlined, 'View Profile'),
          if (astrologer.status != VerificationStatus.approved)
            _item('verify', Icons.verified_outlined, 'Verify Astrologer',
                color: AppColors.success),
          if (astrologer.status != VerificationStatus.rejected)
            _item('reject', Icons.cancel_outlined, 'Reject Astrologer',
                color: AppColors.warning),
          _item('suspend', Icons.block_outlined, 'Suspend Astrologer'),
          _item('delete', Icons.delete_outline, 'Delete Astrologer',
              color: AppColors.error),
        ],
      );

  Future<void> _onAction(
      BuildContext context, WidgetRef ref, String v) async {
    final uid = astrologer.id;
    switch (v) {
      case 'view':
        showAdminAstrologerProfile(context, astrologer, onChanged);
        break;
      case 'verify':
        await _run(context, ref,
            () => ref.read(adminActionsProvider.notifier).approveAstrologer(uid),
            'Astrologer verified.');
        break;
      case 'reject':
        final ok = await _confirm(context, 'Reject Astrologer',
            'Reject ${astrologer.fullName}\'s verification? They will not appear to users.',
            confirmLabel: 'Reject', confirmColor: AppColors.warning);
        if (ok != true || !context.mounted) return;
        await _run(context, ref,
            () => ref.read(adminActionsProvider.notifier).rejectAstrologer(uid),
            'Astrologer rejected.');
        break;
      case 'suspend':
        await _run(context, ref,
            () => ref.read(adminActionsProvider.notifier).suspendAstrologer(uid),
            'Astrologer suspended.');
        break;
      case 'delete':
        final ok = await _confirm(context, 'Delete Astrologer',
            'Are you sure you want to permanently delete ${astrologer.fullName}?');
        if (ok != true || !context.mounted) return;
        await _run(context, ref,
            () => ref.read(adminActionsProvider.notifier).deleteAstrologer(uid),
            'Astrologer permanently deleted.');
        break;
    }
  }

  Future<void> _run(BuildContext context, WidgetRef ref,
      Future<void> Function() action, String okMsg) async {
    final messenger = ScaffoldMessenger.of(context);
    await action();
    final st = ref.read(adminActionsProvider);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError ? 'Action failed. Please try again.' : okMsg),
      backgroundColor: st.hasError ? AppColors.error : null,
    ));
    await onChanged();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets / helpers
// ─────────────────────────────────────────────────────────────────────────────
PopupMenuItem<String> _item(String value, IconData icon, String label,
        {Color? color}) =>
    PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 19, color: color ?? Colors.black54),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );

Widget _planBadge(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10.5, fontWeight: FontWeight.bold)),
    );

Widget _miniChip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );

Widget _kv(IconData icon, String value) => Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 5),
        Flexible(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ),
      ],
    );

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

Future<bool?> _confirm(BuildContext context, String title, String body,
        {String confirmLabel = 'Delete', Color? confirmColor}) =>
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor ?? AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
// FULL PROFILE SHEETS (tap card / "View Profile")
// ─────────────────────────────────────────────────────────────────────────────
void showAdminUserProfile(BuildContext context, UserModel user,
    ProfileModel? profile, Future<void> Function() onChanged) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.scaffoldBg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _AdminUserProfileSheet(
        user: user, profile: profile, onChanged: onChanged),
  );
}

class _AdminUserProfileSheet extends ConsumerWidget {
  final UserModel user;
  final ProfileModel? profile;
  final Future<void> Function() onChanged;
  const _AdminUserProfileSheet(
      {required this.user, required this.profile, required this.onChanged});

  String get _name => (profile?.fullName.trim().isNotEmpty ?? false)
      ? profile!.fullName.trim()
      : (user.displayName ?? user.email ?? user.uid);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final photo = p?.profilePhotoUrl?.trim().isNotEmpty == true
        ? p!.profilePhotoUrl!
        : (user.photoUrl ?? '');
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Center(
            child: Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 14),
          // Header
          Column(
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: AppColors.primary.withOpacity(0.12),
                backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                child: photo.isEmpty
                    ? const Icon(Icons.person,
                        size: 42, color: AppColors.primary)
                    : null,
              ),
              const SizedBox(height: 10),
              Text(_name,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(
                  [
                    if ((p?.age ?? 0) > 0) '${p!.age} yrs',
                    if ((p?.gender ?? user.gender ?? '').isNotEmpty)
                      (p?.gender ?? user.gender),
                  ].whereType<String>().join(' • '),
                  style: TextStyle(color: Colors.grey[600])),
              _statusPill(user.isBlocked ? 'Suspended' : 'Active',
                  user.isBlocked ? AppColors.error : AppColors.success),
            ],
          ),
          const SizedBox(height: 18),

          _section('Personal Details', Icons.person_outline, [
            _r('Name', _name),
            _r('Phone', user.phone ?? p?.contact.mobileNumber ?? '—'),
            _r('Email', user.email ?? '—'),
            _r('Religion', p?.religion ?? '—'),
            _r('Caste', p?.caste ?? '—'),
            _r('Education', p?.education ?? '—'),
            _r('Occupation', p?.occupation ?? '—'),
            _r('Annual Income', p?.annualIncome ?? '—'),
          ]),

          if (p != null)
            _section('Horoscope Details', Icons.auto_awesome_outlined, [
              _r('Rasi', _orDash(p.horoscope.rasi)),
              _r('Nakshatra', _orDash(p.horoscope.nakshatra)),
              _r('Lagnam', _orDash(p.horoscope.lagnam)),
              _r('Dosham', _orDash(p.horoscope.dosham)),
            ]),

          _section('Subscription', Icons.workspace_premium_outlined, [
            _r('Current Plan', _userPlanStyle(user.membershipType).$1),
            _r('Joined', _fmtDate(user.createdAt)),
            if (user.subscriptionExpiry != null)
              _r('Expires', _fmtDate(user.subscriptionExpiry!)),
          ]),

          if (p != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4, bottom: 8),
              child: Row(children: const [
                Icon(Icons.account_tree_outlined,
                    size: 18, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Family Tree',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ]),
            ),
            FamilyTreeView(family: p.family, personName: p.fullName),
          ],

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    final notifier = ref.read(adminActionsProvider.notifier);
                    if (user.isBlocked) {
                      await notifier.unblockUser(user.uid);
                    } else {
                      await notifier.blockUser(user.uid);
                    }
                    await onChanged();
                  },
                  icon: Icon(
                      user.isBlocked ? Icons.lock_open : Icons.block,
                      size: 18),
                  label: Text(user.isBlocked ? 'Activate' : 'Suspend'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.warning,
                      side: const BorderSide(color: AppColors.warning),
                      minimumSize: const Size.fromHeight(46)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final ok = await _confirm(context, 'Delete User',
                        'Are you sure you want to permanently delete $_name?');
                    if (ok != true || !context.mounted) return;
                    Navigator.pop(context);
                    await ref
                        .read(adminActionsProvider.notifier)
                        .deleteUser(user.uid);
                    await onChanged();
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void showAdminAstrologerProfile(BuildContext context, AstrologerAccount a,
    Future<void> Function() onChanged) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.scaffoldBg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _AdminAstroProfileSheet(a: a, onChanged: onChanged),
  );
}

class _AdminAstroProfileSheet extends ConsumerWidget {
  final AstrologerAccount a;
  final Future<void> Function() onChanged;
  const _AdminAstroProfileSheet({required this.a, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verified = a.status == VerificationStatus.approved;
    final services = a.services.isNotEmpty
        ? a.services.map((s) => s.name).toList()
        : a.expertise;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Center(
            child: Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 14),
          Column(
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: AppColors.gold.withOpacity(0.15),
                backgroundImage:
                    a.photoUrl.isNotEmpty ? NetworkImage(a.photoUrl) : null,
                child: a.photoUrl.isEmpty
                    ? const Icon(Icons.auto_awesome,
                        size: 40, color: AppColors.gold)
                    : null,
              ),
              const SizedBox(height: 10),
              Text(a.fullName.isEmpty ? 'Astrologer' : a.fullName,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, size: 16, color: AppColors.gold),
                  const SizedBox(width: 3),
                  Text('${a.rating.toStringAsFixed(1)}  •  ${a.reviewCount} reviews',
                      style: TextStyle(color: Colors.grey[700])),
                ],
              ),
              _statusPill(verified ? 'Verified' : a.status.label,
                  verified ? AppColors.success : AppColors.warning),
            ],
          ),
          const SizedBox(height: 18),

          _section('Basic Details', Icons.info_outline, [
            _r('Experience', '${a.experienceYears} years'),
            _r('Languages',
                a.languages.isEmpty ? '—' : a.languages.join(', ')),
            _r('Plan', _astroPlanStyle(a.subscriptionPlan).$1),
            _r('Registered', a.createdAt == null ? '—' : _fmtDate(a.createdAt!)),
          ]),

          _sectionWrap('Services', Icons.design_services_outlined,
              services.isEmpty ? const [Text('—')] : [
            for (final s in services)
              Chip(
                label: Text(s, style: const TextStyle(fontSize: 12)),
                backgroundColor: AppColors.primary.withOpacity(0.06),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              ),
          ]),

          _certificatesCard(a),

          _section('Contact Details', Icons.call_outlined, [
            _r('Name', a.fullName),
            _r('Phone', a.mobile.isEmpty ? '—' : a.mobile),
            _r('WhatsApp', a.mobile.isEmpty ? '—' : a.mobile),
            _r('Location',
                [a.district, a.city, a.state].where((s) => s.isNotEmpty).join(', ')),
          ]),

          _section('Ratings', Icons.reviews_outlined, [
            _r('Average Rating', a.rating.toStringAsFixed(1)),
            _r('Review Count', '${a.reviewCount}'),
          ]),

          const SizedBox(height: 20),
          if (!verified)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await ref
                        .read(adminActionsProvider.notifier)
                        .approveAstrologer(a.id);
                    await onChanged();
                  },
                  icon: const Icon(Icons.verified, size: 18),
                  label: const Text('Verify Astrologer'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
          if (a.status != VerificationStatus.rejected)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await _confirm(context, 'Reject Astrologer',
                        'Reject ${a.fullName}\'s verification?',
                        confirmLabel: 'Reject', confirmColor: AppColors.warning);
                    if (ok != true || !context.mounted) return;
                    Navigator.pop(context);
                    await ref
                        .read(adminActionsProvider.notifier)
                        .rejectAstrologer(a.id);
                    await onChanged();
                  },
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Reject Astrologer'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.warning,
                      side: const BorderSide(color: AppColors.warning),
                      minimumSize: const Size.fromHeight(46)),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await ref
                        .read(adminActionsProvider.notifier)
                        .suspendAstrologer(a.id);
                    await onChanged();
                  },
                  icon: const Icon(Icons.block, size: 18),
                  label: const Text('Suspend'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.warning,
                      side: const BorderSide(color: AppColors.warning),
                      minimumSize: const Size.fromHeight(46)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final ok = await _confirm(context, 'Delete Astrologer',
                        'Are you sure you want to permanently delete ${a.fullName}?');
                    if (ok != true || !context.mounted) return;
                    Navigator.pop(context);
                    await ref
                        .read(adminActionsProvider.notifier)
                        .deleteAstrologer(a.id);
                    await onChanged();
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Profile-sheet building blocks ─────────────────────────────────────────────
String _orDash(String? v) => (v == null || v.trim().isEmpty) ? '—' : v.trim();

Widget _statusPill(String label, Color color) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );

Widget _section(String title, IconData icon, List<Widget> rows) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );

Widget _sectionWrap(String title, IconData icon, List<Widget> chips) =>
    Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: chips),
        ],
      ),
    );

Widget _r(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13.5))),
        ],
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
// CERTIFICATES — admin review (View + Download, PDF & image)
// ─────────────────────────────────────────────────────────────────────────────
Widget _certificatesCard(AstrologerAccount a) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.workspace_premium_outlined,
                size: 18, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Certificates',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          if (a.certificates.isEmpty)
            Text('No certificates uploaded.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13))
          else
            for (final c in a.certificates) _CertTile(cert: c),
        ],
      ),
    );

/// One reviewable certificate: name · upload date · verification status, with
/// in-app **View** (image preview / PDF open) and **Download** (saves locally).
class _CertTile extends StatefulWidget {
  final AstrologerCertificate cert;
  const _CertTile({required this.cert});

  @override
  State<_CertTile> createState() => _CertTileState();
}

class _CertTileState extends State<_CertTile> {
  bool _busy = false;

  void _snack(String m, {bool error = false}) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(m),
            backgroundColor: error ? AppColors.error : null));

  @override
  Widget build(BuildContext context) {
    final c = widget.cert;
    final statusColor = c.isApproved
        ? AppColors.success
        : c.isRejected
            ? AppColors.error
            : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(c.isPdf ? Icons.picture_as_pdf : Icons.image_outlined,
                  color: AppColors.primary, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13.5)),
                    Text('Uploaded ${_fmtDate(c.uploadedAt)}',
                        style:
                            TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                  ],
                ),
              ),
              _miniChip(c.status.toUpperCase(), statusColor),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _view,
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('View'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 8)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _download,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Download'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _view() async {
    final c = widget.cert;
    if (c.url.isEmpty) {
      _snack('No file attached to this certificate.', error: true);
      return;
    }
    if (!c.isPdf) {
      // Images preview in-app.
      showDialog(
          context: context,
          builder: (_) => _ImagePreviewDialog(url: c.url, name: c.name));
      return;
    }
    // PDFs open in the device's viewer after a temp download.
    await _fetchAndOpen(temp: true);
  }

  Future<void> _download() async {
    if (widget.cert.url.isEmpty) {
      _snack('No file attached to this certificate.', error: true);
      return;
    }
    await _fetchAndOpen(temp: false);
  }

  Future<void> _fetchAndOpen({required bool temp}) async {
    final c = widget.cert;
    setState(() => _busy = true);
    try {
      final res = await http.get(Uri.parse(c.url));
      if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
      Directory dir;
      if (temp) {
        dir = await getTemporaryDirectory();
      } else {
        try {
          dir = (await getDownloadsDirectory()) ??
              await getApplicationDocumentsDirectory();
        } catch (_) {
          dir = await getApplicationDocumentsDirectory();
        }
      }
      final ext = c.fileType.isNotEmpty ? c.fileType : (c.isPdf ? 'pdf' : 'jpg');
      final base = c.name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      final fname = base.toLowerCase().endsWith('.$ext') ? base : '$base.$ext';
      final file = File('${dir.path}/$fname');
      await file.writeAsBytes(res.bodyBytes);
      if (!mounted) return;
      setState(() => _busy = false);
      if (!temp) _snack('Saved to ${file.path}');
      await OpenFile.open(file.path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Could not open the certificate. Please try again.', error: true);
    }
  }
}

class _ImagePreviewDialog extends StatelessWidget {
  final String url;
  final String name;
  const _ImagePreviewDialog({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              child: Image.network(url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(40),
                        child: Icon(Icons.broken_image,
                            color: Colors.white54, size: 64),
                      )),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            bottom: 10,
            left: 12,
            right: 12,
            child: Text(name,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
