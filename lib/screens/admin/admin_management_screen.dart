import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_account_model.dart';
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

// ── Optional filter models ────────────────────────────────────────────────────
class _UserFilters {
  String? gender;
  int? minAge;
  int? maxAge;
  String? religion;
  String? caste;
  String? district;

  _UserFilters copy() => _UserFilters()
    ..gender = gender
    ..minAge = minAge
    ..maxAge = maxAge
    ..religion = religion
    ..caste = caste
    ..district = district;

  int get count => [
        gender,
        minAge,
        maxAge,
        religion,
        caste,
        (district?.trim().isNotEmpty ?? false) ? district : null,
      ].where((e) => e != null).length;
}

class _AstroFilters {
  double? minRating;
  int? minExp;
  String? service;
  String? district;

  _AstroFilters copy() => _AstroFilters()
    ..minRating = minRating
    ..minExp = minExp
    ..service = service
    ..district = district;

  int get count => [
        minRating,
        minExp,
        service,
        (district?.trim().isNotEmpty ?? false) ? district : null,
      ].where((e) => e != null).length;
}

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
  _UserFilters _uf = _UserFilters();
  _AstroFilters _af = _AstroFilters();

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
        _filterRow(),
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

  // ── Filter row ───────────────────────────────────────────────────────────────
  Widget _filterRow() {
    final count =
        _primary == _Primary.users ? _uf.count : _af.count;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _openFilters,
            icon: const Icon(Icons.tune, size: 18),
            label: Text(count == 0 ? 'Filters' : 'Filters ($count)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(
                  color: count == 0 ? Colors.grey[300]! : AppColors.primary),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() {
                if (_primary == _Primary.users) {
                  _uf = _UserFilters();
                } else {
                  _af = _AstroFilters();
                }
                _resetPaging();
              }),
              child: const Text('Clear'),
            ),
          ],
        ],
      ),
    );
  }

  void _openFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _primary == _Primary.users
          ? _UserFiltersSheet(
              initial: _uf.copy(),
              onApply: (f) => setState(() {
                _uf = f;
                _resetPaging();
              }),
            )
          : _AstroFiltersSheet(
              initial: _af.copy(),
              onApply: (f) => setState(() {
                _af = f;
                _resetPaging();
              }),
            ),
    );
  }

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

    // Optional filters (profile-derived).
    final f = _uf;
    if (f.gender != null) {
      final g = (p?.gender ?? u.gender ?? '');
      if (g.toLowerCase() != f.gender!.toLowerCase()) return false;
    }
    final age = p?.age ?? 0;
    if (f.minAge != null && (age == 0 || age < f.minAge!)) return false;
    if (f.maxAge != null && (age == 0 || age > f.maxAge!)) return false;
    if (f.religion != null &&
        (p?.religion ?? '').toLowerCase() != f.religion!.toLowerCase()) {
      return false;
    }
    if (f.caste != null &&
        (p?.caste ?? '').toLowerCase() != f.caste!.toLowerCase()) {
      return false;
    }
    if ((f.district?.trim().isNotEmpty ?? false)) {
      final d = '${p?.district ?? ''} ${p?.city ?? ''}'.toLowerCase();
      if (!d.contains(f.district!.trim().toLowerCase())) return false;
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

    // Optional filters.
    final f = _af;
    if (f.minRating != null && a.rating < f.minRating!) return false;
    if (f.minExp != null && a.experienceYears < f.minExp!) return false;
    if (f.service != null &&
        !a.services.any((s) =>
            s.name.toLowerCase().contains(f.service!.toLowerCase())) &&
        !a.expertise
            .any((e) => e.toLowerCase().contains(f.service!.toLowerCase()))) {
      return false;
    }
    if ((f.district?.trim().isNotEmpty ?? false)) {
      final d = '${a.district} ${a.city}'.toLowerCase();
      if (!d.contains(f.district!.trim().toLowerCase())) return false;
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

Future<bool?> _confirm(BuildContext context, String title, String body) =>
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
                backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
// USER FILTERS SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _UserFiltersSheet extends StatefulWidget {
  final _UserFilters initial;
  final ValueChanged<_UserFilters> onApply;
  const _UserFiltersSheet({required this.initial, required this.onApply});

  @override
  State<_UserFiltersSheet> createState() => _UserFiltersSheetState();
}

class _UserFiltersSheetState extends State<_UserFiltersSheet> {
  late _UserFilters f = widget.initial;
  final _minAge = TextEditingController();
  final _maxAge = TextEditingController();
  final _district = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (f.minAge != null) _minAge.text = '${f.minAge}';
    if (f.maxAge != null) _maxAge.text = '${f.maxAge}';
    if (f.district != null) _district.text = f.district!;
  }

  @override
  void dispose() {
    _minAge.dispose();
    _maxAge.dispose();
    _district.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FilterScaffold(
      title: 'User Filters',
      onClear: () => Navigator.pop(context, _clear()),
      onApply: () {
        f.minAge = int.tryParse(_minAge.text.trim());
        f.maxAge = int.tryParse(_maxAge.text.trim());
        f.district =
            _district.text.trim().isEmpty ? null : _district.text.trim();
        widget.onApply(f);
        Navigator.pop(context);
      },
      children: [
        _label('Gender'),
        Wrap(spacing: 8, children: [
          for (final g in ['Male', 'Female'])
            ChoiceChip(
              label: Text(g),
              selected: f.gender == g,
              onSelected: (_) =>
                  setState(() => f.gender = f.gender == g ? null : g),
            ),
        ]),
        const SizedBox(height: 14),
        _label('Age range'),
        Row(children: [
          Expanded(child: _num(_minAge, 'Min')),
          const SizedBox(width: 12),
          Expanded(child: _num(_maxAge, 'Max')),
        ]),
        const SizedBox(height: 14),
        _dropdown('Religion', AppConstants.religions, f.religion,
            (v) => setState(() => f.religion = v)),
        const SizedBox(height: 14),
        _dropdown('Caste', AppConstants.castes, f.caste,
            (v) => setState(() => f.caste = v)),
        const SizedBox(height: 14),
        _label('District'),
        _text(_district, 'e.g. Chennai'),
      ],
    );
  }

  void _onClearControllers() {
    _minAge.clear();
    _maxAge.clear();
    _district.clear();
  }

  _UserFilters _clear() {
    _onClearControllers();
    final empty = _UserFilters();
    widget.onApply(empty);
    return empty;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ASTROLOGER FILTERS SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _AstroFiltersSheet extends StatefulWidget {
  final _AstroFilters initial;
  final ValueChanged<_AstroFilters> onApply;
  const _AstroFiltersSheet({required this.initial, required this.onApply});

  @override
  State<_AstroFiltersSheet> createState() => _AstroFiltersSheetState();
}

class _AstroFiltersSheetState extends State<_AstroFiltersSheet> {
  late _AstroFilters f = widget.initial;
  final _minExp = TextEditingController();
  final _district = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (f.minExp != null) _minExp.text = '${f.minExp}';
    if (f.district != null) _district.text = f.district!;
  }

  @override
  void dispose() {
    _minExp.dispose();
    _district.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FilterScaffold(
      title: 'Astrologer Filters',
      onClear: () {
        _minExp.clear();
        _district.clear();
        final empty = _AstroFilters();
        widget.onApply(empty);
        Navigator.pop(context);
      },
      onApply: () {
        f.minExp = int.tryParse(_minExp.text.trim());
        f.district =
            _district.text.trim().isEmpty ? null : _district.text.trim();
        widget.onApply(f);
        Navigator.pop(context);
      },
      children: [
        _label('Minimum rating'),
        Wrap(spacing: 8, children: [
          for (final r in [3.0, 4.0, 4.5])
            ChoiceChip(
              label: Text('${r.toStringAsFixed(r == r.roundToDouble() ? 0 : 1)}★+'),
              selected: f.minRating == r,
              onSelected: (_) =>
                  setState(() => f.minRating = f.minRating == r ? null : r),
            ),
        ]),
        const SizedBox(height: 14),
        _label('Minimum experience (years)'),
        _num(_minExp, 'e.g. 5'),
        const SizedBox(height: 14),
        _dropdown('Service', AppConstants.astrologerSpecializations, f.service,
            (v) => setState(() => f.service = v)),
        const SizedBox(height: 14),
        _label('District'),
        _text(_district, 'e.g. Madurai'),
      ],
    );
  }
}

// ── Filter sheet building blocks ──────────────────────────────────────────────
class _FilterScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final VoidCallback onApply;
  final VoidCallback onClear;
  const _FilterScaffold(
      {required this.title,
      required this.children,
      required this.onApply,
      required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('All filters are optional.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onClear,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    child: const Text('Clear All'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onApply,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48)),
                    child: const Text('Apply Filters'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
    );

Widget _num(TextEditingController c, String hint) => TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

Widget _text(TextEditingController c, String hint) => TextField(
      controller: c,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

Widget _dropdown(String label, List<String> options, String? value,
        ValueChanged<String?> onChanged) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          hint: const Text('Any'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Any')),
            for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: onChanged,
        ),
      ],
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

          _section('Certificates', Icons.workspace_premium_outlined, [
            _r('Uploaded', '${a.certificates.length} document(s)'),
            if (a.certName.isNotEmpty) _r('Name', a.certName),
            if (a.certOrg.isNotEmpty) _r('Issued by', a.certOrg),
          ]),

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
