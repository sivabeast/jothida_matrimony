import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../home/tabs/my_profile_tab.dart';

/// "My Profile" — the full profile hub (photo, completion, subscription and the
/// section menu), reached from the header Drawer. The body is the existing
/// [MyProfileTab]; this screen just gives it a Scaffold + AppBar now that the
/// profile is no longer a bottom-navigation tab.
class MyProfileScreen extends StatelessWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(context.l10n.myProfile),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: const MyProfileTab(),
    );
  }
}
