import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/common/data_states.dart';

/// Admin → Profile Approvals (/admin/approvals).
///
/// Live pending-moderation queue: a profile submitted, approved or rejected
/// anywhere shows up / disappears here instantly ([pendingProfilesProvider] is
/// a Firestore snapshot stream). Approve / Reject pass BOTH the profile id and
/// the owner's userId so the member gets the in-app + push notification.
class AdminApprovalsScreen extends ConsumerWidget {
  const AdminApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(pendingProfilesProvider);
    final count = profilesAsync.valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(count > 0 ? 'Profile Approvals ($count)' : 'Profile Approvals'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: profilesAsync.when(
        loading: () => const LoadingState(message: 'Loading profiles...'),
        error: (e, _) {
          debugPrint('[AdminApprovals] load failed: $e');
          return ErrorStateView(
            message: 'Unable to load profiles. Please try again.',
            onRetry: () => ref.invalidate(pendingProfilesProvider),
          );
        },
        data: (profiles) => profiles.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 72, color: AppColors.success),
                    const SizedBox(height: 16),
                    const Text('No profiles waiting for review',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('New submissions will appear here automatically.',
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey[600])),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: profiles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _ApprovalCard(profile: profiles[i]),
              ),
      ),
    );
  }
}

class _ApprovalCard extends ConsumerWidget {
  final ProfileModel profile;

  const _ApprovalCard({required this.profile});

  String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: profile.photos.isNotEmpty
                      ? NetworkImage(profile.photos.first)
                      : null,
                  child: profile.photos.isEmpty
                      ? const Icon(Icons.person, size: 30)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(
                        '${profile.age} yrs • ${profile.gender} • ${profile.city}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      Text(
                        '${profile.religion} • ${profile.caste}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      Text(
                        'Submitted: ${_date(profile.createdAt)}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _InfoChip(Icons.school_outlined, profile.education),
                const SizedBox(width: 8),
                _InfoChip(Icons.work_outline, profile.occupation),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () =>
                    context.push('/admin/user/${profile.userId}'),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('View Details'),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _reject(context, ref),
                    icon: const Icon(Icons.close, color: AppColors.error),
                    label: const Text('Reject',
                        style: TextStyle(color: AppColors.error)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _approve(context, ref),
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text('Approve',
                        style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    // userId too, so the member receives the "Profile Approved" notification.
    await ref
        .read(adminActionsProvider.notifier)
        .approveProfile(profile.id, userId: profile.userId);
    final st = ref.read(adminActionsProvider);
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not approve profile. Please try again.'
          : '${profile.name} approved — the member has been notified.'),
      backgroundColor: st.hasError ? AppColors.error : AppColors.success,
    ));
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Reject Profile'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Reason for rejection (required)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, controller.text.trim()),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white),
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );
    if (reason == null || reason.isEmpty) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(adminActionsProvider.notifier)
        .rejectProfile(profile.id, reason, userId: profile.userId);
    final st = ref.read(adminActionsProvider);
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not reject profile. Please try again.'
          : 'Profile rejected.'),
      backgroundColor: st.hasError ? AppColors.error : AppColors.warning,
    ));
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
