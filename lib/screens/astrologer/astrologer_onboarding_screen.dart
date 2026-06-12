// DEPRECATED — replaced by AstrologerRegisterScreen (/astrologer-register).
//
// The old AstrologerOnboardingScreen incorrectly asked for email, password,
// and other auth credentials after Google Sign-In had already succeeded.
// AstrologerRegisterScreen (the replacement):
//   • pre-fills Full Name, Email, and Profile Photo from the authenticated
//     Google account — credentials are NEVER asked for again
//   • collects only astrologer-specific fields (phone, gender, DOB,
//     location, experience, specializations, languages, fee, about,
//     optional photo update, optional verification document)
//   • saves to Firestore `astrologers/{uid}` with profileCompleted: true
//   • navigates to AstrologerDashboardScreen on completion
//
// The router no longer imports or routes to this file.

// ignore_for_file: deprecated_member_use_from_same_package
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

@Deprecated('Use AstrologerRegisterScreen (/astrologer-register) instead.')
class AstrologerOnboardingScreen extends StatelessWidget {
  const AstrologerOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Should never be reached — router no longer routes here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go('/astrologer-register');
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
