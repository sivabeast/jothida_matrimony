import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers/announcement_provider.dart';
import '../../../providers/notification_provider.dart';
import '../tabs/astrologer_notifications_tab.dart';

/// Full-screen Employee Notifications page, opened from the portal's bell.
/// Shows ONLY employee-audience content: admin → employee broadcasts
/// (announcements, reminders, maintenance…) plus the employee's own per-account
/// notifications (new report assigned…). User notifications never appear here.
class AstrologerNotificationsPage extends ConsumerStatefulWidget {
  const AstrologerNotificationsPage({super.key});

  @override
  ConsumerState<AstrologerNotificationsPage> createState() =>
      _AstrologerNotificationsPageState();
}

class _AstrologerNotificationsPageState
    extends ConsumerState<AstrologerNotificationsPage> {
  @override
  void initState() {
    super.initState();
    // Opening the page clears the bell badge: per-account notifications are
    // batch-marked read; announcements are marked read as they are tapped.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(notificationNotifierProvider.notifier).markAllRead();
      final announcements = ref.read(employeeAnnouncementsProvider);
      ref
          .read(announcementsReadProvider.notifier)
          .markAllRead(announcements.map((a) => a.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: const AstrologerNotificationsTab(),
    );
  }
}
