/// The four legal / policy documents the app publishes, in English and Tamil
/// (§13, §14, §20).
///
/// Each document is the SAME content the website publishes at
/// jothidamatrimony.in, kept here as structured data rather than free HTML so
/// the app can render it natively, switch language with the rest of the UI and
/// stay readable on every screen size.
///
/// Privacy Policy and Terms & Conditions are deliberately DIFFERENT documents
/// — the old app shipped near-identical placeholder copy for both (§13).
library;

import '../../core/constants/app_constants.dart';

/// A single rendered block inside a legal document.
sealed class LegalBlock {
  const LegalBlock();
}

/// A section heading, e.g. "1. Information We Collect".
class LegalHeading extends LegalBlock {
  final String text;
  const LegalHeading(this.text);
}

/// A body paragraph.
class LegalParagraph extends LegalBlock {
  final String text;
  const LegalParagraph(this.text);
}

/// A bulleted list. Each entry may use `Label — body` form; the renderer keeps
/// it as one line of text.
class LegalBullets extends LegalBlock {
  final List<String> items;
  const LegalBullets(this.items);
}

/// A complete document: title, "last updated" date and the ordered blocks.
class LegalDocument {
  final String title;
  final String lastUpdated;
  final List<LegalBlock> blocks;
  const LegalDocument({
    required this.title,
    required this.lastUpdated,
    required this.blocks,
  });
}

/// Support contact details (§22) — shared by every legal page and the Help
/// screen so there is exactly one place to change them.
class SupportContact {
  SupportContact._();
  static const String email = 'jothidamatrimonysupport@gmail.com';

  /// National number, as displayed.
  static const String phoneDisplay = '9342573137';

  /// E.164 form used for `tel:` / WhatsApp deep links.
  static const String phoneE164 = '+919342573137';
  static const String website = 'https://jothidamatrimony.in';
}

const String _lastUpdatedEn = '24 July 2026';
const String _lastUpdatedTa = '24 ஜூலை 2026';

// ── Privacy Policy ──────────────────────────────────────────────────────────

LegalDocument privacyPolicyDocument(bool tamil) =>
    tamil ? _privacyPolicyTa : _privacyPolicyEn;

final LegalDocument _privacyPolicyEn = LegalDocument(
  title: 'Privacy Policy',
  lastUpdated: _lastUpdatedEn,
  blocks: [
    LegalParagraph(
        'This Privacy Policy explains how ${AppConstants.appName} ("we", "us", '
        '"our") collects, uses, shares and protects your information when you '
        'use our mobile application and website at ${SupportContact.website} '
        '(together, the "Service"). By creating an account or using the '
        'Service, you agree to the practices described in this policy.'),
    const LegalParagraph(
        'Because this is a matrimonial and astrology service, some of the '
        'information we collect is sensitive personal data. We only collect '
        'what is needed to help you find a suitable match and to provide '
        'horoscope and astrology-related services.'),
    const LegalHeading('1. Information We Collect'),
    const LegalParagraph('Information you provide:'),
    const LegalBullets([
      'Account & identity — name, email address, mobile number, gender, '
          'profile photo, and who the profile is created by/for.',
      'Profile details — date of birth, age, height, weight, marital status, '
          'physical status, mother tongue and your about-me text.',
      'Religious & community — religion, caste, sub-caste, gothram, '
          'kuladeivam.',
      'Education & career — education, occupation, employment type, '
          'company/college name, work location, annual income.',
      'Family details — family information, number of children and living '
          'status (where applicable).',
      'Astrology / horoscope — birth date, birth time and birth place, and '
          'related horoscope details used for porutham (matching) and '
          'astrologer reports.',
      'Identity verification (KYC) — Aadhaar and related verification '
          'details, where you choose to verify your profile.',
      'Communications — chat messages, interests sent/received, appointment '
          'bookings, reviews and support requests.',
    ]),
    const LegalParagraph('Information collected automatically:'),
    const LegalBullets([
      'Location — approximate or precise location (including GPS coordinates) '
          'to show and filter matches by area, where you allow it.',
      'Device & usage data — device model, operating system, app version, IP '
          'address and in-app activity, for security and to improve the '
          'Service.',
      'Push notification token — to send you match, interest and appointment '
          'notifications.',
      'Login provider — if you sign in with Google, we receive your name, '
          'email and profile photo from Google.',
    ]),
    const LegalHeading('2. How We Use Your Information'),
    const LegalBullets([
      'Create and manage your account and matrimonial profile.',
      'Show your profile to other members and suggest compatible matches.',
      'Provide horoscope matching, astrology reports and astrologer '
          'appointments.',
      'Enable communication such as interests and chat between members.',
      'Verify identity, prevent fraud and keep the community safe.',
      'Send service notifications and, with your consent, updates and offers.',
      'Comply with legal obligations and enforce our terms.',
    ]),
    const LegalHeading('3. How We Share Your Information'),
    const LegalParagraph(
        'We do NOT sell your personal data. We share information only as '
        'follows:'),
    const LegalBullets([
      'Other members — your profile details are visible to other registered '
          'members so they can consider you as a match. Your phone number, '
          'salary, horoscope details and profile photo are HIDDEN by default '
          'and are only shown if you switch them on yourself in Privacy '
          'Settings.',
      'Astrologers — relevant horoscope and profile details are shared with '
          'the astrologer handling your appointment or report.',
      'Service providers — trusted third parties who help us operate the '
          'Service, including Google Firebase (authentication, database, '
          'storage, notifications) and Google Play billing.',
      'Legal reasons — when required by law, court order, or to protect the '
          'rights and safety of users and the public.',
    ]),
    const LegalHeading('4. Data Retention'),
    const LegalParagraph(
        'We keep your information for as long as your account is active or as '
        'needed to provide the Service. If you delete your account, we delete '
        'or anonymise your personal data within a reasonable period, except '
        'where we must retain it to meet legal, tax, security or '
        'fraud-prevention requirements.'),
    const LegalHeading('5. Your Rights and Choices'),
    const LegalBullets([
      'Access, review and update every field of your profile at any time in '
          'the app.',
      'Control what other members can see through Privacy Settings.',
      'Manage location and notification permissions from your device '
          'settings.',
      'Delete your account and personal data from Settings → Delete Account.',
      'Withdraw consent for marketing communications.',
    ]),
    const LegalHeading('6. Security'),
    const LegalParagraph(
        'We use industry-standard measures such as encrypted connections and '
        'access controls to protect your information. However, no method of '
        'transmission or storage is completely secure, and we cannot guarantee '
        'absolute security.'),
    const LegalHeading("7. Children's Privacy"),
    LegalParagraph(
        '${AppConstants.appName} is intended only for individuals of legal '
        'marriageable age in India and is NOT for anyone under 18. We do not '
        'knowingly collect data from minors. If we learn that a minor has '
        'registered, we will remove the account. See our Child Safety page for '
        'details.'),
    const LegalHeading('8. Third-Party Services'),
    const LegalParagraph(
        'The Service uses Google services (including Firebase and Google '
        'Sign-In) and Google Play billing. Your use of those services is also '
        'governed by their own privacy policies.'),
    const LegalHeading('9. Changes to This Policy'),
    const LegalParagraph(
        'We may update this Privacy Policy from time to time. We will publish '
        'the updated version here with a new "Last updated" date. Continued '
        'use of the Service after changes means you accept the updated '
        'policy.'),
    const LegalHeading('10. Contact Us'),
    LegalParagraph(
        'If you have questions about this Privacy Policy or wish to delete '
        'your data, contact us at ${SupportContact.email} or '
        '${SupportContact.phoneDisplay}.'),
  ],
);

