import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/value_l10n.dart';
import '../../models/profile_model.dart';
import '../../providers/location_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/network_photo.dart';
import '../../widgets/profile/field_edit_sheet.dart';

// ── Tamil display helpers (display-only — storage stays English, spec §14) ────

/// Section-title translations for the My Profile page.
const Map<String, String> _kTitleTa = {
  'My Profile': 'என் சுயவிவரம்',
  'Basic Details': 'அடிப்படை விவரங்கள்',
  'Location': 'இருப்பிடம்',
  'Career': 'தொழில்',
  'Community': 'சமூகம்',
  'Horoscope': 'ஜாதகம்',
  'Family Details': 'குடும்ப விவரங்கள்',
  'Partner Preferences': 'துணை விருப்பங்கள்',
  'Photos': 'புகைப்படங்கள்',
  'Upload Horoscope': 'ஜாதகம் பதிவேற்றம்',
  'Contact': 'தொடர்பு',
};

/// Field-label translations for the My Profile page.
const Map<String, String> _kLabelTa = {
  'Profile For': 'சுயவிவரம் யாருக்காக',
  'Name': 'பெயர்',
  'Gender': 'பாலினம்',
  'Age': 'வயது',
  'Height': 'உயரம்',
  'Weight': 'எடை',
  'Marital Status': 'திருமண நிலை',
  'Physical Status': 'உடல் நிலை',
  'Children': 'குழந்தைகள்',
  'Children Living Status': 'குழந்தைகள் வசிப்பு நிலை',
  'Location': 'தற்போதைய வசிப்பிடம்',
  'Native Place': 'சொந்த ஊர்',
  'Citizenship': 'குடியுரிமை',
  'Education': 'கல்வி',
  'Occupation': 'பணி',
  'Course / Degree': 'படிப்பு / பட்டம்',
  'Employment Type': 'வேலை வகை',
  'Annual Income': 'ஆண்டு வருமானம்',
  'Religion': 'மதம்',
  'Caste': 'சாதி',
  'Sub Caste': 'உட்சாதி',
  'Mother Tongue': 'தாய்மொழி',
  'Gothram': 'கோத்திரம்',
  'Kuladeivam': 'குலதெய்வம்',
  'Rasi': 'ராசி',
  'Nakshatra': 'நட்சத்திரம்',
  'Lagnam': 'லக்னம்',
  'Birth Time': 'பிறந்த நேரம்',
  'Birth Place': 'பிறந்த இடம்',
  'Profession': 'பணி',
  'Income': 'வருமானம்',
  'Horoscope Match Required': 'ஜாதக பொருத்தம் தேவை',
  'Contact Person': 'தொடர்பு நபர்',
  'Relationship': 'உறவுமுறை',
  'Mobile': 'கைபேசி',
  'WhatsApp': 'வாட்ஸ்அப்',
  'Email': 'மின்னஞ்சல்',
  'Horoscope PDF': 'ஜாதக PDF',
  'Father': 'தந்தை',
  "Father's Occupation": 'தந்தையின் தொழில்',
  'Mother': 'தாய்',
  "Mother's Occupation": 'தாயின் தொழில்',
  'Brothers': 'சகோதரர்கள்',
  'Sisters': 'சகோதரிகள்',
  'Family Type': 'குடும்ப வகை',
  'Family Status': 'குடும்ப நிலை',
};

/// Section title in the current language (English key → Tamil in Tamil mode).
String _title(BuildContext c, String en) =>
    c.isTamil ? (_kTitleTa[en] ?? en) : en;

/// Field label in the current language.
String _label(BuildContext c, String en) =>
    c.isTamil ? (_kLabelTa[en] ?? en) : en;

/// "25 yrs" → "25 வயது"; empty when age is unknown.
String _ageText(BuildContext c, int age) =>
    age <= 0 ? '' : (c.isTamil ? '$age வயது' : '$age yrs');

/// Preferred-age range: "24 – 30 yrs" / "24 – 30 வயது".
String _rangeYrs(BuildContext c, int min, int max) =>
    c.isTamil ? '$min – $max வயது' : '$min – $max yrs';

