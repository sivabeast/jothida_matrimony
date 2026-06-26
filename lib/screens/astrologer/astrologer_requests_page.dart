import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/consultation_model.dart';
import '../../providers/consultation_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../widgets/astrologer/booking_countdown.dart';
import 'my_consultations_screen.dart' show consultationStatusColor;

/// The astrologer's unified **Requests** page (spec §2) — replaces the old
/// Reviews bottom-nav tab. Two tabs:
///   • MATCH ANALYSIS — all online match-analysis bookings, with the
///     Pending / Accepted / In Progress / Completed / Rejected / Expired
///     lifecycle (spec §11) and a live 12-working-hour acceptance countdown.
///   • DIRECT VISIT — all direct-visit appointments, with the
///     Pending / Accepted / Completed / Cancelled lifecycle.
///
/// Used both embedded inside the dashboard's bottom-nav (no Scaffold) and as the
/// standalone `/astrologer-requests` route (with its own Scaffold/AppBar) so the
/// dashboard banner and FCM taps can deep-link straight to the right tab.
class AstrologerRequestsPage extends StatelessWidget {
  /// When true the page is shown inside the dashboard shell (which already
  /// supplies the AppBar) — only the TabBar + content are rendered.
  final bool embedded;

  /// 0 = Match Analysis, 1 = Direct Visit.
  final int initialTab;