final LegalDocument _privacyPolicyTa = LegalDocument(
  title: 'தனியுரிமைக் கொள்கை',
  lastUpdated: _lastUpdatedTa,
  blocks: [
    LegalParagraph(
        'எங்கள் செயலியையும் ${SupportContact.website} இணையதளத்தையும் (இணைந்து '
        '"சேவை") நீங்கள் பயன்படுத்தும்போது ஜோதிட மேட்ரிமோனி உங்கள் தகவலை எவ்வாறு '
        'சேகரிக்கிறது, பயன்படுத்துகிறது, பகிர்கிறது மற்றும் பாதுகாக்கிறது என்பதை '
        'இந்தக் கொள்கை விளக்குகிறது. கணக்கை உருவாக்குவதன் மூலம் அல்லது சேவையைப் '
        'பயன்படுத்துவதன் மூலம், இங்கு விவரிக்கப்பட்ட நடைமுறைகளை நீங்கள் '
        'ஏற்றுக்கொள்கிறீர்கள்.'),
    const LegalParagraph(
        'இது திருமணம் மற்றும் ஜோதிட சேவை என்பதால், நாங்கள் சேகரிக்கும் சில '
        'தகவல்கள் முக்கியமான தனிப்பட்ட தரவுகளாகும். பொருத்தமான வரனைக் கண்டறியவும் '
        'ஜாதகம் தொடர்பான சேவைகளை வழங்கவும் தேவையானதை மட்டுமே நாங்கள் '
        'சேகரிக்கிறோம்.'),
    const LegalHeading('1. நாங்கள் சேகரிக்கும் தகவல்'),
    const LegalParagraph('நீங்கள் வழங்கும் தகவல்:'),
    const LegalBullets([
      'கணக்கு மற்றும் அடையாளம் — பெயர், மின்னஞ்சல், கைபேசி எண், பாலினம், '
          'சுயவிவரப் புகைப்படம், சுயவிவரம் யாருக்காக உருவாக்கப்பட்டது.',
      'சுயவிவர விவரங்கள் — பிறந்த தேதி, வயது, உயரம், எடை, திருமண நிலை, உடல் '
          'நிலை, தாய்மொழி மற்றும் உங்களைப் பற்றிய குறிப்பு.',
      'மத மற்றும் சமூகம் — மதம், சாதி, உட்பிரிவு, கோத்திரம், குலதெய்வம்.',
      'கல்வி மற்றும் பணி — கல்வி, தொழில், பணி வகை, நிறுவனம்/கல்லூரி பெயர், '
          'பணியிடம், ஆண்டு வருமானம்.',
      'குடும்ப விவரங்கள் — குடும்பத் தகவல், குழந்தைகளின் எண்ணிக்கை மற்றும் '
          'அவர்களின் நிலை (பொருந்தும் இடத்தில்).',
      'ஜாதகம் — பிறந்த தேதி, நேரம், இடம் மற்றும் பொருத்தம் பார்க்கவும் '
          'அறிக்கைகளுக்கும் பயன்படும் ஜாதக விவரங்கள்.',
      'அடையாள சரிபார்ப்பு — நீங்கள் விரும்பினால் ஆதார் மற்றும் அது தொடர்பான '
          'சரிபார்ப்பு விவரங்கள்.',
      'தொடர்புகள் — அரட்டைச் செய்திகள், அனுப்பிய/பெற்ற விருப்பங்கள், சந்திப்பு '
          'முன்பதிவுகள், மதிப்புரைகள் மற்றும் உதவிக் கோரிக்கைகள்.',
    ]),
    const LegalParagraph('தானாகச் சேகரிக்கப்படும் தகவல்:'),
    const LegalBullets([
      'இருப்பிடம் — நீங்கள் அனுமதித்தால், பகுதி வாரியாகப் பொருத்தங்களைக் '
          'காட்டவும் வடிகட்டவும் தோராயமான அல்லது துல்லியமான இருப்பிடம்.',
      'சாதனம் மற்றும் பயன்பாட்டுத் தரவு — சாதன மாதிரி, இயங்குதளம், செயலி பதிப்பு, '
          'IP முகவரி மற்றும் செயலி செயல்பாடு — பாதுகாப்புக்கும் சேவையை '
          'மேம்படுத்தவும்.',
      'அறிவிப்புத் தொகுப்பு (token) — பொருத்தம், விருப்பம் மற்றும் சந்திப்பு '
          'அறிவிப்புகளை அனுப்ப.',
      'உள்நுழைவு வழங்குநர் — Google மூலம் உள்நுழைந்தால், உங்கள் பெயர், மின்னஞ்சல் '
          'மற்றும் புகைப்படத்தை Google இடமிருந்து பெறுகிறோம்.',
    ]),
    const LegalHeading('2. தகவலை நாங்கள் எவ்வாறு பயன்படுத்துகிறோம்'),
    const LegalBullets([
      'உங்கள் கணக்கையும் திருமணச் சுயவிவரத்தையும் உருவாக்கி நிர்வகிக்க.',
      'உங்கள் சுயவிவரத்தை மற்ற உறுப்பினர்களுக்குக் காட்டவும் பொருத்தமான '
          'வரன்களைப் பரிந்துரைக்கவும்.',
      'ஜாதகப் பொருத்தம், ஜோதிட அறிக்கைகள் மற்றும் சந்திப்புகளை வழங்க.',
      'உறுப்பினர்களிடையே விருப்பம் மற்றும் அரட்டை போன்ற தொடர்பை '
          'ஏற்படுத்த.',
      'அடையாளத்தைச் சரிபார்க்க, மோசடியைத் தடுக்க, சமூகத்தைப் பாதுகாப்பாக '
          'வைக்க.',
      'சேவை அறிவிப்புகளையும், உங்கள் ஒப்புதலுடன், புதுப்பிப்புகளையும் அனுப்ப.',
      'சட்டக் கடமைகளைப் பின்பற்றவும் எங்கள் விதிமுறைகளை அமல்படுத்தவும்.',
    ]),
    const LegalHeading('3. தகவலை நாங்கள் எவ்வாறு பகிர்கிறோம்'),
    const LegalParagraph(
        'உங்கள் தனிப்பட்ட தரவை நாங்கள் விற்பதில்லை. கீழ்க்கண்டவாறு மட்டுமே '
        'பகிர்கிறோம்:'),
    const LegalBullets([
      'மற்ற உறுப்பினர்கள் — உங்கள் சுயவிவர விவரங்கள் பதிவுசெய்த உறுப்பினர்களுக்குத் '
          'தெரியும். உங்கள் கைபேசி எண், சம்பளம், ஜாதக விவரங்கள் மற்றும் '
          'சுயவிவரப் புகைப்படம் இயல்பாகவே மறைக்கப்பட்டுள்ளன; தனியுரிமை '
          'அமைப்புகளில் நீங்களே இயக்கினால் மட்டுமே காட்டப்படும்.',
      'ஜோதிடர்கள் — உங்கள் சந்திப்பு அல்லது அறிக்கையைக் கையாளும் ஜோதிடருடன் '
          'தேவையான ஜாதக மற்றும் சுயவிவர விவரங்கள் பகிரப்படும்.',
      'சேவை வழங்குநர்கள் — Google Firebase (அங்கீகாரம், தரவுத்தளம், சேமிப்பு, '
          'அறிவிப்புகள்) மற்றும் Google Play பில்லிங் உள்ளிட்ட நம்பகமான மூன்றாம் '
          'தரப்பினர்.',
      'சட்டக் காரணங்கள் — சட்டம், நீதிமன்ற உத்தரவு அல்லது பயனர்களின் '
          'பாதுகாப்புக்குத் தேவைப்படும்போது.',
    ]),
    const LegalHeading('4. தரவு வைத்திருத்தல்'),
    const LegalParagraph(
        'உங்கள் கணக்கு செயலில் இருக்கும் வரை அல்லது சேவையை வழங்கத் தேவைப்படும் '
        'வரை உங்கள் தகவலை வைத்திருப்போம். கணக்கை நீக்கினால், சட்ட, வரி, பாதுகாப்பு '
        'அல்லது மோசடி தடுப்புத் தேவைகளைத் தவிர, நியாயமான காலத்திற்குள் உங்கள் '
        'தனிப்பட்ட தரவை நீக்குவோம் அல்லது அடையாளமற்றதாக்குவோம்.'),
    const LegalHeading('5. உங்கள் உரிமைகளும் தேர்வுகளும்'),
    const LegalBullets([
      'உங்கள் சுயவிவரத்தின் ஒவ்வொரு புலத்தையும் எப்போது வேண்டுமானாலும் செயலியில் '
          'பார்க்கவும் திருத்தவும் முடியும்.',
      'மற்ற உறுப்பினர்கள் என்ன பார்க்கலாம் என்பதைத் தனியுரிமை அமைப்புகளில் '
          'கட்டுப்படுத்தலாம்.',
      'இருப்பிடம் மற்றும் அறிவிப்பு அனுமதிகளை உங்கள் சாதன அமைப்புகளில் '
          'நிர்வகிக்கலாம்.',
      'அமைப்புகள் → கணக்கை நீக்கு என்பதிலிருந்து உங்கள் கணக்கையும் தரவையும் '
          'நீக்கலாம்.',
      'விளம்பரத் தொடர்புகளுக்கான ஒப்புதலைத் திரும்பப் பெறலாம்.',
    ]),
    const LegalHeading('6. பாதுகாப்பு'),
    const LegalParagraph(
        'மறையாக்கப்பட்ட இணைப்புகள் மற்றும் அணுகல் கட்டுப்பாடுகள் போன்ற தொழில்துறைத் '
        'தரநிலை நடவடிக்கைகளைப் பயன்படுத்துகிறோம். எனினும், எந்த முறையும் '
        'முழுமையாகப் பாதுகாப்பானது அல்ல; முழுமையான பாதுகாப்பை உறுதியளிக்க '
        'முடியாது.'),
    const LegalHeading('7. குழந்தைகளின் தனியுரிமை'),
    const LegalParagraph(
        'இந்தச் சேவை இந்தியாவில் சட்டப்படி திருமண வயதை அடைந்தவர்களுக்கு மட்டுமே; '
        '18 வயதுக்குக் குறைவானவர்களுக்கு அல்ல. சிறார்களிடமிருந்து அறிந்தே தரவைச் '
        'சேகரிப்பதில்லை. சிறார் பதிவு செய்திருப்பது தெரிய வந்தால் அந்தக் கணக்கை '
        'நீக்குவோம். மேலும் விவரங்களுக்கு குழந்தைப் பாதுகாப்புப் பக்கத்தைப் '
        'பார்க்கவும்.'),
    const LegalHeading('8. மூன்றாம் தரப்பு சேவைகள்'),
    const LegalParagraph(
        'இந்தச் சேவை Google சேவைகளையும் (Firebase, Google Sign-In) Google Play '
        'பில்லிங்கையும் பயன்படுத்துகிறது. அவற்றின் பயன்பாடு அவற்றின் சொந்தத் '
        'தனியுரிமைக் கொள்கைகளுக்கும் உட்பட்டது.'),
    const LegalHeading('9. இந்தக் கொள்கையின் மாற்றங்கள்'),
    const LegalParagraph(
        'இந்தக் கொள்கையை அவ்வப்போது புதுப்பிக்கலாம். புதுப்பிக்கப்பட்ட பதிப்பு '
        'புதிய தேதியுடன் இங்கே வெளியிடப்படும். மாற்றங்களுக்குப் பிறகு சேவையைத் '
        'தொடர்ந்து பயன்படுத்துவது புதுப்பிக்கப்பட்ட கொள்கையை ஏற்பதாகும்.'),
    const LegalHeading('10. எங்களைத் தொடர்பு கொள்ள'),
    LegalParagraph(
        'இந்தக் கொள்கை குறித்து கேள்விகள் இருந்தாலோ, உங்கள் தரவை நீக்க '
        'விரும்பினாலோ ${SupportContact.email} அல்லது '
        '${SupportContact.phoneDisplay} ஐத் தொடர்பு கொள்ளுங்கள்.'),
  ],
);