/// Height: `5'4"` → `5 அடி 4 அங்குலம்` in Tamil; unchanged otherwise.
String _heightText(BuildContext c, String h) {
  final v = h.trim();
  if (v.isEmpty || !c.isTamil) return v;
  final m = RegExp(r"(\d+)\s*'\s*(\d+)").firstMatch(v);
  if (m != null) return '${m.group(1)} அடி ${m.group(2)} அங்குலம்';
  return v;
}

/// Weight: "70" → "70 கிலோ" (Tamil) / "70 kg". Empty stays empty.
String _weightText(BuildContext c, String w) {
  final v = w.trim();
  if (v.isEmpty) return '';
  return c.isTamil ? '$v கிலோ' : '$v kg';
}

/// The signed-in member's own contact record (access-gated `contacts/{uid}`;
/// the owner can always read their own).
final myContactProvider = FutureProvider.autoDispose<ContactDetails?>((ref) async {
  final profile = ref.watch(myProfileProvider).valueOrNull;
  if (profile == null) return null;
  try {
    return await ref.read(firestoreServiceProvider).getContact(profile.userId);
  } catch (_) {
    return null; // gated / offline — the section simply shows no rows
  }
});

/// **My Profile** — the member's complete profile organised into the same
/// categories as profile creation, each with its own Edit action that opens
/// ONLY that section (never the full wizard from step 1). Saving a section
/// updates just that category; the live profile stream refreshes the page
/// instantly.
class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final contact = ref.watch(myContactProvider).valueOrNull;
    // Ensures the Tamil-Nadu location dataset loads so district/city names are
    // registered for Tamil display (see LocationRepository); rebuilds when ready.
    ref.watch(districtsProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(_title(context, 'My Profile')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: profileAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => _empty(context),
        data: (p) => p == null ? _empty(context) : _body(context, p, contact),
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(context.l10n.noProfileFoundCreate),
          ],
        ),
      );

  Widget _body(BuildContext context, ProfileModel p, ContactDetails? contact) {
    final pp = p.partnerPreferences;
    final h = p.horoscope;

    String s(Object? v) => (v == null) ? '' : v.toString().trim();
    // Localized display of a stored English value (Male → ஆண், etc.).
    String lv(Object? v) => context.localizeValue(s(v));
    // "ஆம் / இல்லை" for a yes/no flag.
    String yn(bool v) => context.localizeValue(v ? 'Yes' : 'No');
    // Translate a field label for the current language.
    String l(String en) => _label(context, en);

    // Edit route for a wizard section (step index in the creation flow).
    void editStep(int step) =>
        context.push('/profile/${p.id}/edit-section/$step');

    // Location parts are localized individually so each (city / district /
    // state / country) renders in Tamil while storage stays English.
    final location = [p.city, p.district, p.state, p.country]
        .map(lv)
        .where((v) => v.isNotEmpty)
        .join(', ');
    final prefLocation = [pp.city, pp.district, pp.state]
        .map(lv)
        .where((v) => v.isNotEmpty)
        .join(', ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _header(context, p),
        const SizedBox(height: 6),

        _SectionCard(
          icon: Icons.badge_outlined,
          title: 'Basic Details',
          // Field-level editing: opens a sheet to edit ONLY the chosen field.
          onEdit: () => showProfileFieldSheet(context,
              sectionTitle: 'Basic Details', fieldsBuilder: basicDetailsFields),
          rows: [
            [l('Profile For'), lv(p.profileCreatedFor)],
            [l('Name'), p.displayName(context.isTamil)],
            [l('Gender'), lv(p.gender)],
            [l('Age'), _ageText(context, p.age)],
            [l('Height'), _heightText(context, s(p.height))],
            [l('Weight'), _weightText(context, s(p.weight))],
            [l('Marital Status'), lv(p.maritalStatus)],
            [l('Physical Status'), lv(p.physicalStatus)],
            if (p.childrenCount > 0) ...[
              [l('Children'), '${p.childrenCount}'],
              [l('Children Living Status'), lv(p.childrenLivingStatus)],
            ],
          ],
        ),
        _SectionCard(
          icon: Icons.location_on_outlined,
          title: 'Location',
          // Composite (state→district→city cascade) → dedicated section editor.
          onEdit: () => context.push('/edit/location'),
          rows: [
            [l('Location'), location],
            [l('Native Place'), lv(p.nativePlace)],
            [l('Citizenship'), lv(p.citizenship)],
          ],
        ),
        _SectionCard(
          icon: Icons.work_outline,
          title: 'Career',
          // Field-level editing: edit ONLY the chosen career field.
          onEdit: () => showProfileFieldSheet(context,
              sectionTitle: 'Career', fieldsBuilder: careerFields),
          rows: [
            [l('Education'), lv(p.education)],
            [l('Occupation'), lv(p.occupation)],
            [l('Course / Degree'), lv(p.courseDegree)],
            [l('Employment Type'), lv(p.employmentType)],
            [l('Annual Income'), lv(p.annualIncome)],
          ],
        ),
        _SectionCard(
          icon: Icons.diversity_3_outlined,
          title: 'Community',
          // Composite (religion→caste→subcaste cascade) → dedicated editor.
          onEdit: () => context.push('/edit/religious'),
          rows: [
            [l('Religion'), lv(p.religion)],
            [l('Caste'), lv(p.caste)],
            [l('Sub Caste'), lv(p.subCaste)],
            [l('Mother Tongue'), lv(p.motherTongue)],
            [l('Gothram'), lv(p.gothram)],
            [l('Kuladeivam'), lv(p.kuladeivam)],
          ],
        ),
        // Family Details (§5) — editable like every other section.
        _SectionCard(
          icon: Icons.family_restroom_outlined,
          title: 'Family Details',
          onEdit: () => context.push('/edit/family'),
          rows: [
            [l('Father'), s(p.family.fatherName)],
            [l("Father's Occupation"), lv(p.family.fatherOccupation)],
            [l('Mother'), s(p.family.motherName)],
            [l("Mother's Occupation"), lv(p.family.motherOccupation)],
            [
              l('Brothers'),
              p.family.brothersCount > 0 ? '${p.family.brothersCount}' : ''
            ],
            [
              l('Sisters'),
              p.family.sistersCount > 0 ? '${p.family.sistersCount}' : ''
            ],
            [l('Family Type'), lv(p.family.familyType)],
            [l('Family Status'), lv(p.family.familyStatus)],
          ],
        ),
        _SectionCard(
          icon: Icons.auto_awesome_outlined,
          title: 'Horoscope',
          // Opens ONLY the Horoscope details editor (not the full wizard).
          onEdit: () => context.push('/horoscope'),
          rows: [
            [l('Rasi'), lv(h.rasi)],
            [l('Nakshatra'), lv(h.nakshatra)],
            [l('Lagnam'), lv(h.lagnam)],
            [l('Birth Time'), s(h.birthTime)],
            [l('Birth Place'), lv(h.birthPlace)],
          ],
        ),
        _SectionCard(
          icon: Icons.tune,
          title: 'Partner Preferences',
          onEdit: () => context.push('/partner-preferences'),
          rows: [
            [l('Age'), _rangeYrs(context, pp.minAge, pp.maxAge)],
            [l('Height'), '${pp.minHeight} – ${pp.maxHeight}'],
            [l('Caste'), lv(pp.caste)],
            [l('Education'), pp.education.map(lv).join(', ')],
            [l('Profession'), pp.occupation.map(lv).join(', ')],
            [l('Location'), prefLocation],
            [l('Income'), lv(pp.income)],
            [l('Marital Status'), lv(pp.maritalStatus)],
            [l('Mother Tongue'), lv(pp.motherTongue)],
            [l('Horoscope Match Required'), yn(pp.horoscopeMatchRequired)],
          ],
        ),
        _SectionCard(
          icon: Icons.photo_camera_outlined,
          title: 'Photos',
          // Opens ONLY the Photos editor.
          onEdit: () => context.push('/edit/photos'),
          rows: const [],
          child: p.photos.isEmpty
              ? Text(context.l10n.noPhotoAddedYet,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13))
              // Square thumbnail — the photo is a 1:1 crop everywhere (§1).
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 104,
                    height: 104,
                    child: NetworkPhoto(
                        url: p.photos.first,
                        fit: BoxFit.cover,
                        fallbackIcon: Icons.person),
                  ),
                ),
        ),
        _SectionCard(
          icon: Icons.picture_as_pdf_outlined,
          title: 'Upload Horoscope',
          onEdit: () => editStep(7),
          rows: [
            [
              l('Horoscope PDF'),
              (h.horoscopePdfUrl ?? '').isNotEmpty
                  ? (context.isTamil ? 'இணைக்கப்பட்டது' : 'Attached')
                  : (context.isTamil ? 'சேர்க்கப்படவில்லை' : 'Not added'),
            ],
          ],
        ),
        _SectionCard(
          icon: Icons.call_outlined,
          title: 'Contact',
          onEdit: () => editStep(8),
          rows: [
            [l('Contact Person'), s(contact?.contactPersonName)],
            [l('Relationship'), lv(contact?.relationship)],
            [l('Mobile'), s(contact?.mobileNumber)],
            [l('WhatsApp'), s(contact?.whatsappNumber)],
            [l('Email'), s(contact?.email)],
          ],
        ),
      ],
    );
  }

  /// Top header — photo, name, quick facts.
  Widget _header(BuildContext context, ProfileModel p) {
    final facts = [
      if (p.age > 0) _ageText(context, p.age),
      if (p.height.trim().isNotEmpty) _heightText(context, p.height),
      if ((p.caste ?? '').trim().isNotEmpty) context.localizeValue(p.caste!),
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 64,
              height: 64,
              child: p.photos.isEmpty
                  ? Container(
                      color: Colors.white24,
                      child: const Icon(Icons.person,
                          color: Colors.white, size: 34))
                  : NetworkPhoto(
                      url: p.photos.first,
                      fit: BoxFit.cover,
                      fallbackIcon: Icons.person),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.displayName(context.isTamil),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold)),
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(facts,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12.5)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Computes age from a date of birth (so editing DOB keeps `age` in sync).
int _ageFromDob(DateTime dob) {
  final now = DateTime.now();
  var age = now.year - dob.year;
  if (now.month < dob.month ||
      (now.month == dob.month && now.day < dob.day)) {
    age--;
  }
  return age < 0 ? 0 : age;
}

