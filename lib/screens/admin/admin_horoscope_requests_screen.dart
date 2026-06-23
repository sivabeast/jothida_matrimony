import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_account_model.dart';
import '../../models/astrologer_request_model.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/common/data_states.dart';

/// Admin → Horoscope Requests (bottom-nav). Manages the astrologer
/// match-analysis / consultation request queue: summary counts, status
/// filters, a "Need Attention" section for long-pending requests, and per-row
/// admin actions (Send Reminder, Reassign Astrologer).
class AdminHoroscopeRequestsScreen extends ConsumerStatefulWidget {
  const AdminHoroscopeRequestsScreen({super.key});

  @override
  ConsumerState<AdminHoroscopeRequestsScreen> createState() =>
      _AdminHoroscopeRequestsScreenState();
}

enum _ReqFilter { all, pendingAcceptance, accepted, inProgress, completed, reassigned }

extension on _ReqFilter {
  String get label => switch (this) {
        _ReqFilter.all => 'All',
        _ReqFilter.pendingAcceptance => 'Pending Acceptance',
        _ReqFilter.accepted => 'Accepted',
        _ReqFilter.inProgress => 'In Progress',
        _ReqFilter.completed => 'Completed',
        _ReqFilter.reassigned => 'Reassigned',
      };
}

class _AdminHoroscopeRequestsScreenState
    extends ConsumerState<AdminHoroscopeRequestsScreen> {
  _ReqFilter _filter = _ReqFilter.all;

  bool _matches(AstrologerRequestModel r) => switch (_filter) {
        _ReqFilter.all => true,
        _ReqFilter.pendingAcceptance =>
          r.status == AstrologerRequestStatus.pending,
        // Accepted & In Progress share the `accepted` status (the data model
        // has no separate in-progress state).
        _ReqFilter.accepted => r.status == AstrologerRequestStatus.accepted,
        _ReqFilter.inProgress => r.status == AstrologerRequestStatus.accepted,
        _ReqFilter.completed => r.status == AstrologerRequestStatus.completed,
        _ReqFilter.reassigned => r.reassigned,
      };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allAstrologerRequestsProvider);

    return async.when(
      loading: () => const LoadingState(message: 'Loading requests…'),
      error: (e, _) {
        debugPrint('[HoroscopeRequests] load failed: $e');
        return ErrorStateView(
          message: 'Connection Error — unable to load requests.',
          onRetry: () => ref.invalidate(allAstrologerRequestsProvider),
        );
      },
      data: (all) {
        final now = DateTime.now();
        final total = all.length;
        final pending = all
            .where((r) => r.status == AstrologerRequestStatus.pending)
            .length;
        final inProgress = all
            .where((r) => r.status == AstrologerRequestStatus.accepted)
            .length;
        final completed = all
            .where((r) => r.status == AstrologerRequestStatus.completed)
            .length;

        // Need-attention: pending > 24h, grouped by astrologer.
        final stale = all
            .where((r) =>
                r.status == AstrologerRequestStatus.pending &&
                now.difference(r.createdAt).inHours >= 24)
            .toList();
        final grouped = <String, ({int count, Duration maxWait})>{};
        for (final r in stale) {
          final key = r.astrologerName.isEmpty ? 'Unassigned' : r.astrologerName;
          final wait = now.difference(r.createdAt);
          final cur = grouped[key];
          grouped[key] = (
            count: (cur?.count ?? 0) + 1,
            maxWait: (cur == null || wait > cur.maxWait) ? wait : cur.maxWait,
          );
        }

        final shown = all.where(_matches).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            const Text('Horoscope Requests',
                style: TextStyle(
                    fontSize: 22,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),

            // Summary cards (2×2).
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.5,
              children: [
                _SummaryTile('Total Requests', total, Icons.list_alt,
                    AppColors.primary),
                _SummaryTile('Pending Acceptance', pending,
                    Icons.hourglass_top, AppColors.warning),
                _SummaryTile('In Progress', inProgress, Icons.sync,
                    const Color(0xFF2F80ED)),
                _SummaryTile('Completed', completed, Icons.check_circle,
                    AppColors.success),
              ],
            ),
            const SizedBox(height: 16),

            // Filters.
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final f in _ReqFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f.label),
                        selected: _filter == f,
                        showCheckmark: false,
                        selectedColor: AppColors.primary.withOpacity(0.14),
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: _filter == f
                              ? AppColors.primary
                              : Colors.black87,
                          fontWeight: _filter == f
                              ? FontWeight.w600
                              : FontWeight.normal,
                          fontSize: 12.5,
                        ),
                        side: BorderSide(
                            color: _filter == f
                                ? AppColors.primary
                                : Colors.grey[300]!),
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Need attention.
            if (grouped.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.error, size: 18),
                  const SizedBox(width: 6),
                  Text('Need Attention',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[850])),
                ],
              ),
              const SizedBox(height: 8),
              for (final e in grouped.entries)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.priority_high,
                          color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${e.key} — ${e.value.count} request${e.value.count == 1 ? '' : 's'} '
                          'pending for ${_waited(e.value.maxWait)}',
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
            ],

            // Request list.
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: EmptyState(
                    icon: Icons.menu_book_outlined,
                    message: 'No requests in this filter'),
              )
            else
              for (final r in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RequestCard(request: r),
                ),
          ],
        );
      },
    );
  }
}