// ── Terms & Conditions ──────────────────────────────────────────────────────

LegalDocument termsDocument(bool tamil) => tamil ? _termsTa : _termsEn;

final LegalDocument _termsEn = LegalDocument(
  title: 'Terms & Conditions',
  lastUpdated: _lastUpdatedEn,
  blocks: [
    LegalParagraph(
        'These Terms & Conditions govern your use of ${AppConstants.appName} '
        '(the "Service"). By creating an account you accept these terms in '
        'full. If you do not agree, please do not use the Service.'),
    const LegalHeading('1. Eligibility'),
    const LegalParagraph(
        'You must be at least 18 years old and of legal marriageable age under '
        'the laws applicable to you. Profiles may be created only for genuine '
        'matrimonial purposes, by the individual concerned or by an immediate '
        'family member with their consent.'),
    const LegalHeading('2. Your Account'),
    const LegalBullets([
      'You are responsible for the accuracy of every detail you enter, '
          'including your name, date of birth, education, career and horoscope '
          'details.',
      'One person may hold only one matrimonial profile.',
      'Keep your sign-in credentials secure. You are responsible for activity '
          'that takes place under your account.',
      'Providing false, misleading or impersonating information may result in '
          'suspension or permanent removal without notice.',
    ]),
    const LegalHeading('3. Acceptable Use'),
    const LegalParagraph('You agree NOT to:'),
    const LegalBullets([
      'Harass, abuse, threaten or defame any member.',
      'Post obscene, offensive, hateful or unlawful content.',
      'Solicit money, gifts, investments or donations from members.',
      'Misuse contact details, photographs or horoscope documents shared with '
          'you.',
      'Use the Service for commercial advertising, spam or data scraping.',
      'Create profiles for anyone under 18 or without their consent.',
    ]),
    const LegalParagraph(
        'Violations may lead to immediate profile removal and, where '
        'appropriate, reporting to law-enforcement authorities.'),
    const LegalHeading('4. Profile Visibility and Privacy'),
    const LegalParagraph(
        'Your profile is shown to other registered members as part of the '
        'matchmaking service. Your phone number, salary, horoscope details and '
        'profile photo are hidden by default and stay hidden until you change '
        'that yourself in Privacy Settings — accepting an interest does not '
        'reveal them.'),
    const LegalHeading('5. Payments'),
    const LegalParagraph(
        'Matrimony features — creating a profile, browsing matches, sending '
        'interests, chatting with accepted matches and booking an astrologer '
        'appointment — are FREE. Where an optional paid item exists (such as a '
        'detailed horoscope report), the price is shown before purchase and '
        'billing is handled by Google Play. Fees are non-refundable except '
        'where required by law or by Google Play policy.'),
    const LegalHeading('6. Astrology Services'),
    const LegalParagraph(
        'Horoscope and porutham analysis is provided for informational and '
        'cultural purposes. It does not constitute professional, medical, '
        'legal or financial advice, and no particular outcome is guaranteed.'),
    const LegalHeading('7. No Guarantee of a Match'),
    const LegalParagraph(
        'We provide a platform for members to find each other. We do not '
        'guarantee that you will receive interests, responses or a marriage '
        'proposal, and we do not independently verify every detail a member '
        'enters. Please verify details independently before proceeding with '
        'any alliance.'),
    const LegalHeading('8. Limitation of Liability'),
    const LegalParagraph(
        'To the maximum extent permitted by law, we are not liable for '
        'interactions between members or for any loss arising from use of the '
        'Service, including decisions taken on the basis of information '
        'published by another member.'),
    const LegalHeading('9. Suspension and Termination'),
    const LegalParagraph(
        'We may suspend or terminate an account that breaches these terms, is '
        'reported repeatedly, or is used fraudulently. You may delete your own '
        'account at any time from Settings → Delete Account.'),
    const LegalHeading('10. Changes to These Terms'),
    const LegalParagraph(
        'We may update these terms from time to time. Continued use of the app '
        'after an update constitutes acceptance of the revised terms.'),
    const LegalHeading('11. Contact'),
    LegalParagraph(
        'Questions about these terms? Email ${SupportContact.email} or call '
        '${SupportContact.phoneDisplay}.'),
  ],
);

