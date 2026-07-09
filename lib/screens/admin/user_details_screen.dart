import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';

/// Live counts of a user's Horoscope Analysis + Appointment bookings.
final _userRequestsProvider = StreamProvider.autoDispose
    .family<List<AstrologerRequestModel>, String>((ref, uid) {
  return ref.read(astrologerServiceProvider).watchRequestsByUser(uid);
});

/// Admin → User Details (spec §1). Shows the user's profile + activity with
/// Edit (suspend/activate) and Delete (account + data) actions.
class UserDetailsScreen extends ConsumerWidget {
  final String uid;
  const UserDetailsScreen({super.key, required this.uid});

  String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(allUsersProvider).valueOrNull ?? const [];
    UserModel? user;
    for (final u in users) {
      if (u.uid == uid) {
        user = u;
        break;
      }
    }
    final profile = ref.watch(profileByUserIdProvider(uid)).valueOrNull;
    final requests =
        ref.watch(_userRequestsProvider(uid)).valueOrNull ?? const [];
    final analysisCount =
        requests.where((r) => r.type == AstrologerRequestType.matching).length;
    final apptCount = requests.where((r) => r.hasAppointment).length;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('User Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: user == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _card([
                  Center(
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      backgroundImage: _photo(profile, user).isNotEmpty
                          ? NetworkImage(_photo(profile, user))
                          : null,
                      child: _photo(profile, user).isEmpty
                          ? const Icon(Icons.person,
                              color: AppColors.primary, size: 40)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                        profile?.fullName ?? user.displayName ?? 'User',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  const Divider(height: 24),
                  _row('User ID', user.uid),
                  _row('Mobile', user.phone ?? '—'),
                  _row('Email', user.email ?? '—'),
                  _row('Age', profile == null ? '—' : '${_age(profile.dateOfBirth)}'),
                  _row('Gender', profile?.gender ?? user.gender ?? '—'),
                  _row('Location', _location(profile)),
                  _row('Status', user.isBlocked ? 'Suspended' : 'Active'),
                  _row('Registered', _date(user.createdAt)),
                ]),
                const SizedBox(height: 14),
                _card([
                  _sectionTitle('Activity'),
                  const SizedBox(height: 8),
                  _row('Horoscope Analysis Requests', '$analysisCount'),
                  _row('Appointments Booked', '$apptCount'),
                ]),
                const SizedBox(height: 18),
                // Full profile editor — edits flow LIVE to the user app.
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        context.push('/admin/user/${user!.uid}/edit'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Profile'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _toggleStatus(context, ref, user!),
                        icon: Icon(user.isBlocked
                            ? Icons.lock_open_outlined
                            : Icons.block_outlined),
                        label: Text(user.isBlocked ? 'Activate' : 'Suspend'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _delete(context, ref, user!),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete User'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  int _age(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) age--;
    return age;
  }

  String _photo(dynamic profile, UserModel user) {
    final p = (profile?.profilePhotoUrl ?? '') as String;
    if (p.isNotEmpty) return p;
    return user.photoUrl ?? '';
  }

  String _location(dynamic profile) {
    if (profile == null) return '—';
    final parts = [profile.city, profile.state]
        .where((s) => (s as String).trim().isNotEmpty)
        .toList();
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  Future<void> _toggleStatus(
      BuildContext context, WidgetRef ref, UserModel user) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(adminActionsProvider.notifier);
    if (user.isBlocked) {
      await notifier.unblockUser(user.uid);
    } else {
      await notifier.blockUser(user.uid);
    }
    ref.invalidate(allUsersProvider);
    messenger.showSnackBar(SnackBar(
        content: Text(user.isBlocked ? 'User activated.' : 'User suspended.')));
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, UserModel user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete user?'),
        content: const Text(
            'This permanently removes the user account and their profile data. '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    await ref.read(adminActionsProvider.notifier).deleteUser(user.uid);
    final st = ref.read(adminActionsProvider);
    ref.invalidate(allUsersProvider);
    messenger.showSnackBar(SnackBar(
        content: Text(st.hasError ? 'Could not delete user.' : 'User deleted.')));
    if (!st.hasError) router.pop();
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontSize: 15,
          fontFamily: 'Poppins',
          fontWeight: FontWeight.bold,
          color: AppColors.primary));

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 150,
                child: Text(k,
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey[700]))),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
