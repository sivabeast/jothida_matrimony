import 'package:flutter/material.dart';

import 'legal_content.dart';
import 'legal_document_screen.dart';

/// Terms & Conditions — the SAME document published on the website, rendered
/// natively and localized (§13). Registered at `/terms`.
///
/// Distinct from the Privacy Policy: eligibility, account responsibility,
/// acceptable use, payments, liability and termination.
class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[TermsConditionsScreen] build — route /terms opened');
    return LegalDocumentScreen(resolve: termsDocument);
  }
}
