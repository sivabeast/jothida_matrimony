import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/config/dev_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/demo_data_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/use_my_location_button.dart';

/// Personal Details — the primary profile-management screen.
///
/// Each section has its own ✏️ edit action that opens a lightweight bottom
/// sheet, pre-filled with the existing values. Saving performs a **partial**
/// Firestore update (only that section's fields; all other data is preserved)
/// and returns here. Editing never re-opens the onboarding/creation wizard.
class PersonalDetailsScreen extends ConsumerWidget {
  const PersonalDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[PersonalDetailsScreen] build — route /personal-details');
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Personal Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: profileAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => _Message(
          icon: Icons.error_outline,
          title: 'Could not load details',
          subtitle: '$e',
        ),
        data: (profile) {
          if (profile == null) {
            return _Message(
              icon: Icons.person_off_outlined,
              title: 'No profile yet',
              subtitle: 'Create your profile to manage your details here.',
              actionLabel: 'Create Profile',
              onAction: () => context.push('/profile/create'),
            );
          }
          final f = profile.family;
          final p = profile.partnerPreferences;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionCard(
                title: 'Basic Information',
                onEdit: () => _openSheet(context, _BasicInfoSheet(profile: profile)),
                fields: [
                  _kv('Full Name', profile.fullName),
                  _kv('Gender', profile.gender),
                  _kv('Date of Birth', _fmtDate(profile.dateOfBirth)),
                  _kv('Age', '${profile.age} yrs'),
                  _kv('Height', profile.height),
                  _kv('Weight', profile.weight),
                  _kv('Marital Status', profile.maritalStatus),
                  _kv('Mother Tongue', profile.motherTongue),
                ],
              ),
              _SectionCard(
                title: 'Religion & Community',
                onEdit: () => _openSheet(context, _CommunitySheet(profile: profile)),
                fields: [
                  _kv('Religion', profile.religion),
                  _kv('Caste', profile.caste ?? ''),
                  _kv('Sub Caste', profile.subCaste ?? ''),
                ],
              ),
              _SectionCard(
                title: 'Education & Career',
                onEdit: () => _openSheet(context, _CareerSheet(profile: profile)),
                fields: [
                  _kv('Education', profile.education),
                  _kv('Occupation', profile.occupation),
                  _kv('Annual Income', profile.annualIncome),
                ],
              ),
              _SectionCard(
                title: 'Location',
                onEdit: () => _openSheet(context, _LocationSheet(profile: profile)),
                fields: [
                  _kv('City', profile.city),
                  _kv('State', profile.state),
                  _kv('Country', profile.country),
                ],
              ),
              _SectionCard(
                title: 'Family Details',
                onEdit: () => _openSheet(context, _FamilySheet(profile: profile)),
                fields: [
                  _kv('Father', _join(f.fatherName, f.fatherOccupation)),
                  _kv('Mother', _join(f.motherName, f.motherOccupation)),
                  _kv('Brothers', f.brothersCount.toString()),
                  _kv('Sisters', f.sistersCount.toString()),
                  _kv('Family Type', f.familyType),
                  _kv('Family Status', f.familyStatus),
                ],
              ),
              _SectionCard(
                title: 'About Me',
                onEdit: () => _openSheet(context, _AboutSheet(profile: profile)),
                fields: [
                  _kv('', (profile.aboutMe ?? '').trim().isEmpty
                      ? 'Tap edit to add a short introduction.'
                      : profile.aboutMe!),
                ],
              ),
              // Partner Preferences has its own dedicated editor screen.
              _SectionCard(
                title: 'Partner Preferences',
                editIcon: Icons.open_in_new,
                onEdit: () => context.push('/partner-preferences'),
                fields: [
                  _kv('Age Range', '${p.minAge} - ${p.maxAge} yrs'),
                  _kv('Religion', p.religion),
                  _kv('Horoscope Match', p.horoscopeMatchRequired ? 'Required' : 'Optional'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

void _openSheet(BuildContext context, Widget sheet) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => sheet,
  );
}

/// Demo mode → update the in-memory store; real mode → partial Firestore write.
Future<void> _saveSection(
  WidgetRef ref,
  ProfileModel current,
  Map<String, dynamic> data,
  ProfileModel updated,
) async {
  if (kBypassAuth) {
    ref.read(demoProfilesProvider.notifier).upsert(updated);
  } else {
    await ref.read(profileRepositoryProvider).updateProfile(current.id, data);
    ref.invalidate(myProfileProvider);
  }
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

int _ageFromDob(DateTime dob) {
  final now = DateTime.now();
  var age = now.year - dob.year;
  if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
    age--;
  }
  return age < 0 ? 0 : age;
}

String _join(String a, String b) {
  final l = a.trim(), r = b.trim();
  if (l.isEmpty && r.isEmpty) return '';
  if (r.isEmpty) return l;
  if (l.isEmpty) return r;
  return '$l ($r)';
}

/// Ensures [current] is always selectable in a dropdown even if it isn't part
/// of the predefined [base] list (prevents silently changing a custom value).
List<String> _optsWith(List<String> base, String? current) {
  if (current == null || current.isEmpty || base.contains(current)) return base;
  return [current, ...base];
}

InputDecoration _dec(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );

Widget _tf(TextEditingController c, String label,
    {TextInputType? keyboard, int maxLines = 1}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
        controller: c,
        keyboardType: keyboard,
        maxLines: maxLines,
        decoration: _dec(label)),
  );
}

Widget _drop(String label, String value, List<String> opts,
    ValueChanged<String?> onChanged) {
  final safe = opts.contains(value) ? value : (opts.isNotEmpty ? opts.first : value);
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      value: safe,
      isExpanded: true,
      decoration: _dec(label),
      items: opts
          .map((o) => DropdownMenuItem(
              value: o, child: Text(o, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: onChanged,
    ),
  );
}

Widget _sheetChrome({
  required BuildContext context,
  required String title,
  required bool saving,
  required VoidCallback onSave,
  required List<Widget> children,
}) {
  return Padding(
    padding: EdgeInsets.only(
      left: 20,
      right: 20,
      top: 12,
      bottom: MediaQuery.of(context).viewInsets.bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...children,
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: BorderSide(color: Colors.grey[400]!),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: saving ? null : onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Section card + key/value row
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final VoidCallback onEdit;
  final List<Widget> fields;
  final IconData editIcon;
  const _SectionCard({
    required this.title,
    required this.onEdit,
    required this.fields,
    this.editIcon = Icons.edit_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              ),
              IconButton(
                icon: Icon(editIcon, size: 20, color: AppColors.primary),
                tooltip: 'Edit $title',
                onPressed: () {
                  debugPrint('[PersonalDetails] edit section: $title');
                  onEdit();
                },
              ),
            ],
          ),
          const Divider(height: 4),
          const SizedBox(height: 6),
          ...fields,
        ],
      ),
    );
  }
}

