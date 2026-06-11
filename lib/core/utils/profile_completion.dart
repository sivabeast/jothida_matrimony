import '../../models/profile_model.dart';

/// Result of a profile-completeness check: overall percentage plus the
/// human-readable names of whatever is still missing.
class ProfileCompletion {
  final int percent;
  final List<String> missingFields;

  const ProfileCompletion({required this.percent, required this.missingFields});

  bool get isComplete => percent >= 100;
}

/// Computes how complete a matrimony profile is.
///
/// Registration alone (name/mobile/gender/DOB/location) counts as the
/// baseline; the rest comes from the detailed profile. Each entry below is an
/// equally weighted check.
ProfileCompletion computeProfileCompletion(ProfileModel? profile) {
  // (label, isFilled)
  final checks = <MapEntry<String, bool>>[
    MapEntry('Basic details', profile != null),
    MapEntry('Profile photo',
        (profile?.profilePhotoUrl ?? '').isNotEmpty),
    MapEntry('About me', (profile?.aboutMe ?? '').trim().isNotEmpty),
    MapEntry('Education', (profile?.education ?? '').isNotEmpty),
    MapEntry('Profession', (profile?.occupation ?? '').isNotEmpty),
    MapEntry('Annual income', (profile?.annualIncome ?? '').isNotEmpty),
    MapEntry('Height & weight',
        (profile?.height ?? '').isNotEmpty && (profile?.weight ?? '').isNotEmpty),
    MapEntry(
        'Horoscope (Rasi & Nakshatra)',
        (profile?.horoscope.rasi ?? '').isNotEmpty &&
            (profile?.horoscope.nakshatra ?? '').isNotEmpty),
    MapEntry('Birth time & place',
        (profile?.horoscope.birthTime ?? '').isNotEmpty &&
            (profile?.horoscope.birthPlace ?? '').isNotEmpty),
    MapEntry('Family details',
        (profile?.family.fatherName ?? '').isNotEmpty ||
            (profile?.family.motherName ?? '').isNotEmpty),
    MapEntry(
        'Partner preferences',
        profile != null &&
            (profile.partnerPreferences.education.isNotEmpty ||
                profile.partnerPreferences.occupation.isNotEmpty ||
                profile.partnerPreferences.religion != 'Any' ||
                profile.partnerPreferences.caste != null)),
    MapEntry('Contact details',
        (profile?.contact.mobileNumber ?? '').isNotEmpty),
  ];

  // Registration always contributes one "filled" slot so a brand-new account
  // isn't shown as 0%.
  final filled = 1 + checks.where((c) => c.value).length;
  final total = 1 + checks.length;
  final percent = ((filled / total) * 100).round();
  final missing = checks.where((c) => !c.value).map((c) => c.key).toList();

  return ProfileCompletion(percent: percent, missingFields: missing);
}
