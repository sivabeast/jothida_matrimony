import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/account_deletion.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/value_l10n.dart';
import 'legal_content.dart';
import 'legal_document_screen.dart';

/// Delete Account — the website's account-deletion page imported into the app
/// (§14), with the actual self-service delete action attached at the bottom so
/// the member can act on what they just read. Registered at `/delete-account`.
class DeleteAccountScreen extends ConsumerWidget {
  const DeleteAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[DeleteAccountScreen] build — route /delete-account opened');
    final doc = deleteAccountDocument(context.isTamil);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(doc.title),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          const Expanded(
            child: LegalDocumentBody(resolve: deleteAccountDocument),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => confirmAndDeleteAccount(context, ref),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(context.l10n.deleteAccount),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