Widget _kv(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: label.isEmpty
          ? Text(value.trim().isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 13, height: 1.4))
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    flex: 5,
                    child: Text(label,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13))),
                Expanded(
                  flex: 6,
                  child: Text(value.trim().isEmpty ? '—' : value,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
    );

// ─────────────────────────────────────────────────────────────────────────────
// Section editors (bottom sheets)
// ─────────────────────────────────────────────────────────────────────────────

class _BasicInfoSheet extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _BasicInfoSheet({required this.profile});
  @override
  ConsumerState<_BasicInfoSheet> createState() => _BasicInfoSheetState();
}

class _BasicInfoSheetState extends ConsumerState<_BasicInfoSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.profile.fullName);
  late final TextEditingController _weight =
      TextEditingController(text: widget.profile.weight);
  late String _gender = widget.profile.gender.isEmpty ? 'Male' : widget.profile.gender;
  late DateTime _dob = widget.profile.dateOfBirth;
  late String _height = widget.profile.height;
  late String _marital = widget.profile.maritalStatus;
  late String _tongue = widget.profile.motherTongue;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final age = _ageFromDob(_dob);
    final data = {
      'fullName': _name.text.trim(),
      'gender': _gender,
      'dateOfBirth': Timestamp.fromDate(_dob),
      'age': age,
      'height': _height,
      'weight': _weight.text.trim(),
      'maritalStatus': _marital,
      'motherTongue': _tongue,
    };
    final updated = widget.profile.copyWith(
      fullName: _name.text.trim(),
      gender: _gender,
      dateOfBirth: _dob,
      age: age,
      height: _height,
      weight: _weight.text.trim(),
      maritalStatus: _marital,
      motherTongue: _tongue,
    );
    try {
      await _saveSection(ref, widget.profile, data, updated);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Basic information updated')));
    } catch (e) {
      debugPrint('[PersonalDetails] basic save error: $e');
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _sheetChrome(
      context: context,
      title: 'Edit Basic Information',
      saving: _saving,
      onSave: _save,
      children: [
        _tf(_name, 'Full Name'),
        _drop('Gender', _gender, _optsWith(const ['Male', 'Female'], _gender),
            (v) => setState(() => _gender = v!)),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: _pickDob,
            child: InputDecorator(
              decoration: _dec('Date of Birth'),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmtDate(_dob)),
                  const Icon(Icons.calendar_today_outlined, size: 18),
                ],
              ),
            ),
          ),
        ),
        _drop('Height', _height, _optsWith(AppConstants.heightList, _height),
            (v) => setState(() => _height = v!)),
        _tf(_weight, 'Weight', keyboard: TextInputType.number),
        _drop('Marital Status', _marital,
            _optsWith(AppConstants.maritalStatusList, _marital),
            (v) => setState(() => _marital = v!)),
        _drop('Mother Tongue', _tongue,
            _optsWith(AppConstants.motherTongueList, _tongue),
            (v) => setState(() => _tongue = v!)),
      ],
    );
  }
}

