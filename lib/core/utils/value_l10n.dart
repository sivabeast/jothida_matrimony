import 'package:flutter/widgets.dart';

import '../constants/app_constants.dart';

/// Tamil display text for canonical English DATA values (dropdown options,
/// stored profile values, consultation categories…).
///
/// Storage stays English — only DISPLAY switches with the locale, so nothing
/// in Firestore changes shape and matching/filters keep working. Unknown
/// values fall back to the original string, which makes this safe to apply
/// anywhere a stored value is rendered.
///
/// Usage:
/// ```dart
/// Text(context.localizeValue(profile.gender))   // Male → ஆண் (Tamil mode)
/// ```
const Map<String, String> kTamilValueMap = {
  // ── Gender ──
  'Male': 'ஆண்',
  'Female': 'பெண்',

  // ── Marital status ──
  'Never Married': 'திருமணம் ஆகாதவர்',
  'Unmarried': 'திருமணம் ஆகாதவர்',
  'Divorced': 'விவாகரத்து ஆனவர்',
  'Widowed': 'துணையை இழந்தவர்',
  'Widow': 'விதவை',
  'Widower': 'மனைவியை இழந்தவர்',
  'Awaiting Divorce': 'விவாகரத்துக்காக காத்திருப்பவர்',
  'Separated': 'பிரிந்து வாழ்பவர்',

  // ── Physical status ──
  'Normal': 'சாதாரணம்',
  'Physically Challenged': 'மாற்றுத்திறனாளி',

  // ── Profile for ──
  'Myself': 'எனக்காக',
  'Son': 'மகன்',
  'Daughter': 'மகள்',
  'Brother': 'சகோதரன்',
  'Sister': 'சகோதரி',
  'Relative': 'உறவினர்',

  // ── Family type / status / values ──
  'Joint Family': 'கூட்டுக் குடும்பம்',
  'Nuclear Family': 'தனிக் குடும்பம்',
  'Rich': 'பணக்காரர்',
  'Upper Middle Class': 'மேல் நடுத்தர வர்க்கம்',
  'Middle Class': 'நடுத்தர வர்க்கம்',
  'Lower Middle Class': 'கீழ் நடுத்தர வர்க்கம்',
  'Lower Class': 'கீழ் வர்க்கம்',
  'Orthodox': 'மரபுவழி',
  'Traditional': 'பாரம்பரியம்',
  'Moderate': 'மிதவாதம்',
  'Liberal': 'தாராளவாதம்',

  // ── Eating / smoking / drinking habits ──
  'Vegetarian': 'சைவம்',
  'Non-Vegetarian': 'அசைவம்',
  'Non Vegetarian': 'அசைவம்',
  'Eggetarian': 'முட்டை சைவம்',
  'Vegan': 'வீகன்',
  'Never': 'ஒருபோதும் இல்லை',
  'No': 'இல்லை',
  'Yes': 'ஆம்',
  'Occasionally': 'எப்போதாவது',
  'Regularly': 'வழக்கமாக',
  'Non-Smoker': 'புகைப்பிடிக்காதவர்',
  'Non-Drinker': 'மது அருந்தாதவர்',

  // ── Employment STATUS + SECTOR (§6) ──
  // Occupation TITLES are deliberately absent from this file: "Software
  // Engineer", "Doctor", "Teacher"… must render in English on both platforms
  // (§9). Only the status/sector vocabulary is translated.
  'Employed': 'பணியில் உள்ளார்',
  'Job Seeker': 'வேலை தேடுபவர்',
  'Retired': 'ஓய்வு பெற்றவர்',
  'Homemaker': 'இல்லத்தரசி',
  'Student': 'மாணவர்',
  'Government': 'அரசு',
  'Government Job': 'அரசு வேலை',
  'Private': 'தனியார்',
  'Private Job': 'தனியார் வேலை',
  'Business': 'வணிகம்',
  'Profession': 'தொழில்முறை',
  'Self Employed': 'சுயதொழில்',
  'Self-Employed': 'சுயதொழில்',
  'Not Working': 'வேலை இல்லை',
  'Defence': 'பாதுகாப்புத் துறை',
  'Civil Services': 'குடிமைப் பணிகள்',

  // ── Religion ──
  'Hindu': 'இந்து',
  'Muslim': 'முஸ்லிம்',
  'Christian': 'கிறிஸ்தவர்',
  'Sikh': 'சீக்கியர்',
  'Jain': 'சமணர்',
  'Buddhist': 'பௌத்தர்',
  'Parsi': 'பார்சி',
  'Jewish': 'யூதர்',
  'Inter-Religion': 'மத வேறுபாடு இல்லை',

  // ── Mother tongue / languages ──
  'Tamil': 'தமிழ்',
  'Telugu': 'தெலுங்கு',
  'Malayalam': 'மலையாளம்',
  'Kannada': 'கன்னடம்',
  'Hindi': 'இந்தி',
  'English': 'ஆங்கிலம்',

  // ── Education LEVEL (§5) ──
  // Only the LEVEL is translated. Degree names (B.E, M.Sc, MBBS, CA…) stay in
  // English exactly as the website presents them (§9) — that is why there is
  // no entry for any UG/PG qualification below.
  'Below 10th': '10ஆம் வகுப்புக்குக் கீழ்',
  '10th': '10ஆம் வகுப்பு',
  '10th Standard': '10ஆம் வகுப்பு',
  '12th': '12ஆம் வகுப்பு',
  '12th Standard': '12ஆம் வகுப்பு',
  'Diploma': 'டிப்ளமோ',
  'ITI': 'ஐடிஐ',
  'UG': 'இளங்கலை (UG)',
  'PG': 'முதுகலை (PG)',
  'Doctorate': 'முனைவர் (Doctorate)',
  // Legacy level names still stored on older profiles.
  'Bachelors': 'இளங்கலை பட்டம்',
  "Bachelor's Degree": 'இளங்கலை பட்டம்',
  'Masters': 'முதுகலை பட்டம்',
  "Master's Degree": 'முதுகலை பட்டம்',
  'PhD': 'முனைவர் பட்டம்',

  'Others': 'மற்றவை',
  'Other': 'மற்றவை',
  'Any': 'ஏதேனும்',

  // ── Consultation categories (booking flow) ──
  'Marriage Matching': 'திருமண பொருத்தம்',
  'Marriage Consultation': 'திருமண ஆலோசனை',
  'Career Guidance': 'தொழில் வழிகாட்டல்',
  'Career': 'தொழில்',
  'Family': 'குடும்பம்',
  'Finance': 'நிதி',
  'Education': 'கல்வி',
  'General Horoscope': 'பொது ஜாதக ஆலோசனை',
  'General Horoscope Consultation': 'பொது ஜாதக ஆலோசனை',
  'Health': 'உடல்நலம்',

  // ── Contact relationship (Contact step) ──
  'Self': 'நானே',
  'Father': 'தந்தை',
  'Mother': 'தாய்',
  'Guardian': 'பாதுகாவலர்',
  'Friend': 'நண்பர்',

  // ── Citizenship ──
  'Indian': 'இந்தியர்',
  'NRI': 'வெளிநாடு வாழ் இந்தியர்',
  'Foreign National': 'வெளிநாட்டவர்',

  // ── State / country (the platform serves Tamil Nadu / India) ──
  'Tamil Nadu': 'தமிழ்நாடு',
  'Tamilnadu': 'தமிழ்நாடு',
  'India': 'இந்தியா',

  // ── Children living status ──
  'Living with me': 'என்னுடன் வசிக்கிறார்கள்',
  'Not living with me': 'என்னுடன் வசிக்கவில்லை',
  'No children': 'குழந்தைகள் இல்லை',

  // ── Annual income ranges ──
  'Below ₹1 Lakh': '₹1 லட்சத்திற்குக் கீழ்',
  '₹1-2 Lakhs': '₹1-2 லட்சம்',
  '₹2-3 Lakhs': '₹2-3 லட்சம்',
  '₹3-5 Lakhs': '₹3-5 லட்சம்',
  '₹5-7 Lakhs': '₹5-7 லட்சம்',
  '₹7-10 Lakhs': '₹7-10 லட்சம்',
  '₹10-15 Lakhs': '₹10-15 லட்சம்',
  '₹15-20 Lakhs': '₹15-20 லட்சம்',
  '₹20-30 Lakhs': '₹20-30 லட்சம்',
  '₹30-50 Lakhs': '₹30-50 லட்சம்',
  'Above ₹50 Lakhs': '₹50 லட்சத்திற்கு மேல்',

  // ── Misc option values ──
  'Any Caste': 'எந்த சாதியும்',
  "Doesn't Matter": 'பரவாயில்லை',
  'Marathi': 'மராத்தி',
  'Bengali': 'வங்காளம்',
  'Gujarati': 'குஜராத்தி',
  'Punjabi': 'பஞ்சாபி',
  'Urdu': 'உருது',

  // ── Misc statuses (incl. profile status, §20 "Profile Status") ──
  'Pending': 'நிலுவையில்',
  'Accepted': 'ஏற்கப்பட்டது',
  'Approved': 'அங்கீகரிக்கப்பட்டது',
  'approved': 'அங்கீகரிக்கப்பட்டது',
  'pending': 'நிலுவையில்',
  'rejected': 'நிராகரிக்கப்பட்டது',
  'blocked': 'தடுக்கப்பட்டது',
  'Blocked': 'தடுக்கப்பட்டது',
  'Active': 'செயலில்',
  'Inactive': 'செயலில் இல்லை',
  'Married': 'திருமணமானவர்',
  'Rejected': 'நிராகரிக்கப்பட்டது',
  'Completed': 'முடிந்தது',
  'Confirmed': 'உறுதிப்படுத்தப்பட்டது',
  'Cancelled': 'ரத்து செய்யப்பட்டது',
};

