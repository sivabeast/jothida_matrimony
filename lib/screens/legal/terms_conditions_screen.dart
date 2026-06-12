import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';

/// Terms & Conditions — static legal content. Registered at `/terms`.
class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[TermsConditionsScreen] build — route /terms opened');
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Terms & Conditions'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _Para(
            'Last updated: June 2026\n\n'
            'By using ${AppConstants.appName}, you agree to these Terms & Conditions. '
            'Please read them carefully.',
          ),
          _Heading('1. Eligibility'),
          _Para(
            'You must be of legal marriageable age and legally permitted to marry under the laws '
            'applicable to you. Profiles must be created for genuine matrimonial purposes only.',
          ),
          _Heading('2. Account Responsibility'),
          _Para(
            'You are responsible for the accuracy of the information you provide and for keeping '
            'your login credentials secure. Providing false information may result in suspension.',
          ),
          _Heading('3. Acceptable Use'),
          _Para(
            'Do not harass other members, post offensive content, solicit money, or misuse contact '
            'details. Violations may lead to profile removal and reporting to authorities.',
          ),
          _Heading('4. Subscriptions & Payments'),
          _Para(
            'Premium plans are billed as described at purchase. Fees are non-refundable except where '
            'required by law. Subscriptions provide enhanced visibility and features but do not '
            'guarantee a match.',
          ),
          _Heading('5. Astrologer Services'),
          _Para(
            'Horoscope and Porutham analysis are provided for informational and cultural purposes. '
            'They do not constitute professional advice and outcomes are not guaranteed.',
          ),
          _Heading('6. Limitation of Liability'),
          _Para(
            'We are not liable for interactions between members or for any loss arising from use of '
            'the service. Members are advised to verify details independently before proceeding.',
          ),
          _Heading('7. Changes'),
          _Para(
            'We may update these terms from time to time. Continued use of the app constitutes '
            'acceptance of the revised terms.',
          ),
          _Heading('8. Contact'),
          _Para('Questions? Email support@jothidamatrimony.com.'),
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