final LegalDocument _termsTa = LegalDocument(
  title: 'விதிமுறைகள் மற்றும் நிபந்தனைகள்',
  lastUpdated: _lastUpdatedTa,
  blocks: [
    const LegalParagraph(
        'ஜோதிட மேட்ரிமோனி ("சேவை") பயன்பாட்டை இந்த விதிமுறைகள் நிர்வகிக்கின்றன. '
        'கணக்கை உருவாக்குவதன் மூலம் இந்த விதிமுறைகளை முழுமையாக ஏற்கிறீர்கள். '
        'ஒப்புக்கொள்ளவில்லை என்றால் சேவையைப் பயன்படுத்த வேண்டாம்.'),
    const LegalHeading('1. தகுதி'),
    const LegalParagraph(
        'உங்களுக்கு குறைந்தது 18 வயது நிரம்பியிருக்க வேண்டும், மேலும் உங்களுக்குப் '
        'பொருந்தும் சட்டப்படி திருமண வயதை அடைந்திருக்க வேண்டும். உண்மையான திருமண '
        'நோக்கத்திற்காக மட்டுமே சுயவிவரங்களை உருவாக்க வேண்டும் — சம்பந்தப்பட்ட '
        'நபரால் அல்லது அவரது ஒப்புதலுடன் நெருங்கிய குடும்ப உறுப்பினரால்.'),
    const LegalHeading('2. உங்கள் கணக்கு'),
    const LegalBullets([
      'பெயர், பிறந்த தேதி, கல்வி, பணி, ஜாதக விவரங்கள் உட்பட நீங்கள் உள்ளிடும் '
          'ஒவ்வொரு விவரத்தின் துல்லியத்திற்கும் நீங்களே பொறுப்பு.',
      'ஒருவருக்கு ஒரு திருமணச் சுயவிவரம் மட்டுமே.',
      'உங்கள் உள்நுழைவுத் தகவலைப் பாதுகாப்பாக வைத்திருங்கள். உங்கள் கணக்கின் கீழ் '
          'நடக்கும் செயல்களுக்கு நீங்களே பொறுப்பு.',
      'தவறான, தவறாக வழிநடத்தும் அல்லது வேறொருவராகக் காட்டும் தகவல் அளித்தால், '
          'அறிவிப்பின்றி கணக்கு இடைநிறுத்தப்படலாம் அல்லது நிரந்தரமாக '
          'நீக்கப்படலாம்.',
    ]),
    const LegalHeading('3. ஏற்கத்தக்க பயன்பாடு'),
    const LegalParagraph('நீங்கள் கீழ்க்கண்டவற்றைச் செய்யக்கூடாது:'),
    const LegalBullets([
      'எந்த உறுப்பினரையும் துன்புறுத்துவது, மிரட்டுவது அல்லது அவதூறு செய்வது.',
      'ஆபாசமான, புண்படுத்தும், வெறுப்பூட்டும் அல்லது சட்டவிரோதமான உள்ளடக்கத்தை '
          'இடுவது.',
      'உறுப்பினர்களிடம் பணம், பரிசு, முதலீடு அல்லது நன்கொடை கேட்பது.',
      'உங்களுடன் பகிரப்பட்ட தொடர்பு விவரங்கள், புகைப்படங்கள் அல்லது ஜாதக '
          'ஆவணங்களைத் தவறாகப் பயன்படுத்துவது.',
      'வணிக விளம்பரம், ஸ்பேம் அல்லது தரவுத் திருட்டுக்குச் சேவையைப் '
          'பயன்படுத்துவது.',
      '18 வயதுக்குக் குறைவானவர்களுக்கோ, ஒப்புதல் இல்லாமலோ சுயவிவரம் '
          'உருவாக்குவது.',
    ]),
    const LegalParagraph(
        'மீறல்கள் உடனடி சுயவிவர நீக்கத்திற்கும், தேவைப்படும் இடத்தில் சட்ட '
        'அமலாக்க அதிகாரிகளுக்குத் தெரிவிப்பதற்கும் வழிவகுக்கும்.'),
    const LegalHeading('4. சுயவிவரத் தெரிவும் தனியுரிமையும்'),
    const LegalParagraph(
        'வரன் தேடும் சேவையின் ஒரு பகுதியாக உங்கள் சுயவிவரம் மற்ற பதிவுசெய்த '
        'உறுப்பினர்களுக்குக் காட்டப்படும். உங்கள் கைபேசி எண், சம்பளம், ஜாதக '
        'விவரங்கள் மற்றும் சுயவிவரப் புகைப்படம் இயல்பாகவே மறைக்கப்பட்டுள்ளன; '
        'தனியுரிமை அமைப்புகளில் நீங்களே மாற்றும் வரை மறைந்தே இருக்கும் — விருப்பம் '
        'ஏற்கப்படுவது அவற்றை வெளிப்படுத்தாது.'),
    const LegalHeading('5. கட்டணங்கள்'),
    const LegalParagraph(
        'சுயவிவரம் உருவாக்குதல், வரன்களைப் பார்த்தல், விருப்பம் அனுப்புதல், '
        'ஏற்கப்பட்ட வரன்களுடன் அரட்டை மற்றும் ஜோதிடர் சந்திப்பு முன்பதிவு ஆகியவை '
        'இலவசம். விருப்பத் தேர்வான கட்டணப் பொருள் (விரிவான ஜாதக அறிக்கை போன்றவை) '
        'இருந்தால், விலை வாங்குவதற்கு முன் காட்டப்படும்; பணம் Google Play மூலம் '
        'கையாளப்படும். சட்டப்படி அல்லது Google Play கொள்கைப்படி தேவைப்படும் '
        'இடங்களைத் தவிர கட்டணங்கள் திரும்பப் பெறப்படாது.'),
    const LegalHeading('6. ஜோதிட சேவைகள்'),
    const LegalParagraph(
        'ஜாதகம் மற்றும் பொருத்தப் பகுப்பாய்வு தகவல் மற்றும் பண்பாட்டு '
        'நோக்கத்திற்காக மட்டுமே வழங்கப்படுகிறது. இது தொழில்முறை, மருத்துவ, சட்ட '
        'அல்லது நிதி ஆலோசனை அல்ல; எந்த முடிவும் உறுதியளிக்கப்படவில்லை.'),
    const LegalHeading('7. பொருத்தம் குறித்த உத்தரவாதம் இல்லை'),
    const LegalParagraph(
        'உறுப்பினர்கள் ஒருவரையொருவர் கண்டறியும் தளத்தை மட்டுமே நாங்கள் '
        'வழங்குகிறோம். விருப்பங்கள், பதில்கள் அல்லது திருமண வரன் கிடைக்கும் என '
        'உறுதியளிக்கவில்லை; ஒவ்வொரு உறுப்பினரும் உள்ளிடும் விவரங்களைத் தனியாக '
        'சரிபார்ப்பதில்லை. எந்த சம்பந்தத்திற்கும் முன் விவரங்களைத் தாங்களே '
        'சரிபார்க்கவும்.'),
    const LegalHeading('8. பொறுப்பு வரம்பு'),
    const LegalParagraph(
        'சட்டம் அனுமதிக்கும் அளவிற்கு, உறுப்பினர்களுக்கிடையிலான தொடர்புகளுக்கும், '
        'சேவையின் பயன்பாட்டால் ஏற்படும் இழப்புகளுக்கும் நாங்கள் பொறுப்பல்ல.'),
    const LegalHeading('9. இடைநிறுத்தமும் நீக்கமும்'),
    const LegalParagraph(
        'இந்த விதிமுறைகளை மீறும், தொடர்ந்து புகாரளிக்கப்படும் அல்லது மோசடியாகப் '
        'பயன்படுத்தப்படும் கணக்கை இடைநிறுத்தலாம் அல்லது நீக்கலாம். அமைப்புகள் → '
        'கணக்கை நீக்கு என்பதிலிருந்து எப்போது வேண்டுமானாலும் உங்கள் கணக்கை நீங்களே '
        'நீக்கலாம்.'),
    const LegalHeading('10. விதிமுறை மாற்றங்கள்'),
    const LegalParagraph(
        'இந்த விதிமுறைகளை அவ்வப்போது புதுப்பிக்கலாம். புதுப்பிப்புக்குப் பிறகு '
        'செயலியைத் தொடர்ந்து பயன்படுத்துவது திருத்தப்பட்ட விதிமுறைகளை '
        'ஏற்பதாகும்.'),
    const LegalHeading('11. தொடர்பு'),
    LegalParagraph(
        'விதிமுறைகள் குறித்து கேள்விகளா? ${SupportContact.email} க்கு மின்னஞ்சல் '
        'அனுப்பவும் அல்லது ${SupportContact.phoneDisplay} ஐ அழைக்கவும்.'),
  ],
);

