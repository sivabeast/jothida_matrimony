import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/dashboard_analytics.dart';

/// Formats an INR amount with Indian digit grouping, e.g. 850000 → "₹8,50,000".
String inr(int n) {
  final neg = n < 0;
  var s = n.abs().toString();
  if (s.length > 3) {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    s = '${parts.join(',')},$last3';
  }
  return '${neg ? '-' : ''}₹$s';
}

// ── CSV helpers ──────────────────────────────────────────────────────────────

String _cell(Object? v) {
  final s = '$v';
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String _rows(List<List<Object?>> rows) =>
    rows.map((r) => r.map(_cell).join(',')).join('\n');

/// Writes [csv] to a temp file and opens the share sheet so the admin can save
/// it (Drive, Files, email, etc.) as a .csv that Excel/Sheets opens directly.
Future<void> _shareCsv(
    BuildContext context, String filename, String csv) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(csv);
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')],
        subject: filename);
  } catch (e) {
    debugPrint('[Admin] export failed: $e');
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not export the report. Please try again.')),
    );
  }
}

String _stamp() {
  final n = DateTime.now();
  return '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}';
}

// ── Reports ──────────────────────────────────────────────────────────────────

Future<void> exportRevenueCsv(BuildContext context, DashboardAnalytics a) {
  final rows = <List<Object?>>[
    ['Revenue Report', 'Generated', DateTime.now().toIso8601String()],
    [],
    ['Period', 'Amount (INR)'],
    ['Today', a.revenueToday],
    ['This Week', a.revenueWeek],
    ['This Month', a.revenueMonth],
    ['This Year', a.revenueYear],
    ['All Time', a.revenueTotal],
    [],
    ['Daily Trend (last 7 days)', ''],
    ['Day', 'Amount (INR)'],
    for (final p in a.revenueDaily) [p.label, p.amount],
    [],
    ['Monthly Trend (last 6 months)', ''],
    ['Month', 'Amount (INR)'],
    for (final p in a.revenueMonthly) [p.label, p.amount],
    [],
    ['Yearly Trend', ''],
    ['Year', 'Amount (INR)'],
    for (final p in a.revenueYearly) [p.label, p.amount],
  ];
  return _shareCsv(context, 'revenue_report_${_stamp()}.csv', _rows(rows));
}

// (exportSubscriptionsCsv was removed with the subscription system.)

Future<void> exportUsersCsv(BuildContext context, DashboardAnalytics a) {
  final rows = <List<Object?>>[
    ['User Report', 'Generated', DateTime.now().toIso8601String()],
    [],
    ['Metric', 'Count'],
    ['Total Users', a.totalUsers],
    ['New Users Today', a.newUsersToday],
    ['New Users This Week', a.newUsersWeek],
    ['New Users This Month', a.newUsersMonth],
    ['Daily Active Users', a.dailyActiveUsers],
    ['Monthly Active Users', a.monthlyActiveUsers],
    ['Married Users', a.marriedUsers],
    ['Successful Matches', a.successfulMatches],
    ['Marriage Success Rate (%)', a.marriageSuccessRate.toStringAsFixed(1)],
  ];
  return _shareCsv(context, 'user_report_${_stamp()}.csv', _rows(rows));
}

Future<void> exportAstrologersCsv(BuildContext context, DashboardAnalytics a) {
  final rows = <List<Object?>>[
    ['Astrologer Report', 'Generated', DateTime.now().toIso8601String()],
    [],
    ['Metric', 'Count'],
    ['Total Astrologers', a.totalAstrologers],
    ['Pending Verification', a.pendingAstrologers],
    ['Verified Astrologers', a.verifiedAstrologers],
    [],
    ['Top Rated Astrologers', ''],
    ['Name', 'Rating', 'Reviews'],
    for (final r in a.topRatedAstrologers)
      [r.name, r.rating.toStringAsFixed(1), r.reviewCount],
    [],
    ['Most Consulted Astrologers', ''],
    ['Name', 'Consultations'],
    for (final r in a.mostConsultedAstrologers) [r.name, r.consultations],
  ];
  return _shareCsv(context, 'astrologer_report_${_stamp()}.csv', _rows(rows));
}
