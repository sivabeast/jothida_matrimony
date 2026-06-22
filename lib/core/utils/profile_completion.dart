import 'package:flutter/material.dart';
import '../../models/profile_model.dart';

/// Result of a profile-completeness check: overall percentage plus the
/// human-readable names of whatever is still missing.
class ProfileCompletion {
  final int percent;
  final List<String> missingFields;

  const ProfileCompletion({required this.percent, required this.missingFields});

  bool get isComplete => percent >= 100;
}

/// One editable profile section, its completion state and where its editor is.
/// Drives the Home "Complete your profile" card and the Complete-Profile screen.
class ProfileSectionStatus {
  final String id;
  final String title;
  final IconData icon;
  final String route;
  final bool isComplete;

  const ProfileSectionStatus({
    required this.id,
    required this.title,
    required this.icon,
    required this.route,
    required this.isComplete,
  });
}

bool _ne(String? s) => (s ?? '').trim().isNotEmpty;

/// The canonical list of completable profile sections, each with its editor
/// route. The Home card lists the INCOMPLETE ones; the percentage is derived
/// from how many are complete, so editing a section updates the percent live.
List<ProfileSectionStatus> profileSections(ProfileModel? p) {
  final h = p?.horoscope;
  final f = p?.family;
  final l = p?.lifestyle;
  final pp = p?.partnerPreferences;

  final lifestyleFilled = l != null &&
      (_ne(l.eatingHabit) ||
          _ne(l.smokingHabit) ||
          _ne(l.drinkingHabit) ||
          _ne(l.hobbies) ||
          _ne(l.interests) ||
          l.languagesKnown.isNotEmpty);

  final partnerFilled = pp != null &&
      (pp.education.isNotEmpty ||
          pp.occupation.isNotEmpty ||
          (pp.religion.isNotEmpty && pp.religion != 'Any') ||
          (_ne(pp.caste) && pp.caste != 'Any') ||
          _ne(pp.city) ||
          (pp.eatingHabit.isNotEmpty && pp.eatingHabit != 'Any'));

  return [
    ProfileSectionStatus(
      id: 'about',
      title: 'About Me',
      icon: Icons.notes_outlined,
      route: '/edit/about',
      isComplete: _ne(p?.aboutMe),
    ),
    ProfileSectionStatus(
      id: 'education',
      title: 'Education & Career',
      icon: Icons.work_outline,
      route: '/edit/education',
      isComplete: _ne(p?.education) && _ne(p?.occupation),
    ),
    ProfileSectionStatus(
      id: 'location',
      title: 'Location Details',
      icon: Icons.location_on_outlined,
      route: '/edit/location',
      isComplete: _ne(p?.city) && _ne(p?.state),
    ),
    ProfileSectionStatus(
      id: 'religious',
      title: 'Religious Information',
      icon: Icons.account_balance_outlined,
      route: '/edit/religious',
      isComplete: _ne(p?.religion) && _ne(p?.caste),
    ),
    ProfileSectionStatus(
      id: 'astrology',
      title: 'Astrology Information',
      icon: Icons.auto_awesome_outlined,
      route: '/horoscope',
      isComplete: _ne(h?.rasi) && _ne(h?.nakshatra),
    ),
    ProfileSectionStatus(
      id: 'family',
      title: 'Family Details',
      icon: Icons.diversity_3_outlined,
      route: '/edit/family',
      isComplete: _ne(f?.fatherName) || _ne(f?.motherName),
    ),
    ProfileSectionStatus(
      id: 'lifestyle',
      title: 'Lifestyle & Habits',
      icon: Icons.spa_outlined,
      route: '/edit/lifestyle',
      isComplete: lifestyleFilled,
    ),
    ProfileSectionStatus(
      id: 'photos',
      title: 'Photos',
      icon: Icons.photo_camera_outlined,
      route: '/edit/photos',
      isComplete: _ne(p?.profilePhotoUrl),
    ),
    ProfileSectionStatus(
      id: 'partner',
      title: 'Partner Preference',
      icon: Icons.favorite_border,
      route: '/partner-preferences',
      isComplete: partnerFilled,
    ),
  ];
}

/// Computes how complete a matrimony profile is, derived from [profileSections]
/// so the percentage and the Home card always agree. A "Basic details"
/// baseline slot keeps a brand-new (but registered) profile above 0%.
ProfileCompletion computeProfileCompletion(ProfileModel? profile) {
  final sections = profileSections(profile);
  final total = sections.length + 1; // +1 baseline (basic registration details)
  final filled = 1 + sections.where((s) => s.isComplete).length;
  final percent = ((filled / total) * 100).round();
  final missing =
      sections.where((s) => !s.isComplete).map((s) => s.title).toList();
  return ProfileCompletion(percent: percent, missingFields: missing);
}

/// Whether a profile has enough CORE data to count as "completed" for gating
/// actions such as rating astrologers.
///
/// Computed from ACTUAL Firestore profile fields (not the
/// `users/{uid}.isProfileComplete` flag, which can lag behind real data).
/// Rule: the profile exists, has a name, and at least 3 of the four core
/// sections (photo, personal, horoscope, family) are filled in.
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
