import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/report_model.dart';
import '../../providers/admin_provider.dart';

class AdminReportsScreen extends ConsumerWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(allReportsProvider);

    return reportsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (reports) => reports.isEmpty
          ? const Center(child: Text('No reports'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: reports.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _ReportTile(report: reports[i]),
            ),
    );
  }
}

class _ReportTile extends ConsumerWidget {
  final ReportModel report;

  const _ReportTile({required this.report});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _alertColor(report.alertLevel);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
        child: Icon(Icons.report, color: color),
      ),
      title: Text(report.reportedName,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(report.reason),
          if (report.description != null && report.description!.isNotEmpty)
            Text(report.description!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text('By: ${report.reporterName}',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              report.alertLevel.toUpperCase(),
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          if (!report.isResolved)
            GestureDetector(
              onTap: () => ref.read(adminActionsProvider.notifier).blockUser(report.reportedUserId),
              child: const Text('Block User',
                  style: TextStyle(color: Colors.red, fontSize: 11)),
            ),
        ],
      ),
      isThreeLine: true,
    );
  }

  Color _alertColor(String level) {
    switch (level) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.deepOrange;
      case 'warning':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
