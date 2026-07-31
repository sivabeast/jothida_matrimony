import 'package:flutter/material.dart';

import 'legal_content.dart';
import 'legal_document_screen.dart';

/// Child Safety Standards — imported from the website (§14). Registered at
/// `/child-safety` and linked from Settings → About.
class ChildSafetyScreen extends StatelessWidget {
  const ChildSafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[ChildSafetyScreen] build — route /child-safety opened');
    return LegalDocumentScreen(resolve: childSafetyDocument);
  }
}
