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

/// Whether a profile has enough CORE data to count as "completed" for gating
/// actions such as rating astrologers.
///
/// This is deliberately computed from the ACTUAL Firestore profile fields (not
/// the `users/{uid}.isProfileComplete` flag, which can lag behind real data and
/// wrongly lock a finished profile out). It also avoids penalising fields that
/// never live on the public profile document — contact details are stored in
/// the gated `contacts/{uid}` collection, and partner preferences / "about me"
/// are optional — so a user who finished Personal + Horoscope + Family + Photos
/// is correctly treated as complete.
///
/// Rule: the profile must exist, have a name, and have at least 3 of the four
/// core sections (photo, personal, horoscope, family) filled in.
bool isProfileCompleteEnough(ProfileModel? p) {
  if (p == null) return false;
  final hasIdentity = p.fullName.trim().isNotEmpty;
  if (!hasIdentity) return false;

  final hasPhoto =
      (p.profilePhotoUrl ?? '').trim().isNotEmpty || p.additionalPhotos.isNotEmpty;
  final hasPersonal = p.education.trim().isNotEmpty ||
      p.occupation.trim().isNotEmpty ||
      p.height.trim().isNotEmpty;
  final hasHoroscope = p.horoscope.rasi.trim().isNotEmpty ||
      p.horoscope.nakshatra.trim().isNotEmpty ||
      p.horoscope.birthTime.trim().isNotEmpty;
  final hasFamily = p.family.fatherName.trim().isNotEmpty ||
      p.family.motherName.trim().isNotEmpty;

  final coreSections =
      [hasPhoto, hasPersonal, hasHoroscope, hasFamily].where((b) => b).length;
  return coreSections >= 3;
}