class _CommunitySheet extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _CommunitySheet({required this.profile});
  @override
  ConsumerState<_CommunitySheet> createState() => _CommunitySheetState();
}

class _CommunitySheetState extends ConsumerState<_CommunitySheet> {
  late String _religion =
      widget.profile.religion.isEmpty ? 'Hindu' : widget.profile.religion;
  late final TextEditingController _caste =
      TextEditingController(text: widget.profile.caste ?? '');
  late final TextEditingController _subCaste =
      TextEditingController(text: widget.profile.subCaste ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _caste.dispose();
    _subCaste.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final data = {
      'religion': _religion,
      'caste': _caste.text.trim(),
      'subCaste': _subCaste.text.trim(),
    };
    final updated = widget.profile.copyWith(
      religion: _religion,
      caste: _caste.text.trim(),
      subCaste: _subCaste.text.trim(),
    );
    try {
      await _saveSection(ref, widget.profile, data, updated);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Community details updated')));
    } catch (e) {
      debugPrint('[PersonalDetails] community save error: $e');
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _sheetChrome(
      context: context,
      title: 'Edit Religion & Community',
      saving: _saving,
      onSave: _save,
      children: [
        _drop('Religion', _religion,
            _optsWith(AppConstants.religionList, _religion),
            (v) => setState(() => _religion = v!)),
        _tf(_caste, 'Caste'),
        _tf(_subCaste, 'Sub Caste'),
      ],
    );
  }
}

class _CareerSheet extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _CareerSheet({required this.profile});
  @override
  ConsumerState<_CareerSheet> createState() => _CareerSheetState();
}

class _CareerSheetState extends ConsumerState<_CareerSheet> {
  late String _education = widget.profile.education;
  late String _occupation = widget.profile.occupation;
  late String _income = widget.profile.annualIncome;
  bool _saving = false;

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final data = {
      'education': _education,
      'occupation': _occupation,
      'annualIncome': _income,
    };
    final updated = widget.profile.copyWith(
      education: _education,
      occupation: _occupation,
      annualIncome: _income,
    );
    try {
      await _saveSection(ref, widget.profile, data, updated);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Career details updated')));
    } catch (e) {
      debugPrint('[PersonalDetails] career save error: $e');
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _sheetChrome(
      context: context,
      title: 'Edit Education & Career',
      saving: _saving,
      onSave: _save,
      children: [
        _drop('Education', _education,
            _optsWith(AppConstants.educationList, _education),
            (v) => setState(() => _education = v!)),
        _drop('Occupation', _occupation,
            _optsWith(AppConstants.occupationList, _occupation),
            (v) => setState(() => _occupation = v!)),
        _drop('Annual Income', _income,
            _optsWith(AppConstants.incomeList, _income),
            (v) => setState(() => _income = v!)),
      ],
    );
  }
}

class _LocationSheet extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _LocationSheet({required this.profile});
  @override
  ConsumerState<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends ConsumerState<_LocationSheet> {
  late final TextEditingController _city =
      TextEditingController(text: widget.profile.city);
  late String _state = widget.profile.state;
  late String _country =
      widget.profile.country.isEmpty ? 'India' : widget.profile.country;
  double? _lat;
  double? _lng;
  bool _saving = false;

  @override
  void dispose() {
    _city.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final data = {
      'city': _city.text.trim(),
      'state': _state,
      'country': _country,
      // GPS coordinates (when detected via "Use My Location") — stored for
      // future nearby-matching features.
      if (_lat != null) 'latitude': _lat,
      if (_lng != null) 'longitude': _lng,
    };
    final updated = widget.profile.copyWith(
      city: _city.text.trim(),
      state: _state,
      country: _country,
    );
    try {
      await _saveSection(ref, widget.profile, data, updated);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Location updated')));
    } catch (e) {
      debugPrint('[PersonalDetails] location save error: $e');
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _sheetChrome(
      context: context,
      title: 'Edit Location',
      saving: _saving,
      onSave: _save,
      children: [
        UseMyLocationButton(
          label: 'Update My Location',
          onDetected: (loc) => setState(() {
            if (loc.city.isNotEmpty) _city.text = loc.city;
            if (loc.state.isNotEmpty) _state = loc.state;
            if (loc.country.isNotEmpty) _country = loc.country;
            _lat = loc.latitude;
            _lng = loc.longitude;
          }),
        ),
        const SizedBox(height: 14),
        _tf(_city, 'City'),
        _drop('State', _state, _optsWith(AppConstants.indianStates, _state),
            (v) => setState(() => _state = v!)),
        _drop('Country', _country,
            _optsWith(AppConstants.countryList, _country),
            (v) => setState(() => _country = v!)),
      ],
    );
  }
}

class _FamilySheet extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _FamilySheet({required this.profile});
  @override
  ConsumerState<_FamilySheet> createState() => _FamilySheetState();
}

