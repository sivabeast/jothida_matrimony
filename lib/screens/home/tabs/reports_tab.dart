import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_actions.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../core/utils/report_pdf.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../models/compatibility_report_model.dart';
import '../../../providers/match_analysis_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../report/compatibility_report_screen.dart';

/// Requests the self-heal has already retried this app session, so a stuck
/// request is re-assigned at most once per launch (assignRequest itself is
/// also idempotent).
final Set<String> _assignRetryAttempted = <String>{};

/// Reports tab (bottom-nav item 4) — every Horoscope Compatibility Report the
/// user has requested, split into two tabs:
///   • Under Analysis — requests still being prepared (not completed).
///   • Completed      — finished reports, with View Report + Download Report.
///
/// View Report opens the right IN-APP viewer for the content (PDF viewer /
/// image viewer / styled report page). Download Report always delivers ONE
/// valid file: the uploaded PDF as-is, images as-is, or — for text and
/// text+image reports — a professionally generated PDF (logo, title, names,
/// date, description, images, footer). No external-viewer dependency, so
/// "Could not open this file" is gone.
class ReportsTab extends ConsumerWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(myMatchAnalysisRequestsProvider);
    final all = async.valueOrNull ?? const <AstrologerRequestModel>[];

    // Self-healing assignment: a horoscope request stuck with NO assignee
    // (its booking-time auto-assignment failed) is re-assigned the moment the
    // user opens Reports. Internal office appointments (astrologerId set) are
    // never touched, and each request is retried at most once per session.
    ref.listen(myMatchAnalysisRequestsProvider, (_, next) {
      final list = next.valueOrNull;
      if (list == null) return;
      for (final r in list) {
        if (r.status == AstrologerRequestStatus.completed) continue;
        if (r.astrologerEmail.isNotEmpty || r.astrologerId.isNotEmpty) continue;
        if (!_assignRetryAttempted.add(r.id)) continue;
        ref
            .read(matchAnalysisControllerProvider.notifier)
            .retryAssignment(r.id);
      }
    });
    final myName = ref.watch(myProfileProvider).valueOrNull?.fullName ?? '';

    final sorted = [...all]
      ..sort((a, b) => (b.completedAt ?? b.createdAt)
          .compareTo(a.completedAt ?? a.createdAt));
    final underAnalysis = sorted
        .where((r) => r.status != AstrologerRequestStatus.completed)
        .toList();
    final completed = sorted
        .where((r) => r.status == AstrologerRequestStatus.completed)
        .toList();

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            alignment: Alignment.centerLeft,
            child: Text(l10n.reports,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 18)),
          ),
          Container(
            color: Colors.white,
            child: TabBar(
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.primary,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              tabs: [
                Tab(text: l10n.underAnalysisTab(underAnalysis.length)),
                Tab(text: l10n.completedTab(completed.length)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _list(context, ref, underAnalysis, myName, async.isLoading,
                    async.hasError, l10n.noReportsUnderAnalysis),
                _list(context, ref, completed, myName, async.isLoading,
                    async.hasError, l10n.noCompletedReports),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<AstrologerRequestModel> reports,
    String myName,
    bool loading,
    bool hasError,
    String emptyText,
  ) {
    if (reports.isEmpty) {
      if (loading) {
        return const Center(
            child: CircularProgressIndicator(color: AppColors.primary));
      }
      if (hasError) {
        return _empty(
            context, Icons.error_outline, context.l10n.couldNotLoadYourReports,
            retry: () => ref.invalidate(myMatchAnalysisRequestsProvider));
      }
      return _empty(context, Icons.description_outlined, emptyText);
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        // Pull-to-refresh is an explicit "try again": clear the once-per-session
        // guard so a request whose assignment failed earlier is retried, not
        // skipped for the rest of the app's life.
        _assignRetryAttempted.clear();
        ref.invalidate(myMatchAnalysisRequestsProvider);
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) =>
            _ReportCard(report: reports[i], myName: myName),
      ),
    );
  }

  Widget _empty(BuildContext context, IconData icon, String text,
          {VoidCallback? retry}) =>
      Center(
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
                    onPressed: retry, child: Text(context.l10n.tryAgain)),
              ],
            ],
          ),
        ),
      );
}

