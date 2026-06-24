import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../home/tabs/notifications_tab.dart';

/// Full-screen Notifications page (header Drawer + bell icon). Wraps the
/// existing [NotificationsTab] list in a Scaffold so it can be pushed as a
/// route, not only opened inline.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(context.l10n.notifications),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: const NotificationsTab(),
    );
  }
}
