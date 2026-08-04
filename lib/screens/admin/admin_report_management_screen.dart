import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_dialogs.dart';
import '../../models/report_model.dart';
import '../../providers/report_provider.dart';
import '../../widgets/common/data_states.dart';
import '../../widgets/common/network_photo.dart';
import '../../widgets/common/skeletons.dart';

/// Admin **Report Management** (spec §8).
///
/// Two sections — Profile Reports and Chat Reports — each showing the reporter,
/// reported user, reason, description, date and status, with moderation actions
/// (Warning / Suspend / Delete / Reject / Resolve). Reviewed live from the
/// `reports` collection.
class AdminReportManagementScreen extends ConsumerWidget {
  const AdminReportManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(allReportsProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: const Text('Reports'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Profile Reports'),
              Tab(text: 'Chat Reports'),
            ],
          ),
        ),
        body: reportsAsync.when(
          loading: () => const SkeletonList(items: 6, showAvatar: false),
          error: (e, _) => ErrorStateView(
            message: 'Unable to load reports. Please try again.',
            onRetry: () => ref.invalidate(allReportsProvider),
          ),
          data: (reports) {
            final profileReports =
                reports.where((r) => r.type == ReportModel.typeProfile).toList();
            final chatReports =
                reports.where((r) => r.type == ReportModel.typeChat).toList();
            return TabBarView(
              children: [
                _ReportList(reports: profileReports, isChat: false),
                _ReportList(reports: chatReports, isChat: true),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReportList extends StatelessWidget {
  final List<ReportModel> reports;
  final bool isChat;
  const _ReportList({required this.reports, required this.isChat});

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return EmptyState(
        icon: isChat ? Icons.chat_bubble_outline : Icons.flag_outlined,
        message: isChat ? 'No chat reports' : 'No profile reports',
        subtitle: 'Reports submitted by members will appear here for review.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: reports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _ReportCard(report: reports[i]),
    );
  }
}

class _ReportCard extends ConsumerWidget {
  final ReportModel report;
  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = DateFormat('dd MMM yyyy · hh:mm a').format(report.createdAt);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: report.status == 'pending'
            ? Border.all(color: AppColors.error.withValues(alpha: 0.3))
            : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(report.reason,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              _statusChip(report.status),
            ],
          ),
          const SizedBox(height: 8),
          _kv('Reported', report.reportedName),
          _kv('Reporter', report.reporterName),
          if ((report.description ?? '').isNotEmpty)
            _kv('Details', report.description!),
          _kv('Date', date),
          if (report.isChat && (report.screenshotUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _viewScreenshot(context, report.screenshotUrl!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: NetworkPhoto(
                    url: report.screenshotUrl!, width: 90, height: 90),
              ),
            ),
          ],
          const Divider(height: 20),
          _actions(context, ref),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(reportAdminControllerProvider.notifier);
    void snack(String m) => showAppSnack(context, m);

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        _actionBtn('Warning', Icons.warning_amber_outlined, AppColors.gold,
            () async {
          await ctrl.setStatus(report.id, 'warned');
          snack('Marked as warned.');
        }),
        _actionBtn('Suspend', Icons.pause_circle_outline, Colors.deepOrange,
            () async {
          final ok = await _confirm(context, 'Suspend user?',
              'This blocks ${report.reportedName}\'s account and deactivates '
              'their profile.');
          if (!ok) return;
          await ctrl.suspendUser(report);
          snack('User suspended.');
        }),
        if (!report.isChat)
          _actionBtn('Delete', Icons.delete_outline, AppColors.error, () async {
            final ok = await _confirm(context, 'Delete profile?',
                'This permanently deletes ${report.reportedName}\'s profile. '
                'This cannot be undone.');
            if (!ok) return;
            await ctrl.deleteReportedProfile(report);
            snack('Profile deleted.');
          }),
        _actionBtn('Reject', Icons.thumb_down_outlined, Colors.grey, () async {
          await ctrl.setStatus(report.id, 'rejected');
          snack('Report rejected.');
        }),
        _actionBtn('Resolve', Icons.check_circle_outline, AppColors.success,
            () async {
          await ctrl.setStatus(report.id, 'resolved');
          snack('Report resolved.');
        }),
      ],
    );
  }

  Future<bool> _confirm(BuildContext context, String title, String body) =>
      showAppConfirmDialog(
        context,
        title: title,
        message: body,
        confirmLabel: 'Confirm',
        icon: Icons.gavel_rounded,
        danger: true,
      );

  void _viewScreenshot(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(child: NetworkPhoto(url: url)),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(
          String label, IconData icon, Color color, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 12.5)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withOpacity(0.4)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          visualDensity: VisualDensity.compact,
          minimumSize: const Size(0, 34),
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 74,
                child: Text(k,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[600]))),
            Expanded(
                child: Text(v,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500))),
          ],
        ),
      );

  Widget _statusChip(String status) {
    Color c;
    switch (status) {
      case 'pending':
        c = AppColors.error;
        break;
      case 'resolved':
        c = AppColors.success;
        break;
      case 'suspended':
      case 'deleted':
        c = Colors.deepOrange;
        break;
      case 'warned':
        c = AppColors.gold;
        break;
      default:
        c = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: c.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Text(status[0].toUpperCase() + status.substring(1),
          style: TextStyle(
              color: c, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}