// ── Child Safety ────────────────────────────────────────────────────────────

LegalDocument childSafetyDocument(bool tamil) =>
    tamil ? _childSafetyTa : _childSafetyEn;

final LegalDocument _childSafetyEn = LegalDocument(
  title: 'Child Safety',
  lastUpdated: _lastUpdatedEn,
  blocks: [
    LegalParagraph(
        '${AppConstants.appName} has ZERO TOLERANCE for child sexual abuse and '
        'exploitation (CSAE). This page sets out our Child Safety Standards '
        'and how we enforce them.'),
    const LegalHeading('1. Adults Only'),
    const LegalParagraph(
        'The Service is strictly for adults of legal marriageable age in '
        'India. Nobody under 18 may register, and no profile may be created '
        'for a person under 18 — including by a parent or relative. Every '
        'profile must carry a date of birth, and the app refuses a date of '
        'birth that makes the member younger than 18.'),
    const LegalHeading('2. Prohibited Content and Conduct'),
    const LegalParagraph('The following are strictly prohibited:'),
    const LegalBullets([
      'Any child sexual abuse material (CSAM) or content that sexualises a '
          'minor.',
      'Grooming, solicitation or any attempt to contact a minor for a sexual '
          'or matrimonial purpose.',
      'Uploading photographs of children as a profile photo.',
      'Sharing a minor\'s personal information, photographs or contact '
          'details.',
      'Creating a profile on behalf of a minor, or misrepresenting a minor\'s '
          'age.',
    ]),
    const LegalHeading('3. Reporting'),
    LegalParagraph(
        'Every profile and every chat has a Report action. If you believe a '
        'member is a minor, or you encounter CSAE material or behaviour, '
        'report it immediately from the app — or email us at '
        '${SupportContact.email} with the profile name and any evidence. '
        'Reports can also be made by phone on ${SupportContact.phoneDisplay}.'),
    const LegalHeading('4. Our Response'),
    const LegalBullets([
      'Reports concerning a suspected minor or CSAE are prioritised and '
          'reviewed by our moderation team.',
      'Accounts found to involve a minor are removed immediately and '
          'permanently, and the associated data is deleted.',
      'CSAE material is removed and preserved only as required for reporting '
          'to the authorities.',
      'We report confirmed CSAE to the relevant law-enforcement agencies in '
          'India, including the National Cyber Crime Reporting Portal '
          '(cybercrime.gov.in) and the local police, and cooperate fully with '
          'their investigations.',
      'Offending accounts are banned from the platform.',
    ]),
    const LegalHeading('5. Preventive Measures'),
    const LegalBullets([
      'Date of birth is mandatory at profile creation and under-18 dates are '
          'rejected.',
      'Optional Aadhaar-based identity verification is offered so members can '
          'confirm they are adults.',
      'Chat is available only between members who have mutually accepted an '
          'interest.',
      'Phone number, salary, horoscope details and profile photo are hidden by '
          'default.',
      'Moderators review reported profiles and reported chats.',
    ]),
    const LegalHeading('6. Child Safety Point of Contact'),
    LegalParagraph(
        'Child-safety concerns are handled by our designated child-safety '
        'contact and are answered as a priority: ${SupportContact.email} · '
        '${SupportContact.phoneDisplay}.'),
    const LegalHeading('7. Emergency'),
    const LegalParagraph(
        'If a child is in immediate danger, contact the police on 100, the '
        'national child helpline CHILDLINE on 1098, or the Cyber Crime '
        'Helpline on 1930 before contacting us.'),
  ],
);

