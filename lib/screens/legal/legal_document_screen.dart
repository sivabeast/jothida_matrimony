import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/value_l10n.dart';
import 'legal_content.dart';

/// Renders any [LegalDocument] (Privacy Policy, Terms & Conditions, Child
/// Safety, Delete Account) with consistent typography.
///
/// The document itself is chosen by language, so switching between English and
/// Tamil switches the whole page — heading, body and the "last updated" line
/// (§13/§14/§20).
class LegalDocumentScreen extends StatelessWidget {
  /// Resolves the document for the active language.
  final LegalDocument Function(bool tamil) resolve;

  const LegalDocumentScreen({super.key, required this.resolve});

  @override
  Widget build(BuildContext context) {
    final doc = resolve(context.isTamil);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(doc.title),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: LegalDocumentBody(resolve: resolve),
    );
  }
}

/// The scrollable body of a legal document, without a Scaffold — so a screen
/// that needs to add its own actions below the text (e.g. Delete Account) can
/// reuse the exact same rendering.
class LegalDocumentBody extends StatelessWidget {
  final LegalDocument Function(bool tamil) resolve;
  const LegalDocumentBody({super.key, required this.resolve});

  @override
  Widget build(BuildContext context) {
    final doc = resolve(context.isTamil);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Text(
          context.l10n.lastUpdatedOn(doc.lastUpdated),
          style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        for (final block in doc.blocks) _block(block),
      ],
    );
  }

  Widget _block(LegalBlock block) => switch (block) {
        LegalHeading(text: final t) => Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 6),
            child: Text(t,
                style: const TextStyle(
                    fontSize: 15,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
          ),
        LegalParagraph(text: final t) => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(t,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.55, color: Color(0xFF424242))),
          ),
        LegalBullets(items: final items) => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 6, right: 8),
                          child: Icon(Icons.circle,
                              size: 5, color: AppColors.primary),
                        ),
                        Expanded(
                          child: Text(item,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  height: 1.5,
                                  color: Color(0xFF424242))),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      };
}
