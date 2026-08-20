import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/appointment_status.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/astrologer_request_model.dart';
import '../../providers/profile_provider.dart';
import '../common/network_photo.dart';

/// Everything the admin Appointment Management card and detail sheet display
/// for one booking, resolved once from the booking document plus (only when the
/// document is missing a denormalised value) the member's profile and gated
/// contact record.
///
/// Older bookings predate `userPhone` / `userPhotoUrl`, and no booking has ever
/// carried an e-mail — so those fall back to `profiles/{id}` and
/// `contacts/{uid}`, both of which an admin may read.
class AppointmentCardData {
  final String phone;
  final String email;
  final String photo;
  final String appointmentType;
  final String meetingType;
  final String date;
  final String time;
  final String sessionWindow;
  final String payment;
  final String paymentStatus;
  final String notes;
  final String created;
  final String reason;
  final String office;

  const AppointmentCardData({
    required this.phone,
    required this.email,
    required this.photo,
    required this.appointmentType,
    required this.meetingType,
    required this.date,
    required this.time,
    required this.sessionWindow,
    required this.payment,
    required this.paymentStatus,
    required this.notes,
    required this.created,
    required this.reason,
    required this.office,
  });

  static AppointmentCardData of(WidgetRef ref, AstrologerRequestModel a) {
    // Only reach for the profile / contact when the booking itself can't answer.
    final needsProfile = a.userPhone.isEmpty || a.userPhotoUrl.isEmpty;
    final profile = needsProfile
        ? ref.watch(profileByUserIdProvider(a.userId)).valueOrNull
        : null;
    // Contact is a separate, admin-readable record — the only place an e-mail
    // or a mobile number reliably lives.
    final contact = ref.watch(contactByUserIdProvider(a.userId)).valueOrNull;

    final phone = [
      a.userPhone,
      contact?.mobileNumber ?? '',
      profile?.contact.mobileNumber ?? '',
    ].firstWhere((v) => v.trim().isNotEmpty, orElse: () => '');
    final email = [
      contact?.email ?? '',
      profile?.contact.email ?? '',
    ].firstWhere((v) => v.trim().isNotEmpty, orElse: () => '');

    return AppointmentCardData(
      phone: phone.trim(),
      email: email.trim(),
      photo: a.userPhotoUrl.isNotEmpty
          ? a.userPhotoUrl
          : (profile?.profilePhotoUrl ?? ''),
      appointmentType: _typeLabel(a),
      // Every booking in this app is an office visit — there is no online
      // session product. Stated explicitly so the admin never has to assume.
      meetingType: 'In-Person · Office Visit',
      date: a.visitDate == null
          ? '—'
          : DateFormat('EEE, d MMM yyyy').format(a.visitDate!),
      time: a.session.isNotEmpty
          ? AppointmentSession.shortLabel(a.session)
          : (a.slotStartMinutes == null
              ? '—'
              : formatMinutes(a.slotStartMinutes!)),
      sessionWindow:
          a.session.isNotEmpty ? AppointmentSession.label(a.session) : '—',
      payment: a.paid
          ? 'Paid${a.amount > 0 ? ' · ₹${a.amount}' : ''}'
          : (a.amount > 0 ? 'Not Paid · ₹${a.amount}' : 'Free'),
      paymentStatus: a.paid ? 'Paid' : a.paymentStatusLabel,
      notes: a.message.trim(),
      created: DateFormat('d MMM yyyy, h:mm a').format(a.createdAt),
      reason: a.category.trim(),
      office: a.officeAddress.trim(),
    );
  }

  static String _typeLabel(AstrologerRequestModel a) {
    switch (a.type) {
      case AstrologerRequestType.matching:
        return a.isExternalReport
            ? 'External Horoscope Report'
            : 'Horoscope Compatibility Report';
      case AstrologerRequestType.consultation:
        return 'Consultation';
      case AstrologerRequestType.inquiry:
        return 'Inquiry';
    }
  }
}

/// Read-only "View Details" sheet — the complete booking record, including the
/// office address snapshot and the append-only audit trail.
Future<void> showAppointmentDetailsSheet(
        BuildContext context, AstrologerRequestModel appt) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _AppointmentDetailsSheet(appt: appt),
    );

