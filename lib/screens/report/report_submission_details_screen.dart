import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/value_l10n.dart';
import '../../models/astrologer_request_model.dart';
import '../../widgets/report/analysis_profile_cards.dart';

/// **View Details** for a horoscope report request (spec §15) — everything the
/// member submitted, in one read-only page.
///
/// Deliberately has NO edit, update or modify action (spec §16). A report
/// request is a one-time submission: once it is in, the member can review it
/// but not change it, whether it is Under Analysis or Completed.
///
/// The per-person block reuses [AnalysisProfileCards], the same read-only
/// review the astrologer sees — name, age, date and time of birth (with
/// AM/PM), birth place, Rasi, Nakshatra, Lagnam and every uploaded horoscope
/// document — so the two views can never drift apart. For an EXTERNAL report it
/// renders the manually-entered details instead.
class ReportSubmissionDetailsScreen extends ConsumerWidget {
  final AstrologerRequestModel request;
  const ReportSubmissionDetailsScreen({super.key, required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.viewDetails),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _RequestSummaryCard(request: request),
          const SizedBox(height: 16),
          // The submitted details for both sides — read-only by construction.
          AnalysisProfileCards(request: request),
          const SizedBox(height: 12),
          Text(l10n.reportReadOnlyNote,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// Request ID, type, dates and the live status — the "what/when" of the
/// request, above the "who" cards.
class _RequestSummaryCard extends StatelessWidget {
  final AstrologerRequestModel request;
  const _RequestSummaryCard({required this.request});

  String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final completed = request.status == AstrologerRequestStatus.completed;
    final color = completed ? AppColors.success : AppColors.warning;
    return Container(
      width: double.infinity,
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
              const Icon(Icons.receipt_long_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.horoscopeCompatibilityReport,
                    style: const TextStyle(
                        fontSize: 15,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                    completed ? l10n.statusCompleted : l10n.statusPending,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ],
          ),
          const Divider(height: 18),
          _row(l10n.bookingIdLabel, request.id),
          _row(l10n.serviceTypeLabel,
              request.isExternalReport
                  ? l10n.compatibilityReportWithAnyone
                  : l10n.onlineHoroscopeCompatibilityReport),
          _row(l10n.requestDate, _date(request.createdAt)),
          if (completed) _row(l10n.completedDate, _date(request.completedAt)),
          _row(l10n.paymentLabel,
              request.paid
                  ? '${l10n.paymentPaid}'
                      '${request.amount > 0 ? ' · ₹${request.amount}' : ''}'
                  : '—'),
          if (request.message.trim().isNotEmpty)
            _row(l10n.descriptionLabel,
                context.localizeValue(request.message)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
                completed ? l10n.reportReadyMsg : l10n.reportPreparingMsg,
                style: TextStyle(
                    fontSize: 12.5, height: 1.4, color: Colors.grey[800])),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Text(k,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 6,
              child: Text(v.trim().isEmpty ? '—' : v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