String _waited(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} day${d.inDays == 1 ? '' : 's'}';
  if (d.inHours >= 1) return '${d.inHours} hr${d.inHours == 1 ? '' : 's'}';
  return '${d.inMinutes} min';
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  const _SummaryTile(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, height: 1.1)),
                Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends ConsumerWidget {
  final AstrologerRequestModel request;
  const _RequestCard({required this.request});

  String get _matchName {
    if (request.isMatchAnalysis) {
      final g = request.groomName ?? '—';
      final b = request.brideName ?? '—';
      return '$g & $b';
    }
    return request.type.label;
  }

  ({Color color, String text}) get _statusBadge => switch (request.status) {
        AstrologerRequestStatus.pending => (
            color: AppColors.warning,
            text: 'PENDING'
          ),
        AstrologerRequestStatus.accepted => (
            color: const Color(0xFF2F80ED),
            text: 'IN PROGRESS'
          ),
        AstrologerRequestStatus.completed => (
            color: AppColors.success,
            text: 'COMPLETED'
          ),
        AstrologerRequestStatus.rejected => (
            color: AppColors.error,
            text: 'REJECTED'
          ),
      };

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badge = _statusBadge;
    final waiting = _waited(DateTime.now().difference(request.createdAt));
    final isPending = request.status == AstrologerRequestStatus.pending;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(request.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14.5)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badge.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(badge.text,
                    style: TextStyle(
                        color: badge.color,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold)),
              ),
              if (request.reassigned) ...[
                const SizedBox(width: 6),
                const Icon(Icons.swap_horiz, size: 16, color: Colors.deepPurple),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _line(Icons.favorite_border, 'Match', _matchName),
          _line(Icons.auto_awesome, 'Astrologer',
              request.astrologerName.isEmpty ? 'Unassigned' : request.astrologerName),
          _line(Icons.event_outlined, 'Requested', _fmtDate(request.createdAt)),
          _line(Icons.timelapse, 'Waiting', waiting),
          if (isPending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _sendReminder(context, ref),
                    icon: const Icon(Icons.notifications_active_outlined,
                        size: 17),
                    label: const Text('Reminder'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 9)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _reassign(context, ref),
                    icon: const Icon(Icons.swap_horiz, size: 17),
                    label: const Text('Reassign'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 9)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 13, color: Colors.grey[500]),
            const SizedBox(width: 6),
            SizedBox(
                width: 74,
                child: Text(label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
            Expanded(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );

  Future<void> _sendReminder(BuildContext context, WidgetRef ref) async {
    if (request.astrologerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No astrologer assigned to remind.')));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(adminActionsProvider.notifier)
        .sendRequestReminder(request.astrologerId);
    final st = ref.read(adminActionsProvider);
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not send reminder.'
          : 'Reminder sent to ${request.astrologerName}.'),
      backgroundColor: st.hasError ? AppColors.error : null,
    ));
  }

  Future<void> _reassign(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => Consumer(
        builder: (ctx, sheetRef, _) {
          final approved = (sheetRef.watch(allAstrologersProvider).valueOrNull ??
                  const <AstrologerAccount>[])
              .where((a) =>
                  a.status == VerificationStatus.approved &&
                  a.id != request.astrologerId)
              .toList()
            ..sort((a, b) => a.fullName.compareTo(b.fullName));

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Reassign to Astrologer',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('The request resets to pending for the new astrologer.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 12),
                if (approved.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                        child: Text('No other verified astrologers available.')),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: approved.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final a = approved[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor:
                                const Color(0xFF7C5CFC).withOpacity(0.12),
                            backgroundImage: a.photoUrl.isNotEmpty
                                ? NetworkImage(a.photoUrl)
                                : null,
                            child: a.photoUrl.isEmpty
                                ? Text(
                                    a.fullName.isNotEmpty
                                        ? a.fullName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        color: Color(0xFF7C5CFC),
                                        fontWeight: FontWeight.bold))
                                : null,
                          ),
                          title: Text(a.fullName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${a.experienceYears} yrs · ⭐ ${a.rating.toStringAsFixed(1)}',
                              style: const TextStyle(fontSize: 12)),
                          onTap: () async {
                            Navigator.pop(sheetCtx);
                            final messenger = ScaffoldMessenger.of(context);
                            await ref
                                .read(adminActionsProvider.notifier)
                                .reassignRequest(request.id,
                                    astrologerId: a.id,
                                    astrologerName: a.fullName);
                            final st = ref.read(adminActionsProvider);
                            messenger.showSnackBar(SnackBar(
                              content: Text(st.hasError
                                  ? 'Could not reassign.'
                                  : 'Reassigned to ${a.fullName}.'),
                              backgroundColor:
                                  st.hasError ? AppColors.error : null,
                            ));
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