class _FamilySheetState extends ConsumerState<_FamilySheet> {
  late final FamilyDetails _f = widget.profile.family;
  late final TextEditingController _fatherName =
      TextEditingController(text: _f.fatherName);
  late final TextEditingController _fatherOcc =
      TextEditingController(text: _f.fatherOccupation);
  late final TextEditingController _motherName =
      TextEditingController(text: _f.motherName);
  late final TextEditingController _motherOcc =
      TextEditingController(text: _f.motherOccupation);
  late final TextEditingController _brothers =
      TextEditingController(text: _f.brothersCount.toString());
  late final TextEditingController _sisters =
      TextEditingController(text: _f.sistersCount.toString());
  late String _familyType = _f.familyType;
  late String _familyStatus = _f.familyStatus;
  bool _saving = false;

  @override
  void dispose() {
    _fatherName.dispose();
    _fatherOcc.dispose();
    _motherName.dispose();
    _motherOcc.dispose();
    _brothers.dispose();
    _sisters.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final family = FamilyDetails(
      fatherName: _fatherName.text.trim(),
      fatherOccupation: _fatherOcc.text.trim(),
      motherName: _motherName.text.trim(),
      motherOccupation: _motherOcc.text.trim(),
      brothersCount: int.tryParse(_brothers.text.trim()) ?? 0,
      sistersCount: int.tryParse(_sisters.text.trim()) ?? 0,
      familyType: _familyType,
      familyStatus: _familyStatus,
    );
    final data = {'family': family.toMap()};
    final updated = widget.profile.copyWith(family: family);
    try {
      await _saveSection(ref, widget.profile, data, updated);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Family details updated')));
    } catch (e) {
      debugPrint('[PersonalDetails] family save error: $e');
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _sheetChrome(
      context: context,
      title: 'Edit Family Details',
      saving: _saving,
      onSave: _save,
      children: [
        _tf(_fatherName, "Father's Name"),
        _tf(_fatherOcc, "Father's Occupation"),
        _tf(_motherName, "Mother's Name"),
        _tf(_motherOcc, "Mother's Occupation"),
        Row(
          children: [
            Expanded(child: _tf(_brothers, 'Brothers', keyboard: TextInputType.number)),
            const SizedBox(width: 12),
            Expanded(child: _tf(_sisters, 'Sisters', keyboard: TextInputType.number)),
          ],
        ),
        _drop('Family Type', _familyType,
            _optsWith(AppConstants.familyTypeList, _familyType),
            (v) => setState(() => _familyType = v!)),
        _drop('Family Status', _familyStatus,
            _optsWith(AppConstants.familyStatusList, _familyStatus),
            (v) => setState(() => _familyStatus = v!)),
      ],
    );
  }
}

class _AboutSheet extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _AboutSheet({required this.profile});
  @override
  ConsumerState<_AboutSheet> createState() => _AboutSheetState();
}

class _AboutSheetState extends ConsumerState<_AboutSheet> {
  late final TextEditingController _about =
      TextEditingController(text: widget.profile.aboutMe ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _about.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final data = {'aboutMe': _about.text.trim()};
    final updated = widget.profile.copyWith(aboutMe: _about.text.trim());
    try {
      await _saveSection(ref, widget.profile, data, updated);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('About Me updated')));
    } catch (e) {
      debugPrint('[PersonalDetails] about save error: $e');
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _sheetChrome(
      context: context,
      title: 'Edit About Me',
      saving: _saving,
      onSave: _save,
      children: [
        _tf(_about, 'About Me', maxLines: 5),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / error state
// ─────────────────────────────────────────────────────────────────────────────

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.primary.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600])),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
