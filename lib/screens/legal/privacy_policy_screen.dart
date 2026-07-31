import 'package:flutter/material.dart';

import 'legal_content.dart';
import 'legal_document_screen.dart';

/// Privacy Policy — the SAME document published on the website, rendered
/// natively and localized (§13). Registered at `/privacy-policy`.
///
/// This is a distinct document from the Terms & Conditions; the two used to
/// ship near-identical placeholder copy.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[PrivacyPolicyScreen] build — route /privacy-policy opened');
    return LegalDocumentScreen(resolve: privacyPolicyDocument);
  }
}
