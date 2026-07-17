import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/astrologer_request_model.dart';

/// Appointment confirmation (spec §11). Shown after a successful payment, it
/// displays the Booking ID, appointment date & session, office address and
/// contact number. Actions: **View My Bookings** (→ My Bookings page) and
/// **Back to Home**. Fully localized (EN/TA).
class AppointmentConfirmationScreen extends ConsumerWidget {
  final String bookingId;

  /// `{date, session, address, contact, groom, bride, internalUid, expertName,
  /// expertPhoto}` passed from the booking screen.
  final Map<String, dynamic>? extra;

  const AppointmentConfirmationScreen({
    super.key,
    required this.bookingId,
    this.extra,
  });

  DateTime? get _date => extra?['date'] as DateTime?;
  String get _session => (extra?['session'] as String?) ?? '';
  String get _address => (extra?['address'] as String?) ?? '';
  String get _contact => (extra?['contact'] as String?) ?? '';

  String _sessionLabel(BuildContext context) {
    if (_session.isEmpty) return '—';
    return _session == AppointmentSession.morning
        ? context.l10n.morningSessionWindow
        : context.l10n.eveningSessionWindow;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.appointmentConfirmed),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle,
                      color: AppColors.success, size: 56),
                ),
                const SizedBox(height: 14),
                Text(l10n.appointmentBookedTitle,
                    style: const TextStyle(
                        fontSize: 18,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(l10n.visitOfficeAtScheduled,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
              ],
            ),
            child: Column(
              children: [
                _row(Icons.confirmation_number_outlined, l10n.bookingIdLabel,
                    bookingId),
                const Divider(height: 20),
                _row(
                    Icons.event_outlined,
                    l10n.appointmentDate,
                    _date == null
                        ? '—'
                        : DateFormat('EEEE, d MMM yyyy',
                                Localizations.localeOf(context).languageCode)
                            .format(_date!)),
                const Divider(height: 20),
                _row(Icons.schedule_outlined, l10n.sessionLabel,
                    _sessionLabel(context)),
                const Divider(height: 20),
                _row(Icons.support_agent_outlined, l10n.exactTiming,
                    l10n.exactTimingNote),
                const Divider(height: 20),
                _row(Icons.location_on_outlined, l10n.officeAddress,
                    _address.isEmpty ? '—' : _address),
                const Divider(height: 20),
                _row(Icons.call_outlined, l10n.contactNumber,
                    _contact.isEmpty ? '—' : _contact),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // View My Bookings — replaces the old "Open Analysis Chat" and
          // "View My Reports" actions (spec: booking confirmation §6).
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/my-appointments'),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: Text(l10n.viewMyBookings),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => context.go('/home'),
              child: Text(l10n.backToHome),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(
            flex: 6,
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      );
}
