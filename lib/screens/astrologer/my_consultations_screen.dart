import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/consultation_model.dart';
import '../../providers/chat_provider.dart';
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
                itemBuilder: (_, i) => ConsultationBookingCard(booking: list[i]),
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

/// A single consultation booking card. Public so the unified Bookings page
/// (bottom-nav tab) can reuse it alongside "My Consultations".
class ConsultationBookingCard extends ConsumerWidget {
  final ConsultationBooking booking;
  const ConsultationBookingCard({super.key, required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = booking;
    final color = consultationStatusColor(b.status);
    final canViewReport = b.hasReport;
    // Only an unpaid, not-yet-accepted Direct-Visit booking can be cancelled by
    // the user. In-App is paid upfront, so the astrologer accepts/rejects (a
    // rejection is refunded by the admin).
    final canCancel = b.status == ConsultationStatus.pending;
    // Chat unlocks once the booking is confirmed: an In-App booking once the
    // astrologer accepts (it is already paid); a Direct-Visit booking on accept.
    final canChat = _chatEnabled(b);

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
          const SizedBox(height: 8),
          _metaFooter(b),
          if (b.isInApp && b.status == ConsultationStatus.paid) ...[
            const SizedBox(height: 10),
            _awaitingBanner(),
          ],
          if (canViewReport || canCancel) ...[
            const SizedBox(height: 12),
            Row(
              children: [
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
                if (canViewReport && canCancel) const SizedBox(width: 10),
                if (canCancel)
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
          if (canChat) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _chat(context, ref, b),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Chat with Astrologer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Chat unlocks only once the booking is confirmed: an In-App booking once the
  /// astrologer accepts it (it advances to `analysisInProgress`, already paid);
  /// a Direct-Visit booking on acceptance. A paid-but-unaccepted In-App booking
  /// (`paid`) and pending / rejected / cancelled / refunded never allow chat.
  bool _chatEnabled(ConsultationBooking b) {
    switch (b.status) {
      case ConsultationStatus.analysisInProgress:
      case ConsultationStatus.reportSubmitted:
      case ConsultationStatus.completed:
        return true;
      case ConsultationStatus.accepted:
        return b.isDirectVisit;
      case ConsultationStatus.paid:
        // Direct-Visit reaches `paid` only at completion (cash at visit) → chat
        // stays available; In-App `paid` = awaiting acceptance → no chat yet.
        return b.isDirectVisit;
      default:
        return false;
    }
  }

  Future<void> _chat(
      BuildContext context, WidgetRef ref, ConsultationBooking b) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      debugPrint('[MyConsultations] open chat → booking=${b.id} '
          'astrologerId=${b.astrologerId} userId=${b.userId}');
      final id = await ref.read(chatControllerProvider).openChatWith(
            otherUid: b.astrologerId,
            otherName: b.astrologerName.isEmpty
                ? 'Astrologer'
                : b.astrologerName,
            otherPhoto: '',
          );
      if (!context.mounted) return;
      context.push('/chat/$id', extra: {
        'name': b.astrologerName.isEmpty ? 'Astrologer' : b.astrologerName,
        'photo': '',
        // The other party is the astrologer → show the user's quick replies.
        'isAstrologer': true,
      });
    } catch (e, st) {
      debugPrint('[MyConsultations] open chat FAILED (booking=${b.id}, '
          'astrologerId=${b.astrologerId}): $e\n$st');
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not open chat. Try again.')));
    }
  }

  /// Shown on a paid In-App booking that is still waiting for the astrologer to
  /// accept. Reassures the user their money is held safely until then.
  Widget _awaitingBanner() => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.info.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          children: [
            Icon(Icons.lock_clock_outlined,
                size: 16, color: AppColors.info),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Paid. Waiting for the astrologer to accept — you\'ll be '
                'refunded if they can\'t take it.',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );

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

  /// Booking ID · service type · payment status footer (spec display fields).
  Widget _metaFooter(ConsultationBooking b) {
    final pay = b.transactionStatusLabel;
    final payColor = pay == 'Paid' || pay == 'Completed'
        ? AppColors.success
        : pay == 'Cancelled' || pay == 'Refunded'
            ? AppColors.error
            : AppColors.warning;
    final shortId = b.id.length <= 8 ? b.id : b.id.substring(0, 8);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _metaPill(Icons.tag, '#$shortId'),
        _metaPill(Icons.category_outlined, b.mode.label),
        _metaPill(Icons.payments_outlined, pay, color: payColor),
      ],
    );
  }

  Widget _metaPill(IconData icon, String text, {Color? color}) {
    final c = color ?? Colors.grey[600]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 10.5, color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

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
