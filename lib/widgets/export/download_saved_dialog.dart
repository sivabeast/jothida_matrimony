import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import 'profile_form_export.dart';

/// Confirmation shown AFTER a profile download has been written to the phone.
///
/// The save and the share are deliberately two separate steps. The file is
/// already on the device by the time this appears — the dialog says where it
/// went, and sharing is an extra the member opts into, not a hoop they have to
/// jump through to keep the file.
///
/// Never call this before the write succeeds: it states the file is saved.
Future<void> showDownloadSavedDialog(
  BuildContext context, {
  required ExportResult result,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final l10n = ctx.l10n;
      return AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.download_done_rounded,
              color: AppColors.success, size: 30),
        ),
        title: Text(l10n.profileDownloaded, textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.profileSavedTo(result.location),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Colors.grey[700]),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                // Hand the saved bytes to the Android share sheet, so WhatsApp
                // and everything else that accepts a PDF/image shows up.
                await Share.shareXFiles(
                  [for (final p in result.sharePaths) XFile(p)],
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              icon: const Icon(Icons.share_outlined, size: 19),
              label: Text(l10n.share),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[700],
                minimumSize: const Size.fromHeight(44),
              ),
              child: Text(l10n.done),
            ),
          ),
        ],
      );
    },
  );
}
