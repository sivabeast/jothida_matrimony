import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/phone_utils.dart';

/// Help & Support — contact options + FAQ. Registered at `/help`.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const String supportEmail = 'support@jothidamatrimony.com';
  static const String supportPhone = '+919000000000';

  @override
  Widget build(BuildContext context) {
    debugPrint('[HelpSupportScreen] build — route /help opened');
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Contact card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('We are here to help',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Reach the ${AppConstants.appName} support team',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ContactTile(
            icon: Icons.email_outlined,
            title: 'Email Us',
            subtitle: supportEmail,
            onTap: () => _launch(
              context,
              Uri(
                scheme: 'mailto',
                path: supportEmail,
                query: 'subject=${Uri.encodeComponent('${AppConstants.appName} Support')}',
              ),
            ),
          ),
          _ContactTile(
            icon: Icons.call_outlined,
            title: 'Call Us',
            subtitle: '+91 90000 00000',
            onTap: () => _launch(context, phoneCallUri(supportPhone)),
          ),
          _ContactTile(
            icon: Icons.chat_outlined,
            title: 'WhatsApp',
            subtitle: 'Chat with support',
            onTap: () => _launch(context, whatsappUri(supportPhone)),
          ),
          const SizedBox(height: 24),
          const Text('Frequently Asked Questions',
              style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._faqs.map((f) => _FaqTile(question: f.$1, answer: f.$2)),
          const SizedBox(height: 24),
          Center(
            child: Text('${AppConstants.appName} • v${AppConstants.appVersion}',
                style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ),
        ],
      ),
    );
  }

  static const List<(String, String)> _faqs = [
    (
      'How do I verify my profile?',
      'Go to Home and tap "Verify Now" on the verification card, then upload a government ID. Our team reviews it within 24–48 hours.'
    ),
    (
      'How does horoscope matching work?',
      'We compute Porutham (compatibility) from both horoscopes. Open a match and tap Compatibility, or consult an astrologer from the Astrologer tab.'
    ),
    (
      'How do I upgrade to Premium?',
      'Open Profile → Subscription Plans (or the Go Premium banner on Home) and choose a plan. Payments are processed securely via Razorpay.'
    ),
    (
      'How do I edit my preferences?',
      'Tap Partner Preferences on the Home screen to set your preferred age, location, education, horoscope and more.'
    ),
    (
      'How do I delete my account?',
      'Email us at $supportEmail from your registered address and we will process the deletion within 7 days.'
    ),
  ];

  static Future<void> _launch(BuildContext context, Uri uri) async {
    debugPrint('[HelpSupportScreen] launching $uri');
    final ok = await canLaunchUrl(uri);
    if (ok) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${uri.scheme}. Please try again.')),
      );
    }
  }
}

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ContactTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.1),
          child: Icon(icon, color: AppColors.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: AppColors.primary,
          collapsedIconColor: AppColors.primary,
          title: Text(question,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(answer,
                  style: TextStyle(color: Colors.grey[700], fontSize: 13, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}
