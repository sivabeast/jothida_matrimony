import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';

/// Privacy Policy — static legal content. Registered at `/privacy-policy`.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[PrivacyPolicyScreen] build — route /privacy-policy opened');
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _Para(
            'Last updated: June 2026\n\n'
            '${AppConstants.appName} ("we", "our", "us") respects your privacy. '
            'This policy explains what we collect, how we use it, and the choices you have.',
          ),
          _Heading('1. Information We Collect'),
          _Para(
            'Account details (name, email, phone), profile information (date of birth, '
            'horoscope details, education, occupation, family details), photos you upload, '
            'and usage data needed to operate the matrimony service.',
          ),
          _Heading('2. How We Use Your Information'),
          _Para(
            'To create and display your profile to potential matches, compute horoscope '
            'compatibility (Porutham), provide astrologer consultations, process subscription '
            'payments, and keep the platform safe.',
          ),
          _Heading('3. Sharing'),
          _Para(
            'Your profile is visible to other registered members as part of the matchmaking '
            'service. We do not sell your personal data. Payment processing is handled by our '
            'payment partner (Razorpay). We may share data with law enforcement when legally required.',
          ),
          _Heading('4. Data Security'),
          _Para(
            'We use industry-standard security including encrypted transport and access controls. '
            'No method of transmission is 100% secure, but we work hard to protect your data.',
          ),
          _Heading('5. Your Rights'),
          _Para(
            'You can view, edit, or delete your profile at any time from the app. To delete your '
            'account and associated data, contact support@jothidamatrimony.com.',
          ),
          _Heading('6. Contact'),
          _Para(
            'For privacy questions, email support@jothidamatrimony.com.',
          ),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 15,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                color: AppColors.primary)),
      );
}

class _Para extends StatelessWidget {
  final String text;
  const _Para(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontSize: 13.5, height: 1.55, color: Colors.grey[800]),
      );
}