class _AppointmentDetailsSheet extends ConsumerWidget {
  final AstrologerRequestModel appt;
  const _AppointmentDetailsSheet({required this.appt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = AppointmentCardData.of(ref, appt);
    final color = appointmentStatusColor(appt.status);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          Row(
            children: [
              ClipOval(child: NetworkPhoto(url: d.photo, width: 54, height: 54)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appt.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 17,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(d.appointmentType,
                        style:
                            TextStyle(fontSize: 12.5, color: Colors.grey[600])),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(appointmentStatusLabel(appt.status),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _group('Booking', [
            ('Booking ID', appt.id),
            ('Appointment Type', d.appointmentType),
            ('Consultation Reason', d.reason),
            ('Meeting Type', d.meetingType),
            ('Selected Date', d.date),
            ('Selected Time', d.sessionWindow),
            ('Booking Status', appointmentStatusLabel(appt.status)),
            ('Created', d.created),
          ]),
          _group('Member', [
            ('Name', appt.userName),
            ('User ID', appt.userId),
            ('Mobile Number', d.phone),
            // Collected by the booking flow itself — an appointment never
            // requires a matrimony profile to read a DOB from (spec §8).
            ('Date of Birth', appt.userDob),
            ('Email', d.email),
            ('Location', appt.userLocation),
            ('Preferred Language', appt.userLanguage == 'ta' ? 'Tamil' : 'English'),
          ]),
          _group('Payment', [
            ('Payment Status', d.paymentStatus),
            ('Amount', appt.amount > 0 ? '₹${appt.amount}' : 'Free'),
            ('Payment ID', appt.paymentId),
            ('Paid At',
                appt.paidAt == null
                    ? ''
                    : DateFormat('d MMM yyyy, h:mm a').format(appt.paidAt!)),
          ]),
          if (d.notes.isNotEmpty) _paragraph('Notes from the member', d.notes),
          if (d.office.isNotEmpty) _paragraph('Office Address', d.office),
          if (appt.officeContact.trim().isNotEmpty)
            _paragraph('Office Contact', appt.officeContact),
          if (appt.history.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('HISTORY',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Colors.grey[500])),
            const SizedBox(height: 8),
            for (final h in appt.history.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(Icons.circle,
                          size: 7, color: AppColors.primary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h.label,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                          Text(
                              DateFormat('d MMM yyyy, h:mm a').format(h.at),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Rows with no value are dropped; a group with nothing left disappears.
  Widget _group(String title, List<(String, String)> rows) {
    final visible = rows.where((r) => r.$2.trim().isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.primary)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Colors.grey[200]),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(visible[i].$1,
                              style: TextStyle(
                                  fontSize: 11.5, color: Colors.grey[600])),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 5,
                          child: SelectableText(visible[i].$2,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paragraph(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.primary)),
            const SizedBox(height: 6),
            Text(body, style: const TextStyle(fontSize: 12.5, height: 1.45)),
          ],
        ),
      );
}

/// The day + session the admin picked in the reschedule sheet.
class RescheduleChoice {
  final DateTime date;
  final String session;
  const RescheduleChoice(this.date, this.session);
}

/// Reschedule sheet — pick a new day and session. Returns null when dismissed.
Future<RescheduleChoice?> showAppointmentRescheduleSheet(
        BuildContext context, AstrologerRequestModel appt) =>
    showModalBottomSheet<RescheduleChoice>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _RescheduleSheet(appt: appt),
    );

class _RescheduleSheet extends StatefulWidget {
  final AstrologerRequestModel appt;
  const _RescheduleSheet({required this.appt});

  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  late DateTime _date;
  late String _session;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final current = widget.appt.visitDate;
    // Start from the existing visit, unless it is already in the past.
    _date = (current != null &&
            !DateTime(current.year, current.month, current.day)
                .isBefore(DateTime(now.year, now.month, now.day)))
        ? DateTime(current.year, current.month, current.day)
        : DateTime(now.year, now.month, now.day);
    _session = widget.appt.session.isNotEmpty
        ? widget.appt.session
        : AppointmentSession.morning;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() =>
          _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          18, 4, 18, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Reschedule Appointment',
              style: TextStyle(
                  fontSize: 17,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              'The booking keeps its ID and payment — only the visit moves. '
              'The member is notified with the new date.',
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: Colors.grey[600])),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: Text(DateFormat('EEE, d MMM yyyy').format(_date)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 14),
          for (final s in AppointmentSession.all)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RadioListTile<String>(
                value: s,
                groupValue: _session,
                onChanged: (v) => setState(() => _session = v ?? s),
                activeColor: AppColors.primary,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: _session == s
                          ? AppColors.primary
                          : Colors.grey.shade300),
                ),
                title: Text(AppointmentSession.label(s),
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
            ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(
                context, RescheduleChoice(_date, _session)),
            icon: const Icon(Icons.event_available_outlined, size: 18),
            label: const Text('Confirm New Slot'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