final LegalDocument _childSafetyTa = LegalDocument(
  title: 'குழந்தைப் பாதுகாப்பு',
  lastUpdated: _lastUpdatedTa,
  blocks: [
    const LegalParagraph(
        'குழந்தைகளுக்கு எதிரான பாலியல் துஷ்பிரயோகம் மற்றும் சுரண்டல் (CSAE) '
        'விஷயத்தில் ஜோதிட மேட்ரிமோனிக்கு எந்தச் சகிப்புத்தன்மையும் இல்லை. '
        'எங்கள் குழந்தைப் பாதுகாப்புத் தரநிலைகளையும் அவற்றை எப்படி '
        'அமல்படுத்துகிறோம் என்பதையும் இந்தப் பக்கம் விளக்குகிறது.'),
    const LegalHeading('1. பெரியவர்களுக்கு மட்டும்'),
    const LegalParagraph(
        'இந்தச் சேவை இந்தியாவில் சட்டப்படி திருமண வயதை அடைந்த பெரியவர்களுக்கு '
        'மட்டுமே. 18 வயதுக்குக் குறைவானவர்கள் பதிவு செய்யக்கூடாது; பெற்றோர் '
        'அல்லது உறவினர் உட்பட யாரும் 18 வயதுக்குக் குறைவானவருக்குச் சுயவிவரம் '
        'உருவாக்கக்கூடாது. ஒவ்வொரு சுயவிவரத்திலும் பிறந்த தேதி கட்டாயம்; 18 '
        'வயதுக்குக் குறைவான தேதியை செயலி ஏற்காது.'),
    const LegalHeading('2. தடைசெய்யப்பட்ட உள்ளடக்கமும் நடத்தையும்'),
    const LegalParagraph('கீழ்க்கண்டவை கண்டிப்பாகத் தடைசெய்யப்பட்டவை:'),
    const LegalBullets([
      'குழந்தைகள் சார்ந்த பாலியல் துஷ்பிரயோகப் பொருள் (CSAM) அல்லது சிறாரைப் '
          'பாலியல்படுத்தும் எந்த உள்ளடக்கமும்.',
      'சிறாரை பாலியல் அல்லது திருமண நோக்கத்திற்காகத் தொடர்பு கொள்ள முயற்சிப்பது.',
      'குழந்தைகளின் புகைப்படங்களைச் சுயவிவரப் படமாகப் பதிவேற்றுவது.',
      'சிறாரின் தனிப்பட்ட தகவல், புகைப்படம் அல்லது தொடர்பு விவரங்களைப் '
          'பகிர்வது.',
      'சிறாருக்காகச் சுயவிவரம் உருவாக்குவது அல்லது வயதைத் தவறாகக் காட்டுவது.',
    ]),
    const LegalHeading('3. புகாரளித்தல்'),
    LegalParagraph(
        'ஒவ்வொரு சுயவிவரத்திலும் ஒவ்வொரு அரட்டையிலும் "புகாரளி" விருப்பம் உள்ளது. '
        'ஒரு உறுப்பினர் சிறார் என நீங்கள் சந்தேகித்தால், அல்லது CSAE உள்ளடக்கம் '
        'அல்லது நடத்தையைக் கண்டால், உடனடியாகச் செயலியிலிருந்து புகாரளிக்கவும் — '
        'அல்லது சுயவிவரப் பெயர் மற்றும் ஆதாரங்களுடன் ${SupportContact.email} '
        'க்கு மின்னஞ்சல் அனுப்பவும். ${SupportContact.phoneDisplay} எண்ணிலும் '
        'புகாரளிக்கலாம்.'),
    const LegalHeading('4. எங்கள் நடவடிக்கை'),
    const LegalBullets([
      'சிறார் தொடர்பான அல்லது CSAE புகார்கள் முன்னுரிமையுடன் மதிப்பாய்வு '
          'செய்யப்படும்.',
      'சிறார் தொடர்புடையது என உறுதியானால், அந்தக் கணக்கு உடனடியாக நிரந்தரமாக '
          'நீக்கப்படும்; தொடர்புடைய தரவும் அழிக்கப்படும்.',
      'CSAE பொருள் நீக்கப்படும்; அதிகாரிகளுக்குத் தெரிவிக்கத் தேவைப்படும் '
          'அளவுக்கு மட்டுமே பாதுகாக்கப்படும்.',
      'உறுதிப்படுத்தப்பட்ட CSAE இந்தியாவின் சட்ட அமலாக்க அமைப்புகளுக்கு — '
          'தேசிய சைபர் கிரைம் புகார் தளம் (cybercrime.gov.in) மற்றும் உள்ளூர் '
          'காவல்துறை உட்பட — தெரிவிக்கப்படும்; விசாரணைகளுக்கு முழுமையாக '
          'ஒத்துழைப்போம்.',
      'குற்றமிழைத்த கணக்குகள் தளத்திலிருந்து நிரந்தரமாகத் தடைசெய்யப்படும்.',
    ]),
    const LegalHeading('5. தடுப்பு நடவடிக்கைகள்'),
    const LegalBullets([
      'சுயவிவரம் உருவாக்கும்போது பிறந்த தேதி கட்டாயம்; 18 வயதுக்குக் குறைவான '
          'தேதிகள் நிராகரிக்கப்படும்.',
      'பெரியவர் என உறுதிப்படுத்த விருப்பத் தேர்வான ஆதார் சரிபார்ப்பு '
          'வழங்கப்படுகிறது.',
      'இருதரப்பும் விருப்பத்தை ஏற்ற உறுப்பினர்களிடையே மட்டுமே அரட்டை.',
      'கைபேசி எண், சம்பளம், ஜாதக விவரங்கள் மற்றும் சுயவிவரப் புகைப்படம் '
          'இயல்பாகவே மறைக்கப்பட்டுள்ளன.',
      'புகாரளிக்கப்பட்ட சுயவிவரங்களையும் அரட்டைகளையும் மதிப்பாய்வுக் குழு '
          'பரிசீலிக்கும்.',
    ]),
    const LegalHeading('6. குழந்தைப் பாதுகாப்புத் தொடர்பு'),
    LegalParagraph(
        'குழந்தைப் பாதுகாப்பு தொடர்பான கவலைகள் முன்னுரிமையுடன் கையாளப்படும்: '
        '${SupportContact.email} · ${SupportContact.phoneDisplay}.'),
    const LegalHeading('7. அவசர நிலை'),
    const LegalParagraph(
        'ஒரு குழந்தை உடனடி ஆபத்தில் இருந்தால், எங்களைத் தொடர்பு கொள்வதற்கு முன் '
        'காவல்துறை 100, குழந்தைகள் உதவி எண் 1098, அல்லது சைபர் கிரைம் உதவி எண் '
        '1930 ஐத் தொடர்பு கொள்ளுங்கள்.'),
  ],
);

