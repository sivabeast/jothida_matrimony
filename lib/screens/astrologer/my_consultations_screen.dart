import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/consultation_model.dart';
import '../../providers/consultation_provider.dart';

/// "My Consultations" — the user's view of their consultation bookings. They
/// can pay once an In-App booking is accepted, view the submitted report, and
/// cancel a not-yet-accepted booking.
class MyConsultationsScreen extends ConsumerWidget {
  const MyConsultationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myConsultationsProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('My Consultations'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load your consultations'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(myConsultationsProvider),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
        data: (list) => list.isEmpty
            ? _empty()
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _ConsultationCard(booking: list[i]),
              ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_note_outlined,
                  size: 56, color: AppColors.primary.withOpacity(0.35)),
              const SizedBox(height: 12),
              Text('No consultations yet',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            ],
          ),
        ),
      );
}

Color consultationStatusColor(ConsultationStatus s) {
  switch (s) {
    case ConsultationStatus.pending:
      return AppColors.warning;
    case ConsultationStatus.accepted:
    case ConsultationStatus.waitingForPayment:
      return AppColors.info;
    case ConsultationStatus.paid:
    case ConsultationStatus.analysisInProgress:
    case ConsultationStatus.reportSubmitted:
      return const Color(0xFF2F80ED);
    case ConsultationStatus.completed:
      return AppColors.success;
    case ConsultationStatus.rejected:
    case ConsultationStatus.cancelled:
    case ConsultationStatus.refunded:
      return AppColors.error;
  }
}

class _ConsultationCard extends ConsumerWidget {
  final ConsultationBooking booking;
  const _ConsultationCard({required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = booking;
    final color = consultationStatusColor(b.status);
    final canPay = b.isInApp && b.status == ConsultationStatus.waitingForPayment;
    final canViewReport = b.hasReport;
    final canCancel = b.status == ConsultationStatus.pending;

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
              Icon(b.isInApp ? Icons.phone_android : Icons.place_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  b.astrologerName.isEmpty ? 'Astrologer' : b.astrologerName,
                  style:
                      const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              _chip(b.statusLabel, color),
            ],
          ),
          const SizedBox(height: 8),
          _line(Icons.category_outlined, b.mode.label),
          if (b.isDirectVisit && b.visitDate != null)
            _line(
                Icons.event_outlined,
                '${DateFormat('d MMM yyyy').format(b.visitDate!)}'
                '${b.slotStartMinutes != null ? ' · ${formatMinutes(b.slotStartMinutes!)}' : ''}'),
          if (b.amount > 0) _line(Icons.payments_outlined, '₹${b.amount}'),
          if (b.note.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(b.note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
            ),
          if (canPay) ...[
            const SizedBox(height: 10),
            _payBanner(),
          ],
          if (canPay || canViewReport || canCancel) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (canPay)
                  Expanded(child: _payButton(context, ref, b)),
                if (canPay && (canViewReport || canCancel))
                  const SizedBox(width: 10),
                if (canViewReport)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showReport(context, b),
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('Report'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary)),
                    ),
                  ),
                if (canCancel && !canPay)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _cancel(context, ref, b),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error)),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _payButton(BuildContext context, WidgetRef ref, ConsultationBooking b) =>
      ElevatedButton.icon(
        onPressed: () => _pay(context, ref, b),
        icon: const Icon(Icons.payment, size: 18),
        label: Text('Pay ₹${b.amount}'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
        ),
      );

  Widget _payBanner() => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.info.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                size: 16, color: AppColors.info),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Accepted! Complete the payment to confirm your consultation.',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );

  Future<void> _pay(
      BuildContext context, WidgetRef ref, ConsultationBooking b) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(consultationControllerProvider.notifier).pay(b);
      messenger.showSnackBar(const SnackBar(
          content: Text('Payment successful — your booking is confirmed.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Payment could not be completed. Please try again.')));
    }
  }

  Future<void> _cancel(
      BuildContext context, WidgetRef ref, ConsultationBooking b) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(consultationControllerProvider.notifier).cancel(b);
      messenger.showSnackBar(
          const SnackBar(content: Text('Booking cancelled.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not cancel. Please try again.')));
    }
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 6),
            Expanded(
                child: Text(text, style: const TextStyle(fontSize: 12.5))),
          ],
        ),
      );

  void _showReport(BuildContext context, ConsultationBooking b) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                  'Report by ${b.astrologerName.isEmpty ? 'Astrologer' : b.astrologerName}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(height: 26),
              if (b.reportText.trim().isNotEmpty) ...[
                Text(b.reportText,
                    style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 18),
              ],
              if (b.reportImages.isNotEmpty) ...[
                const Text('Images',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: b.reportImages.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => showImageGallery(context, b.reportImages,
                          initialIndex: i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(b.reportImages[i],
                            width: 110, height: 110, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (b.reportPdfs.isNotEmpty) ...[
                const Text('PDFs',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                for (var i = 0; i < b.reportPdfs.length; i++)
                  RemotePdfTile(
                      url: b.reportPdfs[i],
                      label: 'Report PDF ${i + 1}',
                      index: i),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
