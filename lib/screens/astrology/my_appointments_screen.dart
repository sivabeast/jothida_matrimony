import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_dialogs.dart';
import '../../core/utils/appointment_status.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/slot_generator.dart';
import '../../core/utils/value_l10n.dart';
import '../../models/astrologer_request_model.dart';
import '../../providers/appointment_provider.dart';

/// **Astrology Bookings** — the ONE booking-history page (`/my-appointments`).
///
/// Both entry points land here: the side menu's "Astrology Bookings" item and
/// the "View My Bookings" action on the Astrology home page's current-booking
/// card. There is deliberately no second booking-history screen anywhere in
/// the app (spec §2/§33).
///
/// Every booking the signed-in member has made is listed, upcoming ones first,
/// each card carrying its Booking ID, consultation type, astrologer (when one
/// is assigned), date, time, live status and payment status. Data comes from
/// [myAppointmentsProvider], so an admin status change lands here instantly.
class MyAppointmentsScreen extends ConsumerWidget {
  const MyAppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(myAppointmentsProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.astrologyBookings),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => _Empty(message: l10n.couldNotLoadBookings),
        data: (list) {
          if (list.isEmpty) return _Empty(message: l10n.noBookingsYet);
          // Upcoming / open bookings first (soonest visit at the top), then the
          // finished ones newest-first — the order a member expects a booking
          // history in.
          final sorted = _sortForHistory(list);
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => AppointmentHistoryCard(appt: sorted[i]),
          );
        },
      ),
    );
  }

  /// Open bookings ascending by visit date, then closed ones descending by
  /// creation date. The provider already streams newest-first, so this only
  /// lifts the still-relevant bookings to the top.
  static List<AstrologerRequestModel> _sortForHistory(
      List<AstrologerRequestModel> list) {
    final open = <AstrologerRequestModel>[];
    final closed = <AstrologerRequestModel>[];
    for (final a in list) {
      (isOpenAppointment(a.status) ? open : closed).add(a);
    }
    open.sort((a, b) {
      final ad = a.visitDate, bd = b.visitDate;
      if (ad == null && bd == null) return b.createdAt.compareTo(a.createdAt);
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });
    closed.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [...open, ...closed];
  }
}

/// One booking card: status chip · consultation · astrologer · date · time ·
/// payment · Booking ID, plus the cancel action while the booking is open.
///
/// An OPEN booking can be cancelled here. That is also how a date change works:
/// there is deliberately no "edit the date" action — the member cancels this
/// booking and books the new day afresh, so the new visit is a new booking with
/// its own Booking ID rather than this record quietly changing date.
class AppointmentHistoryCard extends ConsumerStatefulWidget {
  final AstrologerRequestModel appt;

  /// Hides the cancel action where the card is purely informational (e.g. the
  /// booking-confirmation screen).
  final bool allowCancel;

  const AppointmentHistoryCard(
      {super.key, required this.appt, this.allowCancel = true});

  @override
  ConsumerState<AppointmentHistoryCard> createState() =>
      _AppointmentHistoryCardState();
}

class _AppointmentHistoryCardState
    extends ConsumerState<AppointmentHistoryCard> {
  /// Collapsed by default so the list stays scannable; "View Details" opens
  /// the full breakdown in place rather than on yet another page.
  bool _expanded = false;

  AstrologerRequestModel get appt => widget.appt;

  /// Cancels the booking after an explicit confirmation — never on one tap.
  Future<void> _cancel() async {
    final l10n = context.l10n;
    final ok = await showAppConfirmDialog(
      context,
      title: l10n.cancelBookingTitle,
      message: l10n.cancelBookingBody(appt.id),
      confirmLabel: l10n.cancelBooking,
      cancelLabel: l10n.keepBooking,
      icon: Icons.event_busy_outlined,
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(appointmentControllerProvider.notifier).delete(appt);
      if (mounted) showAppSnack(context, l10n.bookingCancelledToast);
    } catch (_) {
      if (mounted) {
        showAppSnack(context, l10n.couldNotCancelBooking, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = appointmentStatusColor(appt.status);
    final open = isOpenAppointment(appt.status);
    final dateStr = appt.visitDate == null
        ? '—'
        : DateFormat('EEEE, d MMM yyyy').format(appt.visitDate!);
    final timeStr = appt.session.isNotEmpty
        ? context.localizeValue(appt.sessionLabel)
        : (appt.slotStartMinutes == null
            ? '—'
            : formatMinutes(appt.slotStartMinutes!));
    final astrologer = appt.astrologerName.trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(appointmentStatusIcon(appt.status), size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  appointmentStatusLabel(l10n, appt.status),
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: color),
                ),
              ),
              // Timeline chip — "Upcoming" while the visit is still ahead,
              // otherwise the booking's own status.
              _chip(appointmentTimelineLabel(l10n, appt), color),
            ],
          ),
          const Divider(height: 18),
          if (appt.category.trim().isNotEmpty) ...[
            _row(Icons.category_outlined, l10n.consultationLabel,
                context.localizeValue(appt.category)),
            const SizedBox(height: 8),
          ],
          if (astrologer.isNotEmpty) ...[
            _row(Icons.person_outline, l10n.astrologerLabel, astrologer),
            const SizedBox(height: 8),
          ],
          _row(Icons.event_outlined, l10n.dateLabel, dateStr),
          const SizedBox(height: 8),
          _row(Icons.schedule_outlined, l10n.timeLabel, timeStr),
          const SizedBox(height: 8),
          // Payment status: an in-person consultation is settled at the office,
          // so an unpaid booking is normal — never an error state.
          _row(
            Icons.payments_outlined,
            l10n.paymentLabel,
            appt.paid
                ? '${l10n.paymentPaid}${appt.amount > 0 ? ' · ₹${appt.amount}' : ''}'
                : l10n.paymentAtOffice,
            valueColor: appt.paid ? AppColors.success : null,
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            _row(Icons.confirmation_number_outlined, l10n.bookingIdLabel,
                appt.id),
            const SizedBox(height: 8),
            _row(Icons.history_outlined, l10n.bookedOnLabel,
                DateFormat('d MMM yyyy').format(appt.createdAt)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(appointmentStatusMessage(l10n, appt.status),
                  style: TextStyle(
                      fontSize: 12.5, height: 1.4, color: Colors.grey[800])),
            ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                  _expanded ? Icons.expand_less : Icons.receipt_long_outlined,
                  size: 17),
              label: Text(_expanded ? l10n.close : l10n.viewDetails),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact),
            ),
          ),
          if (widget.allowCancel && open) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _cancel,
                icon: const Icon(Icons.event_busy_outlined, size: 18),
                label: Text(l10n.cancelBooking),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side:
                      BorderSide(color: AppColors.error.withValues(alpha: 0.55)),
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(l10n.rebookAnotherDayNote,
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );

  Widget _row(IconData icon, String label, String value, {Color? valueColor}) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Text(label,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
          ),
          Expanded(
            flex: 5,
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valueColor)),
          ),
        ],
      );
}

class _Empty extends StatelessWidget {
  final String message;
  const _Empty({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_note_outlined,
                size: 64, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14.5, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