// ── Delete Account ──────────────────────────────────────────────────────────

LegalDocument deleteAccountDocument(bool tamil) =>
    tamil ? _deleteAccountTa : _deleteAccountEn;

final LegalDocument _deleteAccountEn = LegalDocument(
  title: 'Delete Account',
  lastUpdated: _lastUpdatedEn,
  blocks: [
    LegalParagraph(
        'You can delete your ${AppConstants.appName} account and its data at '
        'any time. Deletion is immediate and self-service — no admin approval '
        'is needed.'),
    const LegalHeading('1. How to Delete Your Account'),
    const LegalBullets([
      'In the app: open Settings → Delete Account, then confirm.',
      'On the website: sign in and open Settings → Delete Account.',
      'By email: write to us from your registered email address and we will '
          'process the deletion within 7 days.',
    ]),
    const LegalHeading('2. What Is Deleted'),
    const LegalParagraph(
        'Deleting your account permanently removes:'),
    const LegalBullets([
      'Your matrimonial profile and profile photo.',
      'Your contact details and privacy settings.',
      'Interests you sent and received, and your connections.',
      'Your chat threads and messages.',
      'Your horoscope details and uploaded horoscope documents.',
      'Your appointment bookings and report requests.',
      'Your account record and sign-in credentials.',
    ]),
    const LegalHeading('3. What May Be Retained'),
    const LegalParagraph(
        'We may retain a limited amount of data where the law requires it — '
        'for example transaction records for tax and accounting purposes, and '
        'moderation records where an account was removed for abuse or a child '
        'safety violation. Retained data is kept only for as long as the '
        'obligation lasts and is not used to contact you.'),
    const LegalHeading('4. This Cannot Be Undone'),
    const LegalParagraph(
        'Deletion is permanent. Your profile disappears from every other '
        'member\'s matches, interests and chats, and it cannot be restored. If '
        'you want to take a break instead, contact support and we can help you '
        'reduce your visibility rather than delete everything.'),
    const LegalHeading('5. Help'),
    LegalParagraph(
        'Need help deleting your account? Email ${SupportContact.email} or '
        'call ${SupportContact.phoneDisplay}.'),
  ],
);

