import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_actions.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../core/utils/report_pdf.dart';
import '../../../core/utils/value_l10n.dart';
import '../../../widgets/common/app_logo.dart';
import '../../../widgets/common/network_photo.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../models/compatibility_report_model.dart';
import '../../../providers/match_analysis_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../report/compatibility_report_screen.dart';
import '../../report/report_submission_details_screen.dart';

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
          // Request a NEW Horoscope Report for any two people (spec §1–§9).
          //
          // NO gate of any kind: a guest opens the form, fills in both
          // horoscopes and SUBMITS, all without an account. A signed-in member
          // gets their own profile pre-filled into Person 1 — as editable
          // defaults, never as locked values — and the request is linked to
          // their account so they can track it here afterwards.
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: const _NewReportButton(),
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
      // A blank page tells the member nothing. The empty state names what is
      // missing and offers the one action that fills it (spec §45).
      return _empty(context, Icons.description_outlined, emptyText,
          hint: context.l10n.noReportsYetHint, showRequestCta: true);
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

  Widget _empty(
    BuildContext context,
    IconData icon,
    String text, {
    VoidCallback? retry,
    String? hint,
    bool showRequestCta = false,
  }) =>
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 56, color: AppColors.primary.withValues(alpha: 0.35)),
              const SizedBox(height: 14),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15.5,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins')),
              if (hint != null) ...[
                const SizedBox(height: 8),
                Text(hint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.grey[600], fontSize: 13, height: 1.5)),
              ],
              if (retry != null) ...[
                const SizedBox(height: 14),
                OutlinedButton(
                    onPressed: retry, child: Text(context.l10n.tryAgain)),
              ],
              if (showRequestCta) ...[
                const SizedBox(height: 20),
                const _NewReportButton(),
              ],
            ],
          ),
        ),
      );
}

/// The "+ Request a new horoscope report" action. Lives in two places — above
/// the tabs and inside the empty state — so it is defined once.
class _NewReportButton extends StatelessWidget {
  const _NewReportButton();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => context.push('/request-external-report'),
          icon: const Icon(Icons.add_circle_outline, size: 19),
          label: Text(context.l10n.requestNewHoroscopeReport,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                  fontSize: 14.5, height: 1.25, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 13),
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

/// One report, presented by WHO it is about.
///
/// The card leads with the other person — their photo on the left, their name
/// on the right — because "whose report is this?" is the only question a list
/// of reports has to answer at a glance. Everything else (type, status,
/// progress, dates, the request id) sits underneath in decreasing importance,
/// and the request id is deliberately the quietest thing on the card: it is a
/// support reference, not something anyone reads by choice.
///
/// Every value is resolved from the stored request — there is no placeholder
/// name and no invented percentage. When the other person is a registered
/// member their live profile supplies the photo and the current name; when they
/// are not (an external two-chart request) the entered name stands and the
/// photo falls back to a gender-appropriate avatar rather than a broken image.
class _ReportCard extends ConsumerWidget {
  final AstrologerRequestModel report;
  final String myName;
  const _ReportCard({required this.report, required this.myName});

  static String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// The other person's profile document id, when they are a registered member.
  ///
  /// A request stores the groom side as profileA and the bride side as
  /// profileB; whichever of the two is not the viewer's own profile is the
  /// partner. External requests have no second profile at all.
  String? _partnerProfileId(String? myProfileId) {
    if (report.isExternalReport) return null;
    final a = (report.profileAId ?? '').trim();
    final b = (report.profileBId ?? '').trim();
    if (myProfileId != null && myProfileId.isNotEmpty) {
      if (a == myProfileId) return b.isEmpty ? null : b;
      if (b == myProfileId) return a.isEmpty ? null : a;
    }
    // No profile of our own to compare against — take whichever side exists.
    if (b.isNotEmpty) return b;
    return a.isEmpty ? null : a;
  }

  /// The name stored on the request for the other person. Used as-is when the
  /// partner has no live profile to read a current name from.
  String _storedPartnerName(BuildContext context) {
    if (report.isExternalReport) {
      final other = (report.externalOther['name'] ?? '').toString().trim();
      if (other.isNotEmpty) return other;
    }
    final groom = (report.groomName ?? '').trim();
    final bride = (report.brideName ?? '').trim();
    if (myName.isNotEmpty && groom == myName && bride.isNotEmpty) return bride;
    if (myName.isNotEmpty && bride == myName && groom.isNotEmpty) return groom;
    final both = [groom, bride].where((s) => s.isNotEmpty).join(' & ');
    return both.isEmpty ? context.l10n.yourMatch : both;
  }