/// Field-level editable descriptors for the **Basic Details** section — each
/// saves ONLY its own field (Firestore patch) and leaves everything else as-is.
///
/// EVERY field here is editable after profile creation (§5), including the
/// Date of Birth (which also recomputes `age`, so matching stays correct).
/// Labels come from the l10n dictionary so the editor switches language with
/// the rest of the app (§21).
List<ProfileEditableField> basicDetailsFields(BuildContext c, ProfileModel p) {
  final l = c.l10n;
  return [
    ProfileEditableField(
      label: l.fullName,
      kind: ProfileFieldKind.text,
      value: p.fullName,
      localizeValues: false, // a person's name is never translated
      apply: (pr, v) => pr.copyWith(fullName: v as String),
      patch: (v) => {'fullName': v},
    ),
    ProfileEditableField(
      label: l.nameTamilLabel,
      kind: ProfileFieldKind.text,
      value: p.fullNameTamil,
      localizeValues: false,
      apply: (pr, v) => pr.copyWith(fullNameTamil: v as String),
      patch: (v) => {'fullNameTamil': v},
    ),
    ProfileEditableField(
      label: l.gender,
      kind: ProfileFieldKind.options,
      value: p.gender,
      options: const ['Male', 'Female'],
      apply: (pr, v) => pr.copyWith(gender: v as String),
      patch: (v) => {'gender': v},
    ),
    ProfileEditableField(
      label: l.ageDateOfBirth,
      kind: ProfileFieldKind.date,
      value: p.age > 0 ? _ageText(c, p.age) : '',
      localizeValues: false,
      dateValue: p.dateOfBirth,
      apply: (pr, v) {
        final d = v as DateTime;
        return pr.copyWith(dateOfBirth: d, age: _ageFromDob(d));
      },
      patch: (v) {
        final d = v as DateTime;
        return {'dateOfBirth': d, 'age': _ageFromDob(d)};
      },
    ),
    ProfileEditableField(
      label: l.height,
      kind: ProfileFieldKind.options,
      value: p.height,
      options: AppConstants.heightList,
      localizeValues: false, // 5'6" reads the same in both languages
      apply: (pr, v) => pr.copyWith(height: v as String),
      patch: (v) => {'height': v},
    ),
    ProfileEditableField(
      label: l.weightKgLabel,
      kind: ProfileFieldKind.number,
      value: p.weight,
      localizeValues: false,
      apply: (pr, v) => pr.copyWith(weight: v as String),
      patch: (v) => {'weight': v},
    ),
    ProfileEditableField(
      label: l.maritalStatus,
      kind: ProfileFieldKind.options,
      value: p.maritalStatus,
      options: AppConstants.maritalStatusList,
      apply: (pr, v) => pr.copyWith(maritalStatus: v as String),
      patch: (v) => {'maritalStatus': v},
    ),
    ProfileEditableField(
      label: l.physicalStatus,
      kind: ProfileFieldKind.options,
      value: p.physicalStatus,
      options: AppConstants.physicalStatusList,
      apply: (pr, v) => pr.copyWith(physicalStatus: v as String),
      patch: (v) => {'physicalStatus': v},
    ),
  ];
}