final LegalDocument _deleteAccountTa = LegalDocument(
  title: 'கணக்கை நீக்கு',
  lastUpdated: _lastUpdatedTa,
  blocks: [
    const LegalParagraph(
        'உங்கள் ஜோதிட மேட்ரிமோனி கணக்கையும் அதன் தரவையும் எப்போது வேண்டுமானாலும் '
        'நீக்கலாம். நீக்கம் உடனடியானது — நிர்வாக ஒப்புதல் தேவையில்லை.'),
    const LegalHeading('1. கணக்கை எப்படி நீக்குவது'),
    const LegalBullets([
      'செயலியில்: அமைப்புகள் → கணக்கை நீக்கு என்பதைத் திறந்து உறுதிப்படுத்தவும்.',
      'இணையதளத்தில்: உள்நுழைந்து அமைப்புகள் → கணக்கை நீக்கு என்பதைத் திறக்கவும்.',
      'மின்னஞ்சல் மூலம்: பதிவுசெய்த மின்னஞ்சல் முகவரியிலிருந்து எங்களுக்கு எழுதுங்கள்; '
          '7 நாட்களுக்குள் நீக்கத்தை முடிப்போம்.',
    ]),
    const LegalHeading('2. என்ன நீக்கப்படும்'),
    const LegalParagraph('கணக்கை நீக்குவது கீழ்க்கண்டவற்றை நிரந்தரமாக அகற்றும்:'),
    const LegalBullets([
      'உங்கள் திருமணச் சுயவிவரமும் சுயவிவரப் புகைப்படமும்.',
      'உங்கள் தொடர்பு விவரங்களும் தனியுரிமை அமைப்புகளும்.',
      'நீங்கள் அனுப்பிய மற்றும் பெற்ற விருப்பங்கள், உங்கள் இணைப்புகள்.',
      'உங்கள் அரட்டை உரையாடல்களும் செய்திகளும்.',
      'உங்கள் ஜாதக விவரங்களும் பதிவேற்றிய ஜாதக ஆவணங்களும்.',
      'உங்கள் சந்திப்பு முன்பதிவுகளும் அறிக்கைக் கோரிக்கைகளும்.',
      'உங்கள் கணக்குப் பதிவும் உள்நுழைவுத் தகவலும்.',
    ]),
    const LegalHeading('3. என்ன வைத்திருக்கப்படலாம்'),
    const LegalParagraph(
        'சட்டம் தேவைப்படுத்தும் இடங்களில் குறைந்த அளவு தரவை வைத்திருக்கலாம் — '
        'எடுத்துக்காட்டாக வரி மற்றும் கணக்கியல் நோக்கத்திற்கான பரிவர்த்தனைப் '
        'பதிவுகள், மற்றும் துஷ்பிரயோகம் அல்லது குழந்தைப் பாதுகாப்பு மீறல் '
        'காரணமாகக் கணக்கு நீக்கப்பட்ட வழக்குகளின் மதிப்பாய்வுப் பதிவுகள். இவை '
        'கடமை நீடிக்கும் வரை மட்டுமே வைக்கப்படும்; உங்களைத் தொடர்பு கொள்ளப் '
        'பயன்படுத்தப்படாது.'),
    const LegalHeading('4. இதை மீட்டெடுக்க முடியாது'),
    const LegalParagraph(
        'நீக்கம் நிரந்தரமானது. உங்கள் சுயவிவரம் மற்ற உறுப்பினர்களின் பொருத்தங்கள், '
        'விருப்பங்கள், அரட்டைகள் அனைத்திலிருந்தும் மறைந்துவிடும்; அதை மீட்க '
        'முடியாது. அனைத்தையும் நீக்குவதற்குப் பதிலாக சிறிது காலம் இடைவெளி '
        'வேண்டுமெனில், ஆதரவுக் குழுவைத் தொடர்பு கொள்ளுங்கள்.'),
    const LegalHeading('5. உதவி'),
    LegalParagraph(
        'கணக்கை நீக்க உதவி வேண்டுமா? ${SupportContact.email} க்கு மின்னஞ்சல் '
        'அனுப்பவும் அல்லது ${SupportContact.phoneDisplay} ஐ அழைக்கவும்.'),
  ],
);