/// Astrology values (Rasi · Nakshatra · Lagnam) are stored in TAMIL script,
/// because that is what the pickers offer. English mode must therefore
/// translate the OTHER way (§20: "When English is selected, everything must
/// become English").
///
/// [AppConstants] keeps the Tamil and English lists aligned index-for-index, so
/// the two maps below are derived from them rather than duplicated by hand.
final Map<String, String> _astroTaToEn = {
  for (var i = 0; i < AppConstants.rasiList.length; i++)
    AppConstants.rasiList[i]: AppConstants.rasiEnList[i],
  for (var i = 0; i < AppConstants.nakshatraList.length; i++)
    AppConstants.nakshatraList[i]: AppConstants.nakshatraEnList[i],
};

/// The reverse direction, so a value stored in English (older documents, or the
/// website) still renders in Tamil.
final Map<String, String> _astroEnToTa = {
  for (final e in _astroTaToEn.entries) e.value: e.key,
  // Also accept the bare transliteration without the zodiac name in brackets,
  // e.g. "Mesham" as well as "Mesham (Aries)".
  for (var i = 0; i < AppConstants.rasiEnList.length; i++)
    AppConstants.rasiEnList[i].split(' (').first: AppConstants.rasiList[i],
};

/// Runtime English → Tamil names contributed by loaded master data (castes and
/// sub-castes number in the hundreds — far too many to hardcode in
/// [kTamilValueMap]). [MasterDataService] populates this once the datasets load
/// from Firestore / the bundled fallback, keyed case-insensitively on the
/// canonical English name. [localizeValue] consults it after the static map, so
/// a stored English caste renders in Tamil anywhere `localizeValue` is used
/// while storage stays English (spec §13/§14).
final Map<String, String> _masterTamilNames = {};

