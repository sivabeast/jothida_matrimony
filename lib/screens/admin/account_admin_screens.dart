import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/account_provider.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/common/data_states.dart';
import '../../widgets/common/network_photo.dart';
import '../../widgets/common/skeletons.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Admin → Married Members (spec §17–§20)
// ─────────────────────────────────────────────────────────────────────────────

/// Every member who has marked themselves Married in the app.
///
/// The list is fed straight from the profile documents (`isMarried == true`),
/// so it updates the moment a member taps "Married" in Find Partner — there is
/// no separate admin-side flag to keep in sync, and nothing here is sample
/// data (spec §18/§20).
///
/// Ordered by WHEN the member married, newest first, which is what makes
/// "Recently Married" meaningful. Profiles marked before `marriedAt` was
/// stamped have no date; they sort last rather than being dropped.
class MarriedUsersScreen extends ConsumerWidget {
  const MarriedUsersScreen({super.key});

  static String _date(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}'
        ' · ${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'
        ' ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[Admin] MarriedUsers build — /admin/married');
    final marriedAsync = ref.watch(marriedProfilesProvider);
    final stats = ref.watch(adminStatsProvider).valueOrNull ?? const {};

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Married Members'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(marriedProfilesProvider);
              ref.invalidate(adminStatsProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(marriedProfilesProvider);
          ref.invalidate(adminStatsProvider);
        },
        child: marriedAsync.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: const [SkeletonList(items: 6)],
          ),
          error: (e, _) {
            debugPrint('[Admin] married users load failed: $e');
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                ErrorStateView(
                  message: 'Unable to load married members. Please try again.',
                  onRetry: () => ref.invalidate(marriedProfilesProvider),
                ),
              ],
            );
          },
          data: (list) => _body(context, list, stats),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, List<ProfileModel> raw,
      Map<String, dynamic> stats) {
    // Newest marriage first; undated legacy records fall to the bottom.
    final list = [...raw]..sort((a, b) {
        final x = a.marriedAt, y = b.marriedAt;
        if (x == null && y == null) return a.fullName.compareTo(b.fullName);
        if (x == null) return 1;
        if (y == null) return -1;
        return y.compareTo(x);
      });

    // Every number below comes from real data. `marriedUsers` is the
    // collection-wide count from the admin stats pass, which is authoritative
    // even when this page's own query is capped; the fetched list is the
    // fallback when the stats pass has not resolved yet.
    final statCount = stats['marriedUsers'];
    final totalMarried =
        statCount is int && statCount > 0 ? statCount : list.length;
    final totalProfiles = (stats['totalProfiles'] is int)
        ? stats['totalProfiles'] as int
        : 0;
    // Share of all registered profiles that ended in a marriage. Undefined
    // rather than 0% when there are no profiles at all — printing "0.0%" for
    // an empty database states something the data does not support.
    final successRate = totalProfiles > 0
        ? '${((totalMarried / totalProfiles) * 100).toStringAsFixed(1)}%'
        : '—';

    final now = DateTime.now();
    final last30 = list
        .where((p) =>
            p.marriedAt != null && now.difference(p.marriedAt!).inDays <= 30)
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(
              child: _statTile('Total Married', '$totalMarried',
                  Icons.celebration, AppColors.gold)),
          const SizedBox(width: 12),
          Expanded(
              child: _statTile('Success Rate', successRate, Icons.favorite,
                  AppColors.primary,
                  hint: totalProfiles > 0 ? 'of $totalProfiles profiles' : null)),
        ]),
        const SizedBox(height: 12),
        _statTile('Married in the last 30 days', '$last30',
            Icons.event_available_outlined, AppColors.success,
            wide: true),
        const SizedBox(height: 18),
        const Text('Recently Married',
            style: TextStyle(
                fontSize: 15,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                color: AppColors.primary)),
        const SizedBox(height: 10),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 30),
            child: EmptyState(
              icon: Icons.favorite_border,
              message: 'No married members yet',
              subtitle: 'Members who mark themselves as Married appear here.',
            ),
          )
        else
          ...list.map((p) => _MarriedMemberTile(profile: p)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color,
          {String? hint, bool wide = false}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)
          ],
        ),
        child: wide
            ? Row(children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black87))),
                Text(value,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color, size: 22),
                  const SizedBox(height: 8),
                  Text(value,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  Text(label,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (hint != null)
                    Text(hint,
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey[400])),
                ],
              ),
      );
}

/// One married member: photo, name, age, location, profile id and the date
/// they were marked Married. Tapping opens the full admin user detail page —
/// the same page every other admin list opens, so there is one place where a
/// member's complete record lives (spec §19).
class _MarriedMemberTile extends StatelessWidget {
  final ProfileModel profile;
  const _MarriedMemberTile({required this.profile});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final photo = p.profilePhotoUrl ?? '';
    final location = [p.city, p.district, p.state]
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // The admin user page is keyed by the ACCOUNT uid, not the profile
          // document id.
          onTap: p.userId.trim().isEmpty
              ? null
              : () => context.push('/admin/user/${p.userId}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 58,
                    height: 58,
                    child: photo.isEmpty
                        ? Container(
                            color: const Color(0x22D4AF37),
                            alignment: Alignment.center,
                            child: const Text('🎉',
                                style: TextStyle(fontSize: 20)),
                          )
                        : NetworkPhoto(url: photo, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(p.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14.5)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.favorite,
                                    size: 11, color: AppColors.gold),
                                SizedBox(width: 4),
                                Text('MARRIED',
                                    style: TextStyle(
                                        color: AppColors.gold,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold)),
                              ]),
                        ),
                      ]),
                      const SizedBox(height: 3),
                      Text(
                          '${p.age > 0 ? '${p.age} yrs' : '—'}'
                          ' • ${location.isEmpty ? '—' : location}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5, color: Colors.grey[700])),
                      const SizedBox(height: 4),
                      _meta(Icons.badge_outlined, 'Profile ID', p.id),
                      _meta(
                          Icons.event_outlined,
                          'Marked Married',
                          p.marriedAt == null
                              ? 'Date not recorded'
                              : MarriedUsersScreen._date(p.marriedAt!)),
                      if (p.marriedVia.trim().isNotEmpty)
                        _meta(
                            Icons.favorite_border,
                            'Found partner',
                            p.marriedVia == 'app'
                                ? 'Through Jothida Matrimony'
                                : 'Outside the app'),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Icon(icon, size: 12, color: Colors.grey[500]),
            const SizedBox(width: 5),
            Text('$label: ',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            Expanded(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800])),
            ),
          ],
        ),
      );
}
