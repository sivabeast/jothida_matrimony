import 'package:flutter/widgets.dart';

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

  // ── Employment type ──
  'Government': 'அரசு வேலை',
  'Government Job': 'அரசு வேலை',
  'Private': 'தனியார் வேலை',
  'Private Job': 'தனியார் வேலை',
  'Business': 'வணிகம்',
  'Self Employed': 'சுய தொழில்',
  'Self-Employed': 'சுய தொழில்',
  'Not Working': 'வேலையில் இல்லை',
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

  // ── Education (common levels) ──
  'Below 10th': '10ஆம் வகுப்புக்குக் கீழ்',
  '10th': '10ஆம் வகுப்பு',
  '10th Standard': '10ஆம் வகுப்பு',
  '12th': '12ஆம் வகுப்பு',
  '12th Standard': '12ஆம் வகுப்பு',
  'Diploma': 'டிப்ளமோ',
  'ITI': 'ஐடிஐ',
  'Bachelors': 'இளங்கலை பட்டம்',
  "Bachelor's Degree": 'இளங்கலை பட்டம்',
  'Masters': 'முதுகலை பட்டம்',
  "Master's Degree": 'முதுகலை பட்டம்',
  'Doctorate': 'முனைவர் பட்டம்',
  'PhD': 'முனைவர் பட்டம்',

  // ── Common occupations ──
  'Software Professional': 'மென்பொருள் நிபுணர்',
  'Software Engineer': 'மென்பொருள் பொறியாளர்',
  'Engineer': 'பொறியாளர்',
  'Doctor': 'மருத்துவர்',
  'Teacher': 'ஆசிரியர்',
  'Professor': 'பேராசிரியர்',
  'Lawyer': 'வழக்கறிஞர்',
  'Accountant': 'கணக்காளர்',
  'Banker': 'வங்கி ஊழியர்',
  'Business Owner': 'வணிக உரிமையாளர்',
  'Farmer': 'விவசாயி',
  'Nurse': 'செவிலியர்',
  'Police': 'காவலர்',
  'Homemaker': 'இல்லத்தரசி',
  'Student': 'மாணவர்',
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

  // ── Misc statuses ──
  'Pending': 'நிலுவையில்',
  'Accepted': 'ஏற்கப்பட்டது',
  'Rejected': 'நிராகரிக்கப்பட்டது',
  'Completed': 'முடிந்தது',
  'Confirmed': 'உறுதிப்படுத்தப்பட்டது',
  'Cancelled': 'ரத்து செய்யப்பட்டது',
};

extension ValueL10nX on BuildContext {
  /// True when the app is currently displayed in Tamil.
  bool get isTamil => Localizations.localeOf(this).languageCode == 'ta';

  /// Returns the Tamil display text for a stored English data [value] when the
  /// app locale is Tamil; otherwise (or when unmapped) returns [value] as-is.
  String localizeValue(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return v;
    if (!isTamil) return v;
    return kTamilValueMap[v] ?? v;
  }
}