  /// The other person's gender, so a photo-less card still shows the right
  /// avatar instead of a generic silhouette.
  String get _partnerGender {
    if (report.isExternalReport) {
      return (report.externalOther['gender'] ?? '').toString();
    }
    // profileB is the bride side, profileA the groom side.
    final bride = (report.brideName ?? '').trim();
    return myName.isNotEmpty && bride == myName ? 'Male' : 'Female';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final completed = report.status == AstrologerRequestStatus.completed;
    final rejected = report.status == AstrologerRequestStatus.rejected;

    // The partner's live profile, when there is one to read. A failed or
    // still-loading lookup simply leaves the stored name and the avatar in
    // place — the card never waits on it and never shows an error for it.
    final myProfileId = ref.watch(myProfileProvider).valueOrNull?.id;
    final partnerId = _partnerProfileId(myProfileId);
    final partner = partnerId == null
        ? null
        : ref.watch(profileByIdProvider(partnerId)).valueOrNull;

    final livePartnerName =
        (partner?.displayName(context.isTamil) ?? '').trim();
    final partnerName = livePartnerName.isNotEmpty
        ? livePartnerName
        : _storedPartnerName(context);
    final photoUrl = partner?.profilePhotoUrl ?? '';

    final statusColor = completed
        ? AppColors.success
        : rejected
            ? AppColors.error
            : AppColors.info;
    final statusLabel = completed
        ? l10n.statusCompleted
        : rejected
            ? l10n.statusRejected
            : l10n.statusUnderAnalysis;
    final statusIcon = completed
        ? Icons.check_circle
        : rejected
            ? Icons.cancel_outlined
            : Icons.hourglass_bottom;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Who this report is about ────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _photo(photoUrl),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(partnerName,
                        maxLines: 2,
                        style: const TextStyle(
                            fontSize: 16.5,
                            height: 1.25,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(l10n.horoscopeCompatibilityReport,
                        maxLines: 2,
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: Colors.grey[600])),
                    const SizedBox(height: 8),
                    _statusChip(statusLabel, statusColor, statusIcon),
                  ],
                ),
              ),
            ],
          ),
          // ── Progress — the real stage, never an invented percentage ──────
          if (!rejected) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (_stageIndex(report) + 1) / _stageCount,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(statusColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(completed ? l10n.reportReadyMsg : l10n.reportPreparingMsg,
                style: TextStyle(
                    fontSize: 11.5, height: 1.4, color: Colors.grey[600])),
          ],
          const SizedBox(height: 12),
          _row(l10n.requestDate, _date(report.createdAt)),
          if (completed) _row(l10n.completedDate, _date(report.completedAt)),
          const SizedBox(height: 6),
          // The request id is a support reference — small, grey, last.
          Text('${l10n.requestIdLabel}: ${report.id}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: Colors.grey[400])),
          const SizedBox(height: 12),
          // ── One strong primary action ───────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => completed
                  ? _viewReport(context, partnerName)
                  : Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          ReportSubmissionDetailsScreen(request: report),
                    )),
              icon: Icon(
                  completed
                      ? Icons.visibility_outlined
                      : Icons.description_outlined,
                  size: 18),
              label: Text(completed ? l10n.viewReport : l10n.viewDetails,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(
                      fontSize: 14, height: 1.25, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          // §15 — the submitted details stay reachable from a COMPLETED report
          // too, so the member can always review exactly what they sent.
          // Read-only: there is deliberately no edit here (§16).
          if (completed) ...[
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: _DownloadReportButton(
                      report: report,
                      myName: myName,
                      partnerName: partnerName),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => ReportSubmissionDetailsScreen(
                                request: report))),
                    icon: const Icon(Icons.description_outlined, size: 17),
                    label: Text(l10n.viewDetails,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.5)),
                      minimumSize: const Size.fromHeight(42),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The other person's photo: big enough to identify them at a glance, and a
  /// gender-appropriate avatar — never a broken image — when there is none.
  Widget _photo(String url) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: NetworkPhoto(
          url: url,
          width: 78,
          height: 78,
          fit: BoxFit.cover,
          fallbackIcon: _partnerGender == 'Male'
              ? Icons.man_outlined
              : Icons.woman_outlined,
          fallbackIconSize: 38,
        ),
      );

  Widget _statusChip(String label, Color color, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ),
          ],
        ),
      );

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 120,
                child: Text(k,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[600]))),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  /// Opens the right in-app viewer for the report's content type.
  void _viewReport(BuildContext context, String partnerName) {
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
          report: report, myName: myName, partnerName: partnerName),
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
                    const AppLogo(size: 44, circle: false),
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
