import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/consultation_model.dart';
import '../../providers/consultation_provider.dart';
import 'my_consultations_screen.dart' show consultationStatusColor;

/// Astrologer's consultation inbox: accept/reject requests, run the analysis,
/// submit the report and complete the consultation. Three tabs: Requests
/// (pending) · In Progress · Completed.
class AstrologerConsultationsScreen extends ConsumerWidget {
  const AstrologerConsultationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(astrologerConsultationsProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: const Text('Consultations'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: AppColors.gold,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Requests'),
              Tab(text: 'In Progress'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        body: async.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (_, __) => Center(
            child: OutlinedButton(
              onPressed: () =>
                  ref.invalidate(astrologerConsultationsProvider),
              child: const Text('Try Again'),
            ),
          ),
          data: (all) {
            final pending = all
                .where((c) => c.status == ConsultationStatus.pending)
                .toList();
            final progress = all
                .where((c) =>
                    c.isActive &&
                    c.status != ConsultationStatus.pending &&
                    c.status != ConsultationStatus.completed)
                .toList();
            final done = all
                .where((c) =>
                    c.status == ConsultationStatus.completed ||
                    !c.isActive)
                .toList();
            return TabBarView(
              children: [
                _list(pending, 'No new requests'),
                _list(progress, 'Nothing in progress'),
                _list(done, 'No completed consultations'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _list(List<ConsultationBooking> items, String empty) {
    if (items.isEmpty) {
      return Center(
        child: Text(empty, style: TextStyle(color: Colors.grey[600])),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _AstroConsultationCard(booking: items[i]),
    );
  }
}

class _AstroConsultationCard extends ConsumerWidget {
  final ConsultationBooking booking;
  const _AstroConsultationCard({required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = booking;
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
              Icon(b.isInApp ? Icons.phone_android : Icons.place_outlined,
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
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
            ),
          ..._actions(context, ref, b),
        ],
      ),
    );
  }

  List<Widget> _actions(
      BuildContext context, WidgetRef ref, ConsultationBooking b) {
    final ctrl = ref.read(consultationControllerProvider.notifier);
    switch (b.status) {
      case ConsultationStatus.pending:
        return [
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _run(context, () => ctrl.respond(b, false),
                    'Request declined'),
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
                onPressed: () =>
                    _run(context, () => ctrl.respond(b, true), 'Request accepted'),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Accept'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
              ),
            ),
          ]),
        ];
      case ConsultationStatus.waitingForPayment:
        return [_hint('Accepted — waiting for the user to pay.')];
      case ConsultationStatus.accepted:
        // Direct-visit confirmed → can complete after the visit.
        return [_singleAction(context, 'Mark Completed',
            () => ctrl.complete(b), 'Consultation completed')];
      case ConsultationStatus.paid:
        return [
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _run(context, () => ctrl.startAnalysis(b),
                    'Analysis started'),
                child: const Text('Start Analysis'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _reportDialog(context, ref, b),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                child: const Text('Submit Report'),
              ),
            ),
          ]),
        ];
      case ConsultationStatus.analysisInProgress:
        return [_singleAction(context, 'Submit Report',
            () async => _reportDialog(context, ref, b), null,
            primary: true)];
      case ConsultationStatus.reportSubmitted:
        return [_singleAction(context, 'Mark Completed',
            () => ctrl.complete(b), 'Consultation completed')];
      default:
        return const [];
    }
  }

  Widget _singleAction(
      BuildContext context, String label, Future<void> Function() action,
      String? success,
      {bool primary = true}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => _run(context, action, success),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          child: Text(label),
        ),
      ),
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 15, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Expanded(
                child: Text(text,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[600]))),
          ],
        ),
      );

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ]),
      );

  Future<void> _run(BuildContext context, Future<void> Function() action,
      String? success) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (success != null) {
        messenger.showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Action failed. Please try again.')));
    }
  }

  Future<void> _reportDialog(
      BuildContext context, WidgetRef ref, ConsultationBooking b) async {
    final controller = TextEditingController(text: b.reportText);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit Report'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          minLines: 5,
          decoration: const InputDecoration(
            hintText: 'Write the deep match-analysis report for the user…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    if (!context.mounted) return;
    await _run(
      context,
      () => ref.read(consultationControllerProvider.notifier).submitReport(
            b,
            text: text,
            existingImages: b.reportImages,
            existingPdfs: b.reportPdfs,
          ),
      'Report submitted to the user',
    );
  }
}
