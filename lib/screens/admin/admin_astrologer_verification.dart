import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_account_model.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/common/data_states.dart';

/// Admin → Astrologers (bottom-nav). **Verification management only.**
///
/// Shows the queue of astrologers awaiting verification. Approving moves them
/// out of this list (and into the Users → Astrologers tab); rejecting saves a
/// rejected status. Verified / rejected accounts are NOT browsed here — that
/// lives on the Users page.
class AdminAstrologerVerificationView extends ConsumerWidget {
  const AdminAstrologerVerificationView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final astrosAsync = ref.watch(allAstrologersProvider);

    return astrosAsync.when(
      loading: () => const LoadingState(message: 'Loading verification queue…'),
      error: (e, _) {
        debugPrint('[AdminVerification] load failed: $e');
        return ErrorStateView(
          message: 'Connection Error — unable to load astrologers.',
          onRetry: () => ref.invalidate(allAstrologersProvider),
        );
      },
      data: (all) {
        final pending = all
            .where((a) => a.status == VerificationStatus.pending)
            .toList()
          ..sort((a, b) => (b.createdAt ?? DateTime(0))
              .compareTo(a.createdAt ?? DateTime(0)));

        return Column(
          children: [
            _Header(count: pending.length),
            Expanded(
              child: pending.isEmpty
                  ? const EmptyState(
                      icon: Icons.verified_user_outlined,
                      message: 'No astrologers awaiting verification',
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                          itemCount: pending.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) =>
                              PendingAstrologerCard(astrologer: pending[i]),
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  const _Header({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [AppColors.primary, Color(0xFF7C5CFC)]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user, color: Colors.white, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Verification Requests',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                    count == 0
                        ? 'No pending requests'
                        : '$count astrologer${count == 1 ? '' : 's'} awaiting review',
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable verification card for a pending astrologer. Used both by the
/// Astrologers verification page (full) and the Dashboard pending-verification
/// widget ([dense] = notification-card style). Self-contained: runs the
/// approve/reject actions through [adminActionsProvider].
class PendingAstrologerCard extends ConsumerWidget {
  final AstrologerAccount astrologer;
  final bool dense;
  const PendingAstrologerCard(
      {super.key, required this.astrologer, this.dense = false});

  String get _location {
    final parts = [
      astrologer.district.isNotEmpty ? astrologer.district : astrologer.city,
      astrologer.state,
    ].where((p) => p.trim().isNotEmpty).toList();
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  String get _applied {
    final d = astrologer.createdAt;
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  }

  Future<void> _verify(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(adminActionsProvider.notifier)
        .approveAstrologer(astrologer.id);
    final st = ref.read(adminActionsProvider);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not verify. Please try again.'
          : '${astrologer.fullName} verified ✓'),
      backgroundColor: st.hasError ? AppColors.error : AppColors.success,
    ));
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Astrologer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reject ${astrologer.fullName}\'s verification request?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(adminActionsProvider.notifier).rejectAstrologer(
          astrologer.id,
          reason: reasonCtrl.text.trim(),
        );
    final st = ref.read(adminActionsProvider);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not reject. Please try again.'
          : '${astrologer.fullName} rejected'),
      backgroundColor: st.hasError ? AppColors.error : null,
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radius = dense ? 22.0 : 26.0;
    return Container(
      padding: EdgeInsets.all(dense ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withOpacity(0.30)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: radius,
                backgroundColor: AppColors.primary.withOpacity(0.12),
                backgroundImage: astrologer.photoUrl.isNotEmpty
                    ? NetworkImage(astrologer.photoUrl)
                    : null,
                child: astrologer.photoUrl.isEmpty
                    ? Text(
                        astrologer.fullName.isNotEmpty
                            ? astrologer.fullName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(astrologer.fullName.isEmpty
                        ? 'Unnamed astrologer'
                        : astrologer.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: dense ? 14 : 15)),
                    const SizedBox(height: 3),
                    _iconLine(Icons.work_history_outlined,
                        '${astrologer.experienceYears} yrs experience'),
                    const SizedBox(height: 2),
                    _iconLine(Icons.location_on_outlined, _location),
                    const SizedBox(height: 2),
                    _iconLine(Icons.event_outlined, 'Applied $_applied'),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: dense ? 10 : 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _reject(context, ref),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _verify(context, ref),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Verify'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconLine(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 13, color: Colors.grey[500]),
          const SizedBox(width: 5),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          ),
        ],
      );
}
