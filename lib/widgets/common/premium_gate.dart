import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

/// Shows an "upgrade to unlock" dialog for a feature gated behind a paid plan,
/// with a button that navigates to the Subscription screen. Use at every
/// free-plan restriction point so the gate is consistent and discoverable.
Future<void> showUpgradeDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.workspace_premium, color: AppColors.gold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      content: Text(message, style: const TextStyle(fontSize: 14, height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Not now'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            context.push('/subscription');
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.lock_open, size: 18),
          label: const Text('Upgrade'),
        ),
      ],
    ),
  );
}