/// Index of the current user-facing stage for [r]: any paid-but-not-completed
/// request is "Under Analysis"; completed is the final stage. Assignment steps
/// stay internal (spec §8).
int _stageIndex(AstrologerRequestModel r) =>
    r.status == AstrologerRequestStatus.completed ? 3 : 1;

const int _stageCount = 4;

class _ReportCard extends ConsumerWidget {
  final AstrologerRequestModel report;
  final String myName;
  const _ReportCard({required this.report, required this.myName});

  String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String get _partnerName {
    final groom = report.groomName ?? '';
    final bride = report.brideName ?? '';
    if (myName.isNotEmpty && groom == myName && bride.isNotEmpty) return bride;
    if (myName.isNotEmpty && bride == myName && groom.isNotEmpty) return groom;
    final both = [groom, bride].where((s) => s.isNotEmpty).join(' & ');
    return both.isEmpty ? 'Your match' : both;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final completed = report.status == AstrologerRequestStatus.completed;
    final idx = _stageIndex(report);
    final color = completed ? Colors.green : Colors.blue;
    final label = completed ? l10n.statusCompleted : l10n.statusPending;

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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (idx + 1) / _stageCount,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            completed ? l10n.reportReadyMsg : l10n.reportPreparingMsg,
            style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
          ),
          const SizedBox(height: 10),
          _row(l10n.requestDate, _date(report.createdAt)),
          if (completed) _row(l10n.completedDate, _date(report.completedAt)),
          if (completed) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _viewReport(context),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: Text(l10n.viewReport),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(42),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DownloadReportButton(
                      report: report,
                      myName: myName,
                      partnerName: _partnerName),
                ),
              ],
            ),
          ],
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

  /// Opens the right in-app viewer for the report's content type.
  void _viewReport(BuildContext context) {
    // Structured Marriage Compatibility Report → the read-only A4-style page.
    final compat = CompatibilityReport.tryFrom(report.compatReport);
    if (compat != null && compat.isSubmitted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            CompatibilityReportScreen(requestId: report.id, request: report),
      ));
      return;
    }
    final hasText = report.analysisText.trim().isNotEmpty;
    final hasImages = report.analysisImages.isNotEmpty;
    final hasPdfs = report.analysisPdfs.isNotEmpty;

    // Pure PDF report → in-app PDF viewer.
    if (hasPdfs && !hasText && !hasImages) {
      openPdfInApp(context, report.analysisPdfs.first,
          title: context.l10n.horoscopeAnalysisReport);
      return;
    }
    // Pure image report → in-app image gallery.
    if (hasImages && !hasText && !hasPdfs) {
      showImageGallery(context, report.analysisImages);
      return;
    }
    // Text / mixed → styled full report page (one complete report experience).
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReportViewScreen(
          report: report, myName: myName, partnerName: _partnerName),
    ));
  }
}

/// "Download Report" — always delivers ONE valid file via the system
/// save/share sheet, with a busy spinner while preparing.
class _DownloadReportButton extends StatefulWidget {
  final AstrologerRequestModel report;
  final String myName;
  final String partnerName;
  const _DownloadReportButton(
      {required this.report, required this.myName, required this.partnerName});

  @override
  State<_DownloadReportButton> createState() => _DownloadReportButtonState();
}

class _DownloadReportButtonState extends State<_DownloadReportButton> {
  bool _busy = false;

