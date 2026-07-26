import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/report_model.dart';
import '../../providers/profile_provider.dart';
import '../../providers/report_provider.dart';
import '../../widgets/common/network_photo.dart';

/// User-facing Reported Users page (spec §7). Lists the reports the signed-in
/// user has filed — reported member, reason, date and current status — so they
/// can track what happened to each report.
class ReportedUsersScreen extends ConsumerWidget {
  const ReportedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final reportsAsync = ref.watch(myReportsProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.reportedUsers),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: reportsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) =>
            _EmptyState(icon: Icons.flag_outlined, text: l10n.noReportedUsers),
        data: (reports) {
          if (reports.isEmpty) {
            return _EmptyState(
                icon: Icons.flag_outlined, text: l10n.noReportedUsers);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: reports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _ReportCard(report: reports[i]),
          );
        },
      ),
    );
  }
}

class _ReportCard extends ConsumerWidget {
  final ReportModel report;
  const _ReportCard({required this.report});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  String _fmt(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// Maps an internal report status to the user-facing status label + colour.
  ({String label, Color color}) _statusView(BuildContext context) {
    final l10n = context.l10n;
    switch (report.status) {
      case 'pending':
        return (label: l10n.statusSubmitted, color: AppColors.info);
      case 'warned':
      case 'suspended':
      case 'deleted':
        return (label: l10n.statusActionTaken, color: AppColors.success);
      case 'rejected':
      case 'resolved':
        return (label: l10n.statusClosed, color: Colors.grey);
      default:
        return (label: l10n.statusUnderReview, color: AppColors.warning);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Chat reports carry no profile id; profile reports resolve the member for
    // their photo. Name always falls back to the stored reportedName.
    final profile = report.reportedUserId.isEmpty
        ? null
        : ref.watch(profileByUserIdProvider(report.reportedUserId)).valueOrNull;
    final name = (report.reportedName.trim().isNotEmpty)
        ? report.reportedName.trim()
        : (profile?.name ?? l10n.member);
    final photo = profile?.profilePhotoUrl ?? '';
    final status = _statusView(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: NetworkPhoto(url: photo, fallbackIconSize: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            fontFamily: 'Poppins')),
                    const SizedBox(height: 3),
                    Text('${l10n.reasonLabel}: ${report.reason}',
                        maxLines: 2,
                        softWrap: true,
                        style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(status.label, status.color),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.schedule, size: 13, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(_fmt(report.createdAt),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              if (report.isChat) ...[
                const SizedBox(width: 10),
                Icon(Icons.chat_bubble_outline, size: 13, color: Colors.grey[500]),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