/// Field-level editable descriptors for the **Career** section.
List<ProfileEditableField> careerFields(BuildContext c, ProfileModel p) {
  final l = c.l10n;
  return [
    ProfileEditableField(
      label: l.education,
      kind: ProfileFieldKind.options,
      value: p.education,
      options: AppConstants.educationList,
      apply: (pr, v) => pr.copyWith(education: v as String),
      patch: (v) => {'education': v},
    ),
    ProfileEditableField(
      label: l.occupation,
      kind: ProfileFieldKind.options,
      value: p.occupation,
      options: AppConstants.occupationList,
      apply: (pr, v) => pr.copyWith(occupation: v as String),
      patch: (v) => {'occupation': v},
    ),
    ProfileEditableField(
      label: l.courseDegree,
      kind: ProfileFieldKind.text,
      value: p.courseDegree ?? '',
      localizeValues: false,
      apply: (pr, v) => pr.copyWith(courseDegree: v as String),
      patch: (v) => {'courseDegree': v},
    ),
    ProfileEditableField(
      label: l.employmentType,
      kind: ProfileFieldKind.options,
      value: p.employmentType,
      options: AppConstants.employmentTypeList,
      apply: (pr, v) => pr.copyWith(employmentType: v as String),
      patch: (v) => {'employmentType': v},
    ),
    ProfileEditableField(
      label: l.companyName,
      kind: ProfileFieldKind.text,
      value: p.companyName ?? '',
      localizeValues: false,
      apply: (pr, v) => pr.copyWith(companyName: v as String),
      patch: (v) => {'companyName': v},
    ),
    ProfileEditableField(
      label: l.collegeName,
      kind: ProfileFieldKind.text,
      value: p.collegeName ?? '',
      localizeValues: false,
      apply: (pr, v) => pr.copyWith(collegeName: v as String),
      patch: (v) => {'collegeName': v},
    ),
    ProfileEditableField(
      label: l.workLocation,
      kind: ProfileFieldKind.text,
      value: p.workLocation ?? '',
      localizeValues: false,
      apply: (pr, v) => pr.copyWith(workLocation: v as String),
      patch: (v) => {'workLocation': v},
    ),
    // Salary (§5) — editable like everything else; whether OTHERS can see it
    // is a separate Privacy Settings switch (§16).
    ProfileEditableField(
      label: l.annualIncome,
      kind: ProfileFieldKind.options,
      value: p.annualIncome,
      options: AppConstants.incomeList,
      apply: (pr, v) => pr.copyWith(annualIncome: v as String),
      patch: (v) => {'annualIncome': v},
    ),
  ];
}

/// One profile category: title + Edit action + label/value rows (empty values
/// are hidden). [child] renders custom content (e.g. the photo thumbnail).
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onEdit;
  final List<List<String>> rows;
  final Widget? child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.onEdit,
    required this.rows,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final visible = rows.where((r) => r[1].trim().isNotEmpty).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_title(context, title),
                    style: const TextStyle(
                        fontSize: 15,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold)),
              ),
              // The category's own Edit action — opens ONLY this section.
              IconButton(
                tooltip:
                    context.l10n.editSectionTooltip(_title(context, title)),
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined,
                    size: 19, color: AppColors.primary),
              ),
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: 6),
            child!,
          ],
          if (visible.isEmpty && child == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(context.l10n.notAddedTapToFill,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12.5)),
            )
          else
            ...visible.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(r[0],
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 13)),
                      ),
                      Expanded(
                        flex: 6,
                        child: Text(r[1],
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
