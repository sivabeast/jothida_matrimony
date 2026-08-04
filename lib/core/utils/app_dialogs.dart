import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Material 3 dialog + snack helpers so every confirmation popup in the app
/// shares one look: tinted icon badge, title, description, Cancel + Confirm.

/// Confirmation dialog. Resolves to `true` only when the user confirms.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  IconData icon = Icons.help_outline_rounded,
  bool danger = false,
}) async {
  final accent = danger ? AppColors.error : AppColors.primary;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 30, color: accent),
      ),
      title: Text(title, textAlign: TextAlign.center),
      titleTextStyle: Theme.of(ctx).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
      content: Text(message, textAlign: TextAlign.center),
      contentTextStyle: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.45,
          ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel ?? MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: accent),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Informational dialog with a single dismiss action.
Future<void> showAppInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? closeLabel,
  IconData icon = Icons.info_outline_rounded,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 30, color: AppColors.primary),
      ),
      title: Text(title, textAlign: TextAlign.center),
      titleTextStyle: Theme.of(ctx).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
      content: Text(message, textAlign: TextAlign.center),
      contentTextStyle: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.45,
          ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(closeLabel ?? MaterialLocalizations.of(ctx).okButtonLabel),
        ),
      ],
    ),
  );
}

/// Friendly floating snack — success/info/error without technical jargon.
void showAppSnack(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: error ? AppColors.error : AppColors.textPrimary,
      content: Text(message),
    ));
}
