import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_dialogs.dart';
import '../../core/utils/appointment_status.dart';
import '../../models/astrologer_request_model.dart';
import '../../providers/appointment_provider.dart';
import '../../widgets/admin/appointment_admin_views.dart';
import '../../widgets/common/data_states.dart';
import '../../widgets/common/network_photo.dart';
import '../../widgets/common/skeletons.dart';

enum _ApptFilter { all, today, upcoming, confirmed, pending, completed, cancelled }

extension _ApptFilterX on _ApptFilter {
  String get label => switch (this) {
        _ApptFilter.all => 'All',
        _ApptFilter.today => 'Today',
        _ApptFilter.upcoming => 'Upcoming',
        _ApptFilter.confirmed => 'Confirmed',
        _ApptFilter.pending => 'Pending',
        _ApptFilter.completed => 'Completed',
        _ApptFilter.cancelled => 'Cancelled',
      };
}

/// Admin → Appointment Management. A dedicated page (separate from Astrology
/// Management) listing EVERY appointment booking with full user details, live
/// status, search + filters and per-booking actions. Fully database-driven via
/// [allAppointmentsProvider]; status changes sync to the user instantly.
class AdminAppointmentsScreen extends ConsumerStatefulWidget {
  const AdminAppointmentsScreen({super.key});

  @override
  ConsumerState<AdminAppointmentsScreen> createState() =>
      _AdminAppointmentsScreenState();
}

class _AdminAppointmentsScreenState
    extends ConsumerState<AdminAppointmentsScreen> {
  final _search = TextEditingController();
  String _query = '';
  _ApptFilter _filter = _ApptFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matchesFilter(AstrologerRequestModel r) {
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    final visit = r.visitDate == null
        ? null
        : DateTime(r.visitDate!.year, r.visitDate!.month, r.visitDate!.day);
    switch (_filter) {
      case _ApptFilter.all:
        return true;
      case _ApptFilter.today:
        return visit != null && visit == t0;
      case _ApptFilter.upcoming:
        return visit != null &&
            !visit.isBefore(t0) &&
            (r.status == AstrologerRequestStatus.pending ||
                r.status == AstrologerRequestStatus.accepted);
      case _ApptFilter.confirmed:
        return r.status == AstrologerRequestStatus.accepted;
      case _ApptFilter.pending:
        return r.status == AstrologerRequestStatus.pending;
      case _ApptFilter.completed:
        return r.status == AstrologerRequestStatus.completed;
      case _ApptFilter.cancelled:
        return r.status == AstrologerRequestStatus.rejected;
    }
  }

  /// Matches on everything printed on the card that identifies a booking. The
  /// e-mail lives on the member's contact record rather than the booking, so it
  /// is deliberately NOT searched here — searching it would mean a gated read
  /// per row on every keystroke.
  bool _matchesQuery(AstrologerRequestModel r) {
    if (_query.trim().isEmpty) return true;
    final q = _query.trim().toLowerCase();
    return r.userName.toLowerCase().contains(q) ||
        r.userPhone.toLowerCase().contains(q) ||
        r.id.toLowerCase().contains(q) ||
        r.category.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allAppointmentsProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Appointment Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _searchBar(),
          _filterChips(),
          Expanded(
            child: async.when(
              loading: () => const SkeletonList(items: 5),
              error: (e, __) => ErrorStateView(
                message: 'Unable to load appointments. Please try again.',
                onRetry: () => ref.invalidate(allAppointmentsProvider),
              ),
              data: (all) {
                final list = all
                    .where(_matchesFilter)
                    .where(_matchesQuery)
                    .toList();
                if (list.isEmpty) {
                  final filtered =
                      _filter != _ApptFilter.all || _query.trim().isNotEmpty;
                  return EmptyState(
                    icon: Icons.event_busy_outlined,
                    message: filtered
                        ? 'No appointments match this view'
                        : 'No appointments yet',
                    subtitle: filtered
                        ? 'Try a different filter or clear the search.'
                        : 'New bookings will appear here automatically.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _AppointmentAdminCard(appt: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search by name, mobile or booking ID',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

  Widget _filterChips() => SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final f in _ApptFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f.label),
                  selected: _filter == f,
                  selectedColor: AppColors.primary.withOpacity(0.15),
                  labelStyle: TextStyle(
                    color: _filter == f ? AppColors.primary : Colors.black87,
                    fontWeight:
                        _filter == f ? FontWeight.w700 : FontWeight.normal,
                    fontSize: 12.5,
                  ),
                  onSelected: (_) => setState(() => _filter = f),
                ),
              ),
          ],
        ),
      );

}