  Future<void> _download() async {
    final r = widget.report;
    // Structured Marriage Compatibility Report → open the report page with the
    // PDF/Image download sheet already presented (A4 rasterised export).
    final compat = CompatibilityReport.tryFrom(r.compatReport);
    if (compat != null && compat.isSubmitted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CompatibilityReportScreen(
            requestId: r.id, request: r, autoDownload: true),
      ));
      return;
    }
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final hasText = r.analysisText.trim().isNotEmpty;
      final hasImages = r.analysisImages.isNotEmpty;
      final hasPdfs = r.analysisPdfs.isNotEmpty;

      if (hasPdfs) {
        // Employee uploaded a finished PDF → download it as-is.
        await downloadRemotePdf(context, r.analysisPdfs.first,
            fileName: 'jothida_report_${r.id}.pdf');
      } else if (hasImages && !hasText) {
        // Image-only report → download the images.
        await downloadRemoteImages(context, r.analysisImages);
      } else if (hasText || hasImages) {
        // Text / text+images → generate ONE professional PDF.
        messenger.showSnackBar(SnackBar(content: Text(l10n.preparingReport)));
        final bytes = await ReportPdfBuilder.build(
          reportTitle:
              '${l10n.horoscopeAnalysisReport} — ${widget.partnerName}',
          userName: widget.myName.isNotEmpty ? widget.myName : r.userName,
          employeeName: r.astrologerName,
          reportDate: r.completedAt ?? r.createdAt,
          description: r.analysisText,
          imageUrls: r.analysisImages,
        );
        await sharePdfBytes(bytes, fileName: 'jothida_report_${r.id}.pdf');
      } else {
        messenger
            .showSnackBar(SnackBar(content: Text(l10n.reportDownloadFailed)));
      }
    } catch (e) {
      debugPrint('[Reports] download failed: $e');
      messenger
          .showSnackBar(SnackBar(content: Text(l10n.reportDownloadFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _download,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.download_outlined, size: 18),
      label: Text(context.l10n.downloadReport),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        minimumSize: const Size.fromHeight(42),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// Full-page styled report view — logo header, meta card, analysis text,
/// inline images (tap → zoomable gallery) and PDF attachments (tap → in-app
/// PDF viewer). One complete report experience for text/mixed reports.
class ReportViewScreen extends StatelessWidget {
  final AstrologerRequestModel report;
  final String myName;
  final String partnerName;
  const ReportViewScreen({
    super.key,
    required this.report,
    required this.myName,
    required this.partnerName,
  });

  String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = report.analysisText.trim();
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.horoscopeAnalysisReport),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header card — logo + title + meta.
          Container(
            padding: const EdgeInsets.all(16),
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset('assets/images/app_logo.png',
                          width: 44,
                          height: 44,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.auto_awesome,
                              color: AppColors.primary,
                              size: 36)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.appTitle,
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppColors.primary)),
                          Text(l10n.reportFor(partnerName),
                              style: TextStyle(
                                  fontSize: 12.5, color: Colors.grey[700])),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _meta(l10n.name, myName.isNotEmpty ? myName : report.userName),
                _meta(l10n.preparedBy, report.astrologerName),
                _meta(l10n.reportDate,
                    _date(report.completedAt ?? report.createdAt)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (text.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05), blurRadius: 8)
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.descriptionLabel,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: AppColors.primary)),
                  const SizedBox(height: 10),
                  Text(text,
                      style: const TextStyle(fontSize: 14, height: 1.55)),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(l10n.attachedAsFile,
                  style: TextStyle(color: Colors.grey[600])),
            ),
          if (report.analysisImages.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(l10n.imagesLabel,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5)),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.2,
              ),
              itemCount: report.analysisImages.length,
              itemBuilder: (_, i) => InkWell(
                onTap: () => showImageGallery(context, report.analysisImages,
                    initialIndex: i),
                borderRadius: BorderRadius.circular(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    report.analysisImages[i],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image_outlined,
                          color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (report.analysisPdfs.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(l10n.pdfReportsLabel,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5)),
            const SizedBox(height: 8),
            for (var i = 0; i < report.analysisPdfs.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withOpacity(0.25)),
                ),
                child: ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined,
                      color: AppColors.primary),
                  title: Text('${l10n.pdfReportsLabel} ${i + 1}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  trailing:
                      const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => openPdfInApp(context, report.analysisPdfs[i],
                      title: l10n.horoscopeAnalysisReport),
                ),
              ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _meta(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
                width: 110,
                child: Text(k,
                    style:
                        TextStyle(fontSize: 12.5, color: Colors.grey[600]))),
            Expanded(
              child: Text(v.trim().isEmpty ? '—' : v,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
