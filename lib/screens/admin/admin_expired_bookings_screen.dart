import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/astrologer_account_model.dart';
import '../../models/astrologer_request_model.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/common/data_states.dart';

/// Admin → Expired Bookings.
///
/// Lists match-analysis bookings whose astrologer did not respond within the
/// 24-hour window AND whose user chose [BookingReassignMode.allowAdmin]. The
/// admin reassigns each to a single eligible astrologer (radio-button picker —
/// never multiple), which moves the booking and gives the new astrologer a
/// fresh response window.
class AdminExpiredBookingsScreen extends ConsumerStatefulWidget {
  const AdminExpiredBookingsScreen({super.key});

  @override
  ConsumerState<AdminExpiredBookingsScreen> createState() =>
      _AdminExpiredBookingsScreenState();
}

class _AdminExpiredBookingsScreenState
    extends ConsumerState<AdminExpiredBookingsScreen> {
  // Ids already persisted/notified this session, so the sweep never re-fires.
  final _swept = <String>{};

  /// Persist the Expired flag (and notify the user) for any due-but-unflagged
  /// bookings. The service guards against duplicates with a transaction.
  void _sweep(List<AstrologerRequestModel> expired) {
    final due = expired
        .where((r) => r.isExpiredByTime && !r.expired && !_swept.contains(r.id))
        .toList();
    if (due.isEmpty) return;
    for (final r in due) {
      _swept.add(r.id);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in due) {
        ref.read(adminActionsProvider.notifier).expireBooking(r);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(allAstrologerRequestsProvider);

    return requestsAsync.when(
      loading: () => const LoadingState(message: 'Loading bookings…'),
      error: (e, _) {
        debugPrint('[ExpiredBookings] load failed: $e');
        return ErrorStateView(
          message: 'Connection Error — unable to load bookings.',
          onRetry: () => ref.invalidate(allAstrologerRequestsProvider),
        );
      },
      data: (_) {
        final expired = ref.watch(expiredBookingsProvider);
        _sweep(expired);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Text(context.l10n.expiredBookings,
                style: const TextStyle(
                    fontSize: 22,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Bookings whose astrologer did not respond in time and the user '
              'allowed admin reassignment.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            if (expired.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: EmptyState(
                  icon: Icons.event_available_outlined,
                  message: 'No expired bookings to reassign',
                ),
              )
            else
              for (final r in expired)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ExpiredBookingCard(request: r),
                ),
          ],
        );
      },
    );
  }
}

class _ExpiredBookingCard extends ConsumerWidget {
  final AstrologerRequestModel request;
  const _ExpiredBookingCard({required this.request});

  String get _shortId =>
      request.id.length <= 8 ? request.id : request.id.substring(0, 8);

  String get _matchName {
    final g = request.groomName ?? '—';
    final b = request.brideName ?? '—';
    return '$g & $b';
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)
        ],
        border: Border.all(color: AppColors.error.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('#$_shortId',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        fontFamily: 'Poppins')),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  request.reassigned ? 'EXPIRED · REASSIGNED' : 'EXPIRED',
                  style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _line(Icons.person_outline, 'User', request.userName),
          _line(Icons.favorite_border, 'Match', _matchName),
          _line(Icons.auto_awesome, 'Previous Astrologer',
              request.astrologerName.isEmpty ? '—' : request.astrologerName),
          _line(
            Icons.timer_off_outlined,
            'Expiry Time',
            request.expiresAt != null ? _fmt(request.expiresAt!) : '—',
          ),
          if (request.history.isNotEmpty) ...[
            const SizedBox(height: 8),
            _HistoryTrail(history: request.history),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openAssign(context, ref),
              icon: const Icon(Icons.assignment_ind_outlined, size: 18),
              label: Text(context.l10n.assign),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 13, color: Colors.grey[500]),
            const SizedBox(width: 6),
            SizedBox(
                width: 116,
                child: Text(label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );

  Future<void> _openAssign(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => _AssignSheet(request: request),
    );
  }
}

/// Bottom sheet with a single-selection (radio button) list of eligible
/// astrologers and an [Assign Booking] action.
class _AssignSheet extends ConsumerStatefulWidget {
  final AstrologerRequestModel request;
  const _AssignSheet({required this.request});

  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  String? _selectedId;
  bool _assigning = false;

  @override
  Widget build(BuildContext context) {
    // Eligible = active + available-for-assignment + not on leave, excluding the
    // astrologer who just let the booking expire.
    final eligible = ref
        .watch(eligibleAstrologersProvider)
        .where((a) => a.id != widget.request.astrologerId)
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Assign to Astrologer',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Select ONE astrologer. The booking moves to them with a fresh '
            '24-hour response window.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          if (eligible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                    'No eligible astrologers (active, available & not on leave).'),
              ),
            )
          else
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: eligible.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _astrologerRadio(eligible[i]),
                ),
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_selectedId == null || _assigning)
                  ? null
                  : () => _assign(eligible),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _assigning
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(context.l10n.assignBooking,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _astrologerRadio(AstrologerAccount a) => RadioListTile<String>(
        value: a.id,
        groupValue: _selectedId,
        onChanged: (v) => setState(() => _selectedId = v),
        activeColor: AppColors.primary,
        contentPadding: EdgeInsets.zero,
        title: Text(a.fullName,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          '${a.experienceYears} yrs · ⭐ ${a.rating.toStringAsFixed(1)}'
          '${a.city.isNotEmpty ? ' · ${a.city}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        secondary: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.12),
          backgroundImage:
              a.photoUrl.isNotEmpty ? NetworkImage(a.photoUrl) : null,
          child: a.photoUrl.isEmpty
              ? Text(
                  a.fullName.isNotEmpty ? a.fullName[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.bold))
              : null,
        ),
      );

  Future<void> _assign(List<AstrologerAccount> eligible) async {
    final picked = eligible.firstWhere((a) => a.id == _selectedId);
    setState(() => _assigning = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await ref.read(adminActionsProvider.notifier).reassignRequest(
          widget.request.id,
          astrologerId: picked.id,
          astrologerName: picked.fullName,
          userId: widget.request.userId,
        );
    final st = ref.read(adminActionsProvider);
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not assign the booking. Please try again.'
          : 'Booking assigned to ${picked.fullName}.'),
      backgroundColor: st.hasError ? AppColors.error : null,
    ));
  }
}

/// Compact vertical timeline of the booking's history entries.
class _HistoryTrail extends StatelessWidget {
  final List<BookingHistoryEntry> history;
  const _HistoryTrail({required this.history});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('History',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700])),
          const SizedBox(height: 6),
          for (final h in history)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: AppColors.primary, shape: BoxShape.circle),
                    ),
                  ),
                  Expanded(
                    child: Text(h.label,
                        style: const TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