  const AstrologerRequestsPage(
      {super.key, this.embedded = false, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    final body = DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      child: Column(
        children: [
          Material(
            color: embedded ? Colors.white : AppColors.primary,
            child: TabBar(
              indicatorColor: AppColors.gold,
              labelColor: embedded ? AppColors.primary : Colors.white,
              unselectedLabelColor:
                  embedded ? Colors.grey : Colors.white70,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: const [
                Tab(text: 'Match Analysis'),
                Tab(text: 'Direct Visit'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _MatchAnalysisTab(),
                _DirectVisitTab(),
              ],
            ),
          ),
        ],
      ),
    );

    if (embedded) return body;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Requests'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MATCH ANALYSIS
// ════════════════════════════════════════════════════════════════════════════

const _matchBuckets = <String, String>{
  'all': 'All',
  'pending': 'Pending',
  'accepted': 'Accepted',
  'inProgress': 'In Progress',
  'completed': 'Completed',
  'rejected': 'Rejected',
  'expired': 'Expired',
};

class _MatchAnalysisTab extends ConsumerStatefulWidget {
  const _MatchAnalysisTab();

  @override
  ConsumerState<_MatchAnalysisTab> createState() => _MatchAnalysisTabState();
}

class _MatchAnalysisTabState extends ConsumerState<_MatchAnalysisTab>
    with AutomaticKeepAliveClientMixin {
  String _bucket = 'all';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final async = ref.watch(astrologerMatchRequestsProvider);
    return async.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      error: (_, __) => _ErrorRetry(
          onRetry: () => ref.invalidate(astrologerMatchRequestsProvider)),
      data: (all) {
        // Order: actionable first (pending → accepted/in-progress), then done.
        int rank(AstrologerRequestModel r) {
          switch (r.displayBucket) {
            case 'pending':
              return 0;
            case 'inProgress':
              return 1;
            case 'accepted':
              return 2;
            case 'expired':
              return 3;
            case 'completed':
              return 4;
            default:
              return 5; // rejected
          }
        }

        final sorted = [...all]..sort((a, b) {
            final r = rank(a).compareTo(rank(b));
            return r != 0 ? r : b.createdAt.compareTo(a.createdAt);
          });
        final filtered = _bucket == 'all'
            ? sorted
            : sorted.where((r) => r.displayBucket == _bucket).toList();

        return Column(
          children: [
            _FilterChips(
              buckets: _matchBuckets,
              selected: _bucket,
              counts: {
                for (final k in _matchBuckets.keys)
                  k: k == 'all'
                      ? all.length
                      : all.where((r) => r.displayBucket == k).length,
              },
              onSelected: (k) => setState(() => _bucket = k),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const _EmptyState(
                      icon: Icons.auto_awesome_outlined,
                      message: 'No match-analysis requests here')
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) =>
                          _MatchRequestCard(request: filtered[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _MatchRequestCard extends ConsumerStatefulWidget {
  final AstrologerRequestModel request;
  const _MatchRequestCard({required this.request});

  @override
  ConsumerState<_MatchRequestCard> createState() => _MatchRequestCardState();
}

class _MatchRequestCardState extends ConsumerState<_MatchRequestCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Action failed. Please try again.'),
            backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open() =>
      context.push('/match-workspace/${widget.request.id}', extra: widget.request);

  Color _bucketColor(String bucket) {
    switch (bucket) {
      case 'pending':
        return AppColors.warning;
      case 'accepted':
      case 'inProgress':
        return AppColors.info;
      case 'completed':
        return AppColors.success;
      case 'expired':
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.primary;
    }
  }

  String _bucketLabel(String bucket) {
    switch (bucket) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'inProgress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'expired':
        return 'Expired';
      default:
        return 'Rejected';
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final bucket = r.displayBucket;
    final color = _bucketColor(bucket);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _open,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: r.userPhotoUrl.isNotEmpty
                      ? NetworkImage(r.userPhotoUrl)
                      : null,
                  child: r.userPhotoUrl.isEmpty
                      ? Text(r.userName.isNotEmpty ? r.userName[0] : '?',
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
                      Text(r.userName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(DateFormat('d MMM yyyy, h:mm a').format(r.createdAt),
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.grey[500])),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_bucketLabel(bucket),
                      style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.favorite, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${r.groomName ?? 'Groom'}  ×  ${r.brideName ?? 'Bride'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                  ),
                  if (r.amount > 0)
                    Text(r.paid ? '₹${r.amount} · Paid' : '₹${r.amount}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            fontSize: 12.5)),
                ],
              ),
            ),
            // Live acceptance countdown for pending bookings (spec §7).
            if (bucket == 'pending') ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: BookingCountdown(expiresAt: r.expiresAt),
              ),
            ],
            const SizedBox(height: 12),
            _actions(r, bucket),
          ],
        ),
      ),
    );
  }

  Widget _actions(AstrologerRequestModel r, String bucket) {
    switch (bucket) {
      case 'pending':
        // SPEC §6: once expired the Accept button is disabled and the booking
        // can no longer be accepted.
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => ref
                            .read(matchAnalysisControllerProvider.notifier)
                            .setStatus(r, AstrologerRequestStatus.rejected),
                        'Request declined'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error)),
                child: const Text('Reject'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => ref
                            .read(matchAnalysisControllerProvider.notifier)
                            .setStatus(r, AstrologerRequestStatus.accepted),
                        'Request accepted — chat is now open with the user.'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                child: _busy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Accept'),
              ),
            ),
          ],
        );
      case 'expired':
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.block, size: 16),
            label: const Text('Acceptance Expired'),
            style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error.withOpacity(0.4))),
          ),
        );
      case 'accepted':
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _open,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => ref
                            .read(matchAnalysisControllerProvider.notifier)
                            .startAnalysis(r),
                        'Analysis started'),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Start'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.info,
                    foregroundColor: Colors.white),
              ),
            ),
          ],
        );
      case 'inProgress':
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _open,
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Submit Report'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
          ),
        );
      case 'completed':
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _open,
            icon: const Icon(Icons.visibility_outlined, size: 16),
            label: const Text('View Analysis'),
            style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary)),
          ),
        );
      default: // rejected
        return SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _open,
            style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
            child: const Text('View'),
          ),
        );
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// DIRECT VISIT
// ════════════════════════════════════════════════════════════════════════════

const _visitBuckets = <String, String>{
  'all': 'All',
  'pending': 'Pending',
  'accepted': 'Accepted',
  'completed': 'Completed',
  'cancelled': 'Cancelled',
};

/// Maps a consultation status to one of the four Direct-Visit buckets (spec §2).
String _visitBucket(ConsultationBooking c) {
  switch (c.status) {
    case ConsultationStatus.pending:
      return 'pending';
    case ConsultationStatus.accepted:
      return 'accepted';
    case ConsultationStatus.completed:
      return 'completed';
    case ConsultationStatus.rejected:
    case ConsultationStatus.cancelled:
    case ConsultationStatus.refunded:
      return 'cancelled';
    default:
      // Direct-Visit bookings never reach the In-App-only states.
      return 'accepted';
  }
}