/// Registers `{ englishName: tamilName }` pairs from master data. Empty names on
/// either side are ignored; later registrations overwrite earlier ones.
void registerMasterTamilNames(Map<String, String> pairs) {
  pairs.forEach((en, ta) {
    final k = en.trim().toLowerCase();
    final v = ta.trim();
    if (k.isNotEmpty && v.isNotEmpty) _masterTamilNames[k] = v;
  });
}

/// The registered Tamil name for a canonical English [value], or null.
String? masterTamilNameFor(String value) =>
    _masterTamilNames[value.trim().toLowerCase()];

extension ValueL10nX on BuildContext {
  /// True when the app is currently displayed in Tamil.
  bool get isTamil => Localizations.localeOf(this).languageCode == 'ta';

  /// Renders a stored data [value] in the ACTIVE language (§20).
  ///
  ///  • Tamil mode → the Tamil text for a canonical English value (static map,
  ///    then the master-data registry, then the astrology pairs).
  ///  • English mode → the English text for a value stored in Tamil script
  ///    (Rasi / Nakshatra / Lagnam are stored in Tamil, so English mode has to
  ///    translate back).
  ///
  /// An unmapped value is returned unchanged, which makes this safe to apply
  /// anywhere a stored value is rendered.
  String localizeValue(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return v;
    if (isTamil) {
      return kTamilValueMap[v] ??
          masterTamilNameFor(v) ??
          _astroEnToTa[v] ??
          v;
    }
    return _astroTaToEn[v] ?? v;
  }
}
