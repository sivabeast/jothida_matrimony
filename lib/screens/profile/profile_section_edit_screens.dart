import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_edit_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/location_picker_section.dart';
import '../../widgets/common/religion_caste_fields.dart';
import '../../widgets/common/searchable_field.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared chrome + save helper for every section editor.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _persistSection(
  BuildContext context,
  WidgetRef ref, {
  required ProfileModel updated,
  required Map<String, dynamic> patch,
}) async {
  try {
    await ref
        .read(profileEditControllerProvider.notifier)
        .save(updated: updated, patch: patch);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved')));
    Navigator.of(context).maybePop();
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Please try again.')));
  }
}

/// Outer wrapper: loads `myProfile`, shows the [builder] form once available.
class _SectionLoader extends ConsumerWidget {
  final String title;
  final Widget Function(ProfileModel profile) builder;
  const _SectionLoader({required this.title, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myProfileProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) =>
            const Center(child: Text('Could not load your profile.')),
        data: (p) => p == null
            ? const Center(child: Text('Create your profile first.'))
            : builder(p),
      ),
    );
  }
}

/// Scrollable form body + a sticky Save button with a loading overlay.
class _FormBody extends ConsumerWidget {
  final List<Widget> children;
  final VoidCallback onSave;
  const _FormBody({
    required this.children,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saving = ref.watch(profileEditControllerProvider).isLoading;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ...children,
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving ? null : onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(saving ? 'Saving…' : 'Save Changes'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
        if (saving)
          Container(
            color: Colors.black.withOpacity(0.05),
            child: const Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1) About Me
// ─────────────────────────────────────────────────────────────────────────────
class AboutMeEditScreen extends StatelessWidget {
  const AboutMeEditScreen({super.key});
  @override
  Widget build(BuildContext context) => _SectionLoader(
        title: 'About Me',
        builder: (p) => _AboutMeForm(profile: p),
      );
}

class _AboutMeForm extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _AboutMeForm({required this.profile});
  @override
  ConsumerState<_AboutMeForm> createState() => _AboutMeFormState();
}

class _AboutMeFormState extends ConsumerState<_AboutMeForm> {
  late final _about = TextEditingController(text: widget.profile.aboutMe ?? '');

  @override
  void dispose() {
    _about.dispose();
    super.dispose();
  }

  void _save() {
    final v = _about.text.trim();
    _persistSection(context, ref,
        updated: widget.profile.copyWith(aboutMe: v), patch: {'aboutMe': v});
  }

  @override
  Widget build(BuildContext context) {
    return _FormBody(
      onSave: _save,
      children: [
        AppTextField(
          controller: _about,
          label: 'About Me',
          hint: 'Write a few lines about yourself, your family, interests, '
              'values and expectations.',
          maxLines: 7,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2) Education & Career
// ─────────────────────────────────────────────────────────────────────────────
class EducationEditScreen extends StatelessWidget {
  const EducationEditScreen({super.key});
  @override
  Widget build(BuildContext context) => _SectionLoader(
        title: 'Education & Career',
        builder: (p) => _EducationForm(profile: p),
      );
}

class _EducationForm extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _EducationForm({required this.profile});
  @override
  ConsumerState<_EducationForm> createState() => _EducationFormState();
}

class _EducationFormState extends ConsumerState<_EducationForm> {
  late String? _education = _orNull(widget.profile.education);
  late String? _occupation = _orNull(widget.profile.occupation);
  late String? _employmentType = _orNull(widget.profile.employmentType);
  late String? _income = _orNull(widget.profile.annualIncome);
  late final _college =
      TextEditingController(text: widget.profile.collegeName ?? '');
  late final _company =
      TextEditingController(text: widget.profile.companyName ?? '');
  late final _workLocation =
      TextEditingController(text: widget.profile.workLocation ?? '');

  static String? _orNull(String s) => s.trim().isEmpty ? null : s;

  @override
  void dispose() {
    _college.dispose();
    _company.dispose();
    _workLocation.dispose();
    super.dispose();
  }

  void _save() {
    if (_education == null || _occupation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Education and occupation are required.')));
      return;
    }
    final patch = {
      'education': _education,
      'occupation': _occupation,
      'employmentType': _employmentType ?? '',
      'annualIncome': _income ?? '',
      'collegeName': _college.text.trim(),
      'companyName': _company.text.trim(),
      'workLocation': _workLocation.text.trim(),
    };
    _persistSection(context, ref,
        updated: widget.profile.copyWith(
          education: _education,
          occupation: _occupation,
          employmentType: _employmentType ?? '',
          annualIncome: _income ?? '',
          collegeName: _college.text.trim(),
          companyName: _company.text.trim(),
          workLocation: _workLocation.text.trim(),
        ),
        patch: patch);
  }

  @override
  Widget build(BuildContext context) {
    return _FormBody(
      onSave: _save,
      children: [
        SearchableField(
          label: 'Highest Education',
          isRequired: true,
          items: AppConstants.educations,
          selectedItem: _education,
          prefixIcon: Icons.school_outlined,
          onChanged: (v) => setState(() => _education = v),
        ),
        const SizedBox(height: 16),
        AppTextField(controller: _college, label: 'College Name'),
        const SizedBox(height: 16),
        SearchableField(
          label: 'Occupation',
          isRequired: true,
          items: AppConstants.occupations,
          selectedItem: _occupation,
          prefixIcon: Icons.work_outline,
          onChanged: (v) => setState(() => _occupation = v),
        ),
        const SizedBox(height: 16),
        SearchableField(
          label: 'Employment Type',
          items: AppConstants.employmentTypeList,
          selectedItem: _employmentType,
          prefixIcon: Icons.badge_outlined,
          onChanged: (v) => setState(() => _employmentType = v),
        ),
        const SizedBox(height: 16),
        AppTextField(controller: _company, label: 'Company Name'),
        const SizedBox(height: 16),
        SearchableField(
          label: 'Annual Income',
          items: AppConstants.incomeRanges,
          selectedItem: _income,
          prefixIcon: Icons.currency_rupee,
          onChanged: (v) => setState(() => _income = v),
        ),
        const SizedBox(height: 16),
        AppTextField(controller: _workLocation, label: 'Work Location'),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3) Location Details
// ─────────────────────────────────────────────────────────────────────────────
class LocationEditScreen extends StatelessWidget {
  const LocationEditScreen({super.key});
  @override
  Widget build(BuildContext context) => _SectionLoader(
        title: 'Location Details',
        builder: (p) => _LocationForm(profile: p),
      );
}

class _LocationForm extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _LocationForm({required this.profile});
  @override
  ConsumerState<_LocationForm> createState() => _LocationFormState();
}

class _LocationFormState extends ConsumerState<_LocationForm> {
  late String? _country = widget.profile.country.isEmpty
      ? 'India'
      : widget.profile.country;
  late String? _state = _n(widget.profile.state);
  late String? _stateId = _n(widget.profile.stateId);
  late String? _district = _n(widget.profile.district);
  late String? _districtId = _n(widget.profile.districtId);
  late String? _city = _n(widget.profile.city);
  late String? _cityId = _n(widget.profile.cityId);
  late double? _lat = widget.profile.latitude;
  late double? _lng = widget.profile.longitude;
  late String? _citizenship = _n(widget.profile.citizenship ?? '');
  late final _nativePlace =
      TextEditingController(text: widget.profile.nativePlace ?? '');

  static String? _n(String s) => s.trim().isEmpty ? null : s;

  @override
  void dispose() {
    _nativePlace.dispose();
    super.dispose();
  }

  void _save() {
    if (_state == null || _district == null || _city == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select state, district and city.')));
      return;
    }
    final patch = {
      'country': _country ?? 'India',
      'state': _state,
      'stateId': _stateId ?? '',
      'stateName': _state,
      'district': _district,
      'districtId': _districtId ?? '',
      'districtName': _district,
      'city': _city,
      'cityId': _cityId ?? '',
      'cityName': _city,
      'latitude': _lat,
      'longitude': _lng,
      'nativePlace': _nativePlace.text.trim(),
      'citizenship': _citizenship ?? '',
    };
    _persistSection(context, ref,
        updated: widget.profile.copyWith(
          country: _country ?? 'India',
          state: _state,
          stateId: _stateId ?? '',
          district: _district,
          districtId: _districtId ?? '',
          city: _city,
          cityId: _cityId ?? '',
          latitude: _lat,
          longitude: _lng,
          nativePlace: _nativePlace.text.trim(),
          citizenship: _citizenship ?? '',
        ),
        patch: patch);
  }

  @override
  Widget build(BuildContext context) {
    return _FormBody(
      onSave: _save,
      children: [
        LocationPickerSection(
          initialCountry: _country,
          initialState: _state,
          initialDistrict: _district,
          initialCity: _city,
          initialLatitude: _lat,
          initialLongitude: _lng,
          onChanged: (loc) => setState(() {
            _country = loc.country.isEmpty ? 'India' : loc.country;
            _state = loc.state.isEmpty ? null : loc.state;
            _stateId = loc.stateId.isEmpty ? null : loc.stateId;
            _district = loc.district.isEmpty ? null : loc.district;
            _districtId = loc.districtId.isEmpty ? null : loc.districtId;
            _city = loc.city.isEmpty ? null : loc.city;
            _cityId = loc.cityId.isEmpty ? null : loc.cityId;
            _lat = loc.latitude;
            _lng = loc.longitude;
          }),
        ),
        const SizedBox(height: 16),
        AppTextField(controller: _nativePlace, label: 'Native Place'),
        const SizedBox(height: 16),
        SearchableField(
          label: 'Citizenship',
          items: AppConstants.citizenshipList,
          selectedItem: _citizenship,
          prefixIcon: Icons.flag_outlined,
          onChanged: (v) => setState(() => _citizenship = v),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4) Religious Information
// ─────────────────────────────────────────────────────────────────────────────
class ReligiousEditScreen extends StatelessWidget {
  const ReligiousEditScreen({super.key});
  @override
  Widget build(BuildContext context) => _SectionLoader(
        title: 'Religious Information',
        builder: (p) => _ReligiousForm(profile: p),
      );
}

class _ReligiousForm extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _ReligiousForm({required this.profile});
  @override
  ConsumerState<_ReligiousForm> createState() => _ReligiousFormState();
}

class _ReligiousFormState extends ConsumerState<_ReligiousForm> {
  late String? _religion = _n(widget.profile.religion);
  late String? _religionId = widget.profile.religionId;
  late String? _caste = widget.profile.caste;
  late String? _casteId = widget.profile.casteId;
  late String? _subCaste = widget.profile.subCaste;
  late String? _subCasteId = widget.profile.subCasteId;
  late final _gothram =
      TextEditingController(text: widget.profile.gothram);
  late final _kuladeivam =
      TextEditingController(text: widget.profile.kuladeivam);

  static String? _n(String s) => s.trim().isEmpty ? null : s;

  @override
  void dispose() {
    _gothram.dispose();
    _kuladeivam.dispose();
    super.dispose();
  }

  void _save() {
    if (_religion == null || _caste == null || _caste!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Religion and caste are required.')));
      return;
    }
    final patch = {
      'religion': _religion,
      'religionId': _religionId,
      'caste': _caste,
      'casteId': _casteId,
      'subCaste': _subCaste ?? '',
      'subCasteId': _subCasteId,
      'gothram': _gothram.text.trim(),
      'kuladeivam': _kuladeivam.text.trim(),
    };
    _persistSection(context, ref,
        updated: widget.profile.copyWith(
          religion: _religion,
          religionId: _religionId,
          caste: _caste,
          casteId: _casteId,
          subCaste: _subCaste ?? '',
          subCasteId: _subCasteId,
          gothram: _gothram.text.trim(),
          kuladeivam: _kuladeivam.text.trim(),
        ),
        patch: patch);
  }

  @override
  Widget build(BuildContext context) {
    return _FormBody(
      onSave: _save,
      children: [
        ReligionCasteFields(
          religionId: _religionId,
          religionName: _religion,
          casteId: _casteId,
          casteName: _caste,
          subCasteId: _subCasteId,
          subCasteName: _subCaste,
          onReligionChanged: (id, name) => setState(() {
            _religionId = id;
            _religion = name;
            _casteId = null;
            _caste = null;
            _subCasteId = null;
            _subCaste = null;
          }),
          onCasteChanged: (id, name) => setState(() {
            _casteId = id;
            _caste = name;
            _subCasteId = null;
            _subCaste = null;
          }),
          onSubcasteChanged: (id, name) => setState(() {
            _subCasteId = id;
            _subCaste = name;
          }),
        ),
        const SizedBox(height: 16),
        AppTextField(controller: _gothram, label: 'Gothram'),
        const SizedBox(height: 16),
        AppTextField(controller: _kuladeivam, label: 'Kuladeivam'),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5) Family Details
// ─────────────────────────────────────────────────────────────────────────────
class FamilyEditScreen extends StatelessWidget {
  const FamilyEditScreen({super.key});
  @override
  Widget build(BuildContext context) => _SectionLoader(
        title: 'Family Details',
        builder: (p) => _FamilyForm(profile: p),
      );
}

class _FamilyForm extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _FamilyForm({required this.profile});
  @override
  ConsumerState<_FamilyForm> createState() => _FamilyFormState();
}

class _FamilyFormState extends ConsumerState<_FamilyForm> {
  late final FamilyDetails _f = widget.profile.family;
  late String? _familyType = _n(_f.familyType);
  late String? _familyStatus = _n(_f.familyStatus);
  late final _fatherName = TextEditingController(text: _f.fatherName);
  late final _fatherOcc = TextEditingController(text: _f.fatherOccupation);
  late final _motherName = TextEditingController(text: _f.motherName);
  late final _motherOcc = TextEditingController(text: _f.motherOccupation);
  late final _brothers = TextEditingController(
      text: _f.brothersCount > 0 ? '${_f.brothersCount}' : '');
  late final _sisters = TextEditingController(
      text: _f.sistersCount > 0 ? '${_f.sistersCount}' : '');
  late final _marriedBrothers = TextEditingController(
      text: _f.marriedBrothers > 0 ? '${_f.marriedBrothers}' : '');
  late final _marriedSisters = TextEditingController(
      text: _f.marriedSisters > 0 ? '${_f.marriedSisters}' : '');
  late final _aboutFamily = TextEditingController(text: _f.aboutFamily);

  static String? _n(String s) => s.trim().isEmpty ? null : s;
  int _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  @override
  void dispose() {
    for (final c in [
      _fatherName,
      _fatherOcc,
      _motherName,
      _motherOcc,
      _brothers,
      _sisters,
      _marriedBrothers,
      _marriedSisters,
      _aboutFamily,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final fam = _f.copyWith(
      familyType: _familyType ?? '',
      familyStatus: _familyStatus ?? '',
      fatherName: _fatherName.text.trim(),
      fatherOccupation: _fatherOcc.text.trim(),
      motherName: _motherName.text.trim(),
      motherOccupation: _motherOcc.text.trim(),
      brothersCount: _i(_brothers),
      sistersCount: _i(_sisters),
      marriedBrothers: _i(_marriedBrothers),
      marriedSisters: _i(_marriedSisters),
      aboutFamily: _aboutFamily.text.trim(),
    );
    _persistSection(context, ref,
        updated: widget.profile.copyWith(family: fam),
        patch: {'family': fam.toMap()});
  }

  @override
  Widget build(BuildContext context) {
    return _FormBody(
      onSave: _save,
      children: [
        SearchableField(
          label: 'Family Type',
          items: AppConstants.familyTypeList,
          selectedItem: _familyType,
          onChanged: (v) => setState(() => _familyType = v),
        ),
        const SizedBox(height: 16),
        SearchableField(
          label: 'Family Status',
          items: AppConstants.familyStatusList,
          selectedItem: _familyStatus,
          onChanged: (v) => setState(() => _familyStatus = v),
        ),
        const SizedBox(height: 16),
        AppTextField(controller: _fatherName, label: 'Father Name'),
        const SizedBox(height: 16),
        AppTextField(controller: _fatherOcc, label: 'Father Occupation'),
        const SizedBox(height: 16),
        AppTextField(controller: _motherName, label: 'Mother Name'),
        const SizedBox(height: 16),
        AppTextField(controller: _motherOcc, label: 'Mother Occupation'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _numField(_brothers, 'Brothers')),
            const SizedBox(width: 12),
            Expanded(child: _numField(_marriedBrothers, 'Married')),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _numField(_sisters, 'Sisters')),
            const SizedBox(width: 12),
            Expanded(child: _numField(_marriedSisters, 'Married')),
          ],
        ),
        const SizedBox(height: 16),
        AppTextField(
            controller: _aboutFamily, label: 'About Family', maxLines: 4),
      ],
    );
  }

  Widget _numField(TextEditingController c, String label) => AppTextField(
        controller: c,
        label: label,
        hint: '0',
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// 6) Lifestyle & Habits
// ─────────────────────────────────────────────────────────────────────────────
class LifestyleEditScreen extends StatelessWidget {
  const LifestyleEditScreen({super.key});
  @override
  Widget build(BuildContext context) => _SectionLoader(
        title: 'Lifestyle & Habits',
        builder: (p) => _LifestyleForm(profile: p),
      );
}

class _LifestyleForm extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _LifestyleForm({required this.profile});
  @override
  ConsumerState<_LifestyleForm> createState() => _LifestyleFormState();
}

class _LifestyleFormState extends ConsumerState<_LifestyleForm> {
  late final LifestyleDetails _l = widget.profile.lifestyle;
  late String? _eating = _n(_l.eatingHabit);
  late String? _smoking = _n(_l.smokingHabit);
  late String? _drinking = _n(_l.drinkingHabit);
  late final _hobbies = TextEditingController(text: _l.hobbies);
  late final _interests = TextEditingController(text: _l.interests);
  late final _languages =
      TextEditingController(text: _l.languagesKnown.join(', '));

  static String? _n(String s) => s.trim().isEmpty ? null : s;

  @override
  void dispose() {
    _hobbies.dispose();
    _interests.dispose();
    _languages.dispose();
    super.dispose();
  }

  void _save() {
    final langs = _languages.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final life = _l.copyWith(
      eatingHabit: _eating ?? '',
      smokingHabit: _smoking ?? '',
      drinkingHabit: _drinking ?? '',
      hobbies: _hobbies.text.trim(),
      interests: _interests.text.trim(),
      languagesKnown: langs,
    );
    _persistSection(context, ref,
        updated: widget.profile.copyWith(lifestyle: life),
        patch: {'lifestyle': life.toMap()});
  }

  @override
  Widget build(BuildContext context) {
    return _FormBody(
      onSave: _save,
      children: [
        SearchableField(
          label: 'Eating Habit',
          items: AppConstants.eatingHabitList,
          selectedItem: _eating,
          prefixIcon: Icons.restaurant_outlined,
          onChanged: (v) => setState(() => _eating = v),
        ),
        const SizedBox(height: 16),
        SearchableField(
          label: 'Smoking Habit',
          items: AppConstants.smokingHabitList,
          selectedItem: _smoking,
          prefixIcon: Icons.smoke_free,
          onChanged: (v) => setState(() => _smoking = v),
        ),
        const SizedBox(height: 16),
        SearchableField(
          label: 'Drinking Habit',
          items: AppConstants.drinkingHabitList,
          selectedItem: _drinking,
          prefixIcon: Icons.no_drinks_outlined,
          onChanged: (v) => setState(() => _drinking = v),
        ),
        const SizedBox(height: 16),
        AppTextField(
            controller: _hobbies,
            label: 'Hobbies',
            hint: 'e.g. Reading, Music, Cooking'),
        const SizedBox(height: 16),
        AppTextField(
            controller: _interests,
            label: 'Interests',
            hint: 'e.g. Travel, Sports'),
        const SizedBox(height: 16),
        AppTextField(
            controller: _languages,
            label: 'Languages Known',
            hint: 'Comma separated, e.g. Tamil, English'),
      ],
    );
  }
}