class _DirectVisitTab extends ConsumerStatefulWidget {
  const _DirectVisitTab();

  @override
  ConsumerState<_DirectVisitTab> createState() => _DirectVisitTabState();
}

class _DirectVisitTabState extends ConsumerState<_DirectVisitTab>
    with AutomaticKeepAliveClientMixin {
  String _bucket = 'all';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final async = ref.watch(astrologerConsultationsProvider);
    return async.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      error: (_, __) => _ErrorRetry(
          onRetry: () => ref.invalidate(astrologerConsultationsProvider)),
      data: (all) {
        // SPEC §3: only Direct-Visit bookings here (In-App service removed).
        final visits = all.where((c) => c.isDirectVisit).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final filtered = _bucket == 'all'
            ? visits
            : visits.where((c) => _visitBucket(c) == _bucket).toList();

        return Column(
          children: [
            _FilterChips(
              buckets: _visitBuckets,
              selected: _bucket,
              counts: {
                for (final k in _visitBuckets.keys)
                  k: k == 'all'
                      ? visits.length
                      : visits.where((c) => _visitBucket(c) == k).length,
              },
              onSelected: (k) => setState(() => _bucket = k),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const _EmptyState(
                      icon: Icons.place_outlined,
                      message: 'No direct-visit bookings here')
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) =>
                          _DirectVisitCard(booking: filtered[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _DirectVisitCard extends ConsumerStatefulWidget {
  final ConsultationBooking booking;
  const _DirectVisitCard({required this.booking});

  @override
  ConsumerState<_DirectVisitCard> createState() => _DirectVisitCardState();
}

class _DirectVisitCardState extends ConsumerState<_DirectVisitCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(success)));
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Action failed. Please try again.'),
            backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final ctrl = ref.read(consultationControllerProvider.notifier);
    final color = consultationStatusColor(b.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.place_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(b.userName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(b.statusLabel,
                    style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (b.visitDate != null)
            _line(
                Icons.event_outlined,
                '${DateFormat('d MMM yyyy').format(b.visitDate!)}'
                '${b.slotStartMinutes != null ? ' · ${formatMinutes(b.slotStartMinutes!)}' : ''}'),
          // SPEC §3/§4: Direct Visit collects NO online payment — the user pays
          // the astrologer in person.
          _line(Icons.money_off_outlined,
              b.amount > 0 ? 'Pay ₹${b.amount} at the visit (cash/UPI/card)'
                  : 'Payment handled in person'),
          if (b.note.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(b.note,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
            ),
          ..._actions(b, ctrl),
        ],
      ),
    );
  }

  List<Widget> _actions(
      ConsultationBooking b, ConsultationController ctrl) {
    switch (b.status) {
      case ConsultationStatus.pending:
        return [
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() => ctrl.respond(b, false),
                        'Appointment declined'),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() => ctrl.respond(b, true),
                        'Appointment confirmed'),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Accept'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
              ),
            ),
          ]),
        ];
      case ConsultationStatus.accepted:
        return [
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => ctrl.complete(b), 'Visit marked completed'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: const Text('Mark Completed'),
            ),
          ),
        ];
      default:
        return const [];
    }
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ]),
      );
}

// ════════════════════════════════════════════════════════════════════════════
// Shared bits
// ════════════════════════════════════════════════════════════════════════════

class _FilterChips extends StatelessWidget {
  final Map<String, String> buckets;
  final String selected;
  final Map<String, int> counts;
  final ValueChanged<String> onSelected;

  const _FilterChips({
    required this.buckets,
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final entry in buckets.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                    '${entry.value}${(counts[entry.key] ?? 0) > 0 ? ' (${counts[entry.key]})' : ''}'),
                selected: selected == entry.key,
                onSelected: (_) => onSelected(entry.key),
                selectedColor: AppColors.primary.withOpacity(0.15),
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  color:
                      selected == entry.key ? AppColors.primary : Colors.grey[700],
                  fontWeight: selected == entry.key
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                      color: selected == entry.key
                          ? AppColors.primary
                          : Colors.grey.withOpacity(0.3)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.primary.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(message, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
}

class _ErrorRetry extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorRetry({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: AppColors.error),
            const SizedBox(height: 12),
            const Text('Could not load requests'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try Again')),
          ],
        ),
      );
}
