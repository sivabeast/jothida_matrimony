import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_account_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/settlement_provider.dart';
import '../../widgets/common/data_states.dart';
import 'admin_export.dart' show inr;

/// Admin → Astrologers (bottom-nav). Two sections via tabs:
///  • **Pending Verification** — the queue awaiting approve / reject.
///  • **Approved** — every live astrologer with search, active/online status,
///    booking count, pending payout and quick actions (View Profile, Suspend).
class AdminAstrologerVerificationView extends ConsumerWidget {
  const AdminAstrologerVerificationView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final astrosAsync = ref.watch(allAstrologersProvider);

    return astrosAsync.when(
      loading: () => const LoadingState(message: 'Loading astrologers…'),
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
        final approved = all.where((a) => a.isApproved).toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));

        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Material(
                color: Colors.white,
                child: TabBar(
                  labelColor: AppColors.primary,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: AppColors.primary,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  tabs: [
                    Tab(text: 'Pending (${pending.length})'),
                    Tab(text: 'Approved (${approved.length})'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _PendingList(pending: pending),
                    _ApprovedList(approved: approved),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Pending-verification queue (approve / reject via [PendingAstrologerCard]).
class _PendingList extends StatelessWidget {
  final List<AstrologerAccount> pending;
  const _PendingList({required this.pending});

  @override
  Widget build(BuildContext context) {
    if (pending.isEmpty) {
      return const EmptyState(
        icon: Icons.verified_user_outlined,
        message: 'No astrologers awaiting verification',
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          itemCount: pending.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => PendingAstrologerCard(astrologer: pending[i]),
        ),
      ),
    );
  }
}

/// Searchable list of approved astrologers with live status + payout snapshot.
class _ApprovedList extends ConsumerStatefulWidget {
  final List<AstrologerAccount> approved;
  const _ApprovedList({required this.approved});

  @override
  ConsumerState<_ApprovedList> createState() => _ApprovedListState();
}

class _ApprovedListState extends ConsumerState<_ApprovedList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.approved
        : widget.approved
            .where((a) =>
                a.fullName.toLowerCase().contains(q) ||
                a.mobile.contains(q) ||
                a.email.toLowerCase().contains(q))
            .toList();
    // astrologerId → pending payout (₹).
    final payouts = {
      for (final s in ref.watch(astrologerSettlementsProvider))
        s.astrologerId: s,
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search by name, mobile or email',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(
                  icon: Icons.person_search_outlined,
                  message: 'No approved astrologers')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ApprovedCard(
                    astrologer: list[i],
                    pendingPayout:
                        payouts[list[i].id]?.pendingPayout ?? 0,
                  ),
                ),
        ),
      ],
    );
  }
}

class _ApprovedCard extends ConsumerWidget {
  final AstrologerAccount astrologer;
  final int pendingPayout;
  const _ApprovedCard(
      {required this.astrologer, required this.pendingPayout});

  Future<void> _suspend(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suspend Astrologer'),
        content: Text('Suspend ${astrologer.fullName}? They lose live '
            'visibility and return to the verification queue.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Suspend'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(adminActionsProvider.notifier).suspendAstrologer(astrologer.id);
    final st = ref.read(adminActionsProvider);
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not suspend. Please try again.'
          : '${astrologer.fullName} suspended.'),
      backgroundColor: st.hasError ? AppColors.error : null,
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = astrologer;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withOpacity(0.12),
                backgroundImage:
                    a.photoUrl.isNotEmpty ? NetworkImage(a.photoUrl) : null,
                child: a.photoUrl.isEmpty
                    ? Text(
                        a.fullName.isNotEmpty
                            ? a.fullName[0].toUpperCase()
                            : '?',
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
                    Text(a.fullName.isEmpty ? 'Astrologer' : a.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _dot(a.manuallyAvailable ? 'Active' : 'Inactive',
                            a.manuallyAvailable
                                ? AppColors.success
                                : Colors.grey),
                        const SizedBox(width: 6),
                        _dot(a.isAvailableNow ? 'Online' : 'Offline',
                            a.isAvailableNow
                                ? AppColors.success
                                : Colors.grey),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          Row(
            children: [
              _stat('Bookings', '${a.bookingCount}'),
              _stat('Pending Payout', inr(pendingPayout)),
              _stat('Rating', a.rating.toStringAsFixed(1)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _suspend(context, ref),
                  icon: const Icon(Icons.block, size: 16),
                  label: const Text('Suspend'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/admin/astrologer/${a.id}'),
                  icon: const Icon(Icons.person_outline, size: 16),
                  label: const Text('View Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11.5, color: Colors.grey[700])),
        ],
      );

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 1),
            Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
      );
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
