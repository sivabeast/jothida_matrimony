import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/appointment_status.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/astrologer_request_model.dart';
import '../../providers/appointment_provider.dart';

/// "My Appointments" — the signed-in user's full appointment booking history.
/// Each card shows the booked date, time, status (live) and booking id. Data is
/// loaded dynamically from the database via [myAppointmentsProvider].
class MyAppointmentsScreen extends ConsumerWidget {
  const MyAppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myAppointmentsProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('My Appointments'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => const _Empty(
            message: 'Could not load your appointments. Please try again.'),
        data: (list) {
          if (list.isEmpty) {
            return const _Empty(message: 'You have no appointments yet.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => AppointmentHistoryCard(appt: list[i]),
          );
        },
      ),
    );
  }
}

/// A clean appointment card (date · time · status · booking id) reused by the
/// history screen.
class AppointmentHistoryCard extends StatelessWidget {
  final AstrologerRequestModel appt;
  const AppointmentHistoryCard({super.key, required this.appt});

  @override
  Widget build(BuildContext context) {
    final color = appointmentStatusColor(appt.status);
    final dateStr = appt.visitDate == null
        ? '—'
        : DateFormat('EEEE, d MMM yyyy').format(appt.visitDate!);
    final timeStr =
        appt.slotStartMinutes == null ? '—' : formatMinutes(appt.slotStartMinutes!);

    return Container(
      padding: const EdgeInsets.all(16),
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
            children: [
              Icon(appointmentStatusIcon(appt.status), size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  appointmentStatusLabel(appt.status),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: color),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(appointmentStatusLabel(appt.status),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ),
            ],
          ),
          const Divider(height: 18),
          _row(Icons.event_outlined, 'Date', dateStr),
          const SizedBox(height: 8),
          _row(Icons.schedule_outlined, 'Time', timeStr),
          const SizedBox(height: 8),
          _row(Icons.confirmation_number_outlined, 'Booking ID', appt.id),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Row(
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
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
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