class _AppointmentAdminCard extends ConsumerWidget {
  final AstrologerRequestModel appt;
  const _AppointmentAdminCard({required this.appt});

  Future<void> _setStatus(BuildContext context, WidgetRef ref,
      AstrologerRequestStatus status) async {
    try {
      await ref
          .read(appointmentControllerProvider.notifier)
          .setStatus(appt, status);
      if (context.mounted) {
        showAppSnack(
            context, 'Appointment ${appointmentStatusLabel(status)}.');
      }
    } catch (_) {
      if (context.mounted) {
        showAppSnack(context, 'Action failed. Please try again.', error: true);
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete Appointment?',
      message: 'This permanently removes the booking and frees its slot. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
      danger: true,
    );
    if (!ok) return;
    if (!context.mounted) return;
    try {
      await ref.read(appointmentControllerProvider.notifier).delete(appt);
      if (context.mounted) showAppSnack(context, 'Appointment deleted.');
    } catch (_) {
      if (context.mounted) {
        showAppSnack(context, 'Delete failed. Please try again.', error: true);
      }
    }
  }

  /// Opens the "Reschedule" sheet and applies the chosen day + session.
  Future<void> _reschedule(BuildContext context, WidgetRef ref) async {
    final picked = await showAppointmentRescheduleSheet(context, appt);
    if (picked == null || !context.mounted) return;
    try {
      await ref.read(appointmentControllerProvider.notifier).reschedule(
            appt,
            visitDate: picked.date,
            session: picked.session,
          );
      if (context.mounted) {
        showAppSnack(
            context,
            'Rescheduled to '
            '${DateFormat('EEE, d MMM yyyy').format(picked.date)} · '
            '${AppointmentSession.shortLabel(picked.session)}.');
      }
    } catch (_) {
      if (context.mounted) {
        showAppSnack(context, 'Could not reschedule. Please try again.',
            error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = AppointmentCardData.of(ref, appt);
    final color = appointmentStatusColor(appt.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipOval(
                child: NetworkPhoto(url: d.photo, width: 48, height: 48),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appt.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    if (d.phone.isNotEmpty)
                      Text('📞 ${d.phone}',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[700])),
                    if (d.email.isNotEmpty)
                      Text('✉ ${d.email}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[700])),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _pill(appointmentStatusLabel(appt.status), color),
                  const SizedBox(height: 4),
                  _pill(d.paymentStatus,
                      appt.paid ? AppColors.success : AppColors.warning),
                ],
              ),
            ],
          ),
          const Divider(height: 18),
          // Every detail uses ONE structure (label above value, value on its
          // own full-width line) laid out in a responsive grid: two columns
          // when there is room, one column on narrow phones. Values therefore
          // always get enough width to wrap on word boundaries instead of
          // breaking one word — or one character — per line.
          AppointmentDetailsGrid(items: [
            (Icons.category_outlined, 'Appointment Type', d.appointmentType),
            (Icons.place_outlined, 'Meeting Type', d.meetingType),
            (Icons.event_outlined, 'Date', d.date),
            (Icons.schedule_outlined, 'Time', d.time),
            (Icons.payments_outlined, 'Payment', d.payment),
            (Icons.history_toggle_off_outlined, 'Created', d.created),
          ]),
          const SizedBox(height: 10),
          _info(Icons.confirmation_number_outlined, 'Booking ID', appt.id),
          if (d.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            _info(Icons.sticky_note_2_outlined, 'Notes', d.notes),
          ],
          const SizedBox(height: 14),
          _actions(context, ref),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _info(IconData icon, String label, String value) =>
      AppointmentDetailRow(icon: icon, label: label, value: value);

  /// Every action the spec asks for, offered only when it makes sense for the
  /// booking's current state:
  ///   • **View Details** — always (the full record, incl. the audit trail);
  ///   • **Confirm** — while still pending (paid bookings auto-confirm at
  ///     payment time, so this is for free / unpaid ones);
  ///   • **Reschedule** — until the visit is completed or cancelled;
  ///   • **Complete** / **Cancel** — until one of them has happened;
  ///   • **Delete** — cleanup, always.
  Widget _actions(BuildContext context, WidgetRef ref) {
    final s = appt.status;
    final open = s != AstrologerRequestStatus.completed &&
        s != AstrologerRequestStatus.rejected;
    final chips = <Widget>[
      _actionBtn(context, 'View Details', Icons.receipt_long_outlined,
          AppColors.primary, () => showAppointmentDetailsSheet(context, appt)),
      if (s == AstrologerRequestStatus.pending)
        _actionBtn(context, 'Confirm', Icons.check_circle_outline,
            AppColors.success,
            () => _setStatus(context, ref, AstrologerRequestStatus.accepted)),
      if (open)
        _actionBtn(context, 'Reschedule', Icons.event_repeat_outlined,
            AppColors.warning, () => _reschedule(context, ref)),
      if (open)
        _actionBtn(context, 'Complete', Icons.verified_outlined, AppColors.info,
            () => _setStatus(context, ref, AstrologerRequestStatus.completed)),
      if (open)
        _actionBtn(context, 'Cancel', Icons.cancel_outlined, AppColors.error,
            () => _setStatus(context, ref, AstrologerRequestStatus.rejected)),
      _actionBtn(context, 'Delete', Icons.delete_outline, Colors.grey.shade700,
          () => _delete(context, ref)),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _actionBtn(BuildContext context, String label, IconData icon,
          Color color, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 12.5)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
}


/// The appointment card's label/value grid (spec §19).
///
/// Two columns when the card is wide enough, ONE full-width column when it is
/// not, so a value like "In-Person · Office Visit" always has room to wrap on
/// word boundaries instead of breaking one word — or one character — per line.
class AppointmentDetailsGrid extends StatelessWidget {
  /// (icon, label, value) triples, rendered in order.
  final List<(IconData, String, String)> items;

  const AppointmentDetailsGrid({super.key, required this.items});

  /// The minimum width one detail column needs before a value starts breaking
  /// badly. Below twice this (plus the gutter) the grid drops to one column.
  static const double minColumnWidth = 150;
  static const double _gutter = 12;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, c) {
        final twoColumns = c.maxWidth >= minColumnWidth * 2 + _gutter;
        // Subtract a hair so rounding can never push two tiles past the line.
        final itemWidth =
            twoColumns ? (c.maxWidth - _gutter) / 2 - 0.01 : c.maxWidth;
        return Wrap(
          spacing: _gutter,
          runSpacing: 10,
          children: [
            for (final (icon, label, value) in items)
              SizedBox(
                width: itemWidth,
                child:
                    AppointmentDetailRow(icon: icon, label: label, value: value),
              ),
          ],
        );
      });
}

/// One label/value pair. The label sits on its own line next to the icon and
/// the value takes the FULL width underneath, so labels and values stay aligned
/// and ordinary words are never squeezed into a one-character-per-line column.
class AppointmentDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const AppointmentDetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(
              value.trim().isEmpty ? '—' : value,
              softWrap: true,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3),
            ),
          ),
        ],
      );
}
