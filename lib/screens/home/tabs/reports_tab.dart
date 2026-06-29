import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_actions.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../providers/match_analysis_provider.dart';
import '../../../providers/profile_provider.dart';

/// Reports tab (bottom-nav item 4) — the history of the user's COMPLETED
/// Horoscope Analysis reports (spec §2). Only completed reports appear here;
/// each card shows Partner Name · Request Date · Completed Date with View
/// Report + Download PDF actions.
class ReportsTab extends ConsumerWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myMatchAnalysisRequestsProvider);
    final all = async.valueOrNull ?? const <AstrologerRequestModel>[];
    final myName = ref.watch(myProfileProvider).valueOrNull?.fullName ?? '';

    final completed = all
        .where((r) => r.status == AstrologerRequestStatus.completed)
        .toList()
      ..sort((a, b) => (b.completedAt ?? b.createdAt)
          .compareTo(a.completedAt ?? a.createdAt));
    final pendingCount = all
        .where((r) => r.status != AstrologerRequestStatus.completed)
        .length;

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          alignment: Alignment.centerLeft,
          child: const Text('Reports',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
        ),
        if (pendingCount > 0)
          Container(
            width: double.infinity,
            color: Colors.orange.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.hourglass_bottom,
                    size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$pendingCount analysis ${pendingCount == 1 ? 'report is' : 'reports are'} '
                    'being prepared. They will appear here once completed.',
                    style: TextStyle(
                        fontSize: 12.5, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _body(context, ref, completed, myName, async.isLoading,
              async.hasError),
        ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    List<AstrologerRequestModel> reports,
    String myName,
    bool loading,
    bool hasError,
  ) {
    if (reports.isEmpty) {
      if (loading) {
        return const Center(
            child: CircularProgressIndicator(color: AppColors.primary));
      }
      if (hasError) {
        return _empty(Icons.error_outline, 'Could not load your reports',
            retry: () => ref.invalidate(myMatchAnalysisRequestsProvider));
      }
      return _empty(Icons.verified_outlined, 'No completed reports yet');
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(myMatchAnalysisRequestsProvider),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) =>
            _ReportCard(report: reports[i], myName: myName),
      ),
    );
  }

  Widget _empty(IconData icon, String text, {VoidCallback? retry}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: AppColors.primary.withOpacity(0.35)),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14)),
              if (retry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                    onPressed: retry, child: const Text('Try Again')),
              ],
            ],
          ),
        ),
      );
}

class _ReportCard extends StatelessWidget {
  final AstrologerRequestModel report;
  final String myName;
  const _ReportCard({required this.report, required this.myName});

  String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// The partner = whichever of the two compared profiles is not the user.
  String get _partnerName {
    final groom = report.groomName ?? '';
    final bride = report.brideName ?? '';
    if (myName.isNotEmpty && groom == myName && bride.isNotEmpty) return bride;
    if (myName.isNotEmpty && bride == myName && groom.isNotEmpty) return groom;
    final both = [groom, bride].where((s) => s.isNotEmpty).join(' & ');
    return both.isEmpty ? 'Your match' : both;
  }

  @override
  Widget build(BuildContext context) {
    final hasPdf = report.analysisPdfs.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_partnerName,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Completed',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.green)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _row('Request Date', _date(report.createdAt)),
          _row('Completed Date', _date(report.completedAt)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _viewReport(context),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View Report'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(42),
                  ),
                ),
              ),
              if (hasPdf) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => openRemoteFile(
                        context, report.analysisPdfs.first,
                        pdf: true),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Download PDF'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(42)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
                width: 120,
                child: Text(k,
                    style:
                        TextStyle(fontSize: 12.5, color: Colors.grey[600]))),
            Text(v,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  void _viewReport(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Horoscope Analysis — $_partnerName',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (report.analysisText.trim().isNotEmpty)
              Text(report.analysisText,
                  style: const TextStyle(fontSize: 14, height: 1.5))
            else
              Text('The astrologer attached the analysis as a file below.',
                  style: TextStyle(color: Colors.grey[600])),
            if (report.analysisImages.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Images',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < report.analysisImages.length; i++)
                    ActionChip(
                      avatar: const Icon(Icons.image, size: 16),
                      label: Text('Image ${i + 1}'),
                      onPressed: () => openRemoteFile(
                          ctx, report.analysisImages[i],
                          pdf: false),
                    ),
                ],
              ),
            ],
            if (report.analysisPdfs.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('PDF Reports',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < report.analysisPdfs.length; i++)
                    ActionChip(
                      avatar: const Icon(Icons.picture_as_pdf, size: 16),
                      label: Text('PDF ${i + 1}'),
                      onPressed: () =>
                          openRemoteFile(ctx, report.analysisPdfs[i], pdf: true),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
