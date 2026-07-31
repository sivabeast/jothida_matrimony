import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/utils/value_l10n.dart';
import '../legal/legal_content.dart';

/// Help & Support — contact options + FAQ. Registered at `/help`.
///
/// Contact details come from [SupportContact] (§22), the single place they are
/// defined, so the legal pages and this screen can never drift apart.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[HelpSupportScreen] build — route /help opened');
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.helpSupport),
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
                Text(l10n.weAreHereToHelp,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(l10n.reachSupportTeam(AppConstants.appName),
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ContactTile(
            icon: Icons.email_outlined,
            title: l10n.emailUs,
            subtitle: SupportContact.email,
            onTap: () => _launch(
              context,
              Uri(
                scheme: 'mailto',
                path: SupportContact.email,
                query:
                    'subject=${Uri.encodeComponent('${AppConstants.appName} Support')}',
              ),
            ),
          ),
          _ContactTile(
            icon: Icons.call_outlined,
            title: l10n.callUs,
            subtitle: SupportContact.phoneDisplay,
            onTap: () =>
                _launch(context, phoneCallUri(SupportContact.phoneE164)),
          ),
          _ContactTile(
            icon: Icons.chat_outlined,
            title: l10n.whatsapp,
            subtitle: SupportContact.phoneDisplay,
            onTap: () => _launch(context, whatsappUri(SupportContact.phoneE164)),
          ),
          const SizedBox(height: 24),
          Text(l10n.faqTitle,
              style: const TextStyle(
                  fontSize: 16,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._faqs(context).map((f) => _FaqTile(question: f.$1, answer: f.$2)),
          const SizedBox(height: 24),
          Center(
            child: Text('${AppConstants.appName} • v${AppConstants.appVersion}',
                style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// FAQ content, in the active language.
  static List<(String, String)> _faqs(BuildContext context) {
    if (context.isTamil) {
      return [
        (
          'என் சுயவிவரப் புகைப்படத்தை எப்படி மாற்றுவது?',
          'எனது சுயவிவரம் → சுயவிவரப் புகைப்படம் என்பதைத் திறந்து படத்தைத் '
              'தேர்ந்தெடுக்கவும். 1:1 சதுரமாக வெட்டிய பிறகே படம் சேமிக்கப்படும், '
              'மேலும் அது பழைய படத்தை மாற்றும். ஒரு உறுப்பினருக்கு ஒரே ஒரு '
              'புகைப்படம் மட்டுமே.'
        ),
        (
          'என் தகவல்களை மற்றவர்கள் பார்க்காமல் எப்படி மறைப்பது?',
          'கைபேசி எண், சம்பளம், ஜாதக விவரங்கள் மற்றும் சுயவிவரப் புகைப்படம் '
              'இயல்பாகவே மறைக்கப்பட்டுள்ளன. அமைப்புகள் → தனியுரிமை அமைப்புகளில் '
              'நீங்களே அவற்றை இயக்கும் வரை மறைந்தே இருக்கும் — விருப்பம் '
              'ஏற்கப்பட்டாலும் தானாக வெளிப்படாது.'
        ),
        (
          'ஜாதகப் பொருத்தம் எப்படி வேலை செய்கிறது?',
          'இரு ஜாதகங்களிலிருந்தும் பொருத்தம் கணக்கிடப்படுகிறது. ஒரு வரனைத் '
              'திறந்து பொருத்தம் என்பதைத் தட்டவும், அல்லது ஜோதிடர் சந்திப்பை '
              'இலவசமாக முன்பதிவு செய்யவும்.'
        ),
        (
          'ஜோதிடர் சந்திப்புக்குக் கட்டணம் உண்டா?',
          'இல்லை. நேரத்தைத் தேர்ந்தெடுத்து சந்திப்பை முன்பதிவு செய்வது '
              'முற்றிலும் இலவசம். முன்பதிவு "எனது முன்பதிவுகள்" பக்கத்திலும் '
              'ஜோதிடர் டாஷ்போர்டிலும் தோன்றும்.'
        ),
        (
          'சுயவிவரத்தைத் திருத்த முடியுமா?',
          'ஆம். பெயர், பிறந்த தேதி, கல்வி, பணி, சம்பளம், ஜாதகம், துணை விருப்பம், '
              'குடும்ப விவரங்கள், கைபேசி எண், மின்னஞ்சல் உட்பட ஒவ்வொரு புலத்தையும் '
              'எனது சுயவிவரம் பக்கத்திலிருந்து எப்போது வேண்டுமானாலும் திருத்தலாம்.'
        ),
        (
          'என் கணக்கை எப்படி நீக்குவது?',
          'அமைப்புகள் → கணக்கை நீக்கு என்பதைத் திறக்கவும். நீக்கம் உடனடியானது; '
              'என்ன அழிக்கப்படுகிறது என்பதை அந்தப் பக்கம் விவரிக்கிறது.'
        ),
      ];
    }
    return [
      (
        'How do I change my profile photo?',
        'Open My Profile → Profile Photo and pick an image. The photo is saved '
            'only after you crop it to a 1:1 square, and it replaces your '
            'previous photo — every member has exactly one photo.'
      ),
      (
        'How do I keep my details private?',
        'Your phone number, salary, horoscope details and profile photo are '
            'hidden by default. They stay hidden until you switch them on '
            'yourself in Settings → Privacy Settings — accepting an interest '
            'never reveals them.'
      ),
      (
        'How does horoscope matching work?',
        'We compute Porutham (compatibility) from both horoscopes. Open a '
            'match and tap Compatibility, or book a free astrologer '
            'appointment.'
      ),
      (
        'Is the astrologer appointment free?',
        'Yes. Selecting a slot and booking an appointment is completely free — '
            'there are no booking charges. Your booking appears in My Bookings '
            'and on the astrologer dashboard.'
      ),
      (
        'Can I edit my profile after creating it?',
        'Yes. Every field — name, date of birth, education, career, salary, '
            'horoscope, partner preference, family details, mobile number and '
            'email — can be edited at any time from My Profile. Nothing is '
            'permanently locked.'
      ),
      (
        'How do I delete my account?',
        'Open Settings → Delete Account. Deletion is immediate and '
            'self-service; that page explains exactly what is removed.'
      ),
    ];
  }

  static Future<void> _launch(BuildContext context, Uri uri) async {
    debugPrint('[HelpSupportScreen] launching $uri');
    final ok = await canLaunchUrl(uri);
    if (ok) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.couldNotOpenScheme(uri.scheme))),
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
