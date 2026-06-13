import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/dev_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_account_model.dart';
import '../../../providers/astrologer_session_provider.dart';
import '../../../providers/auth_provider.dart';
import 'astrologer_profile_common.dart';

const _genders = ['Male', 'Female', 'Other'];
const _methods = ['Chat', 'Audio Call', 'Video Call', 'In-Person'];
const _languages = [
  'Tamil', 'English', 'Telugu', 'Hindi', 'Malayalam', 'Kannada', 'Marathi'
];
const _modes = ['Online', 'Offline', 'Both'];

/// Shared save helper for the section screens.
Future<bool> _persist(
  BuildContext context,
  WidgetRef ref,
  AstrologerAccount updated,
) async {
  try {
    await ref.read(myAstrologerAccountProvider.notifier).saveAccount(updated);
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save — please try again.')),
      );
    }
    return false;
  }
}

// ════════════════════════ Personal Details ════════════════════════════════
class AstrologerPersonalDetailsScreen extends ConsumerStatefulWidget {
  const AstrologerPersonalDetailsScreen({super.key});
  @override
  ConsumerState<AstrologerPersonalDetailsScreen> createState() =>
      _PersonalState();
}

class _PersonalState extends ConsumerState<AstrologerPersonalDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name, _mobile, _email, _city, _state, _country;
  late String _gender;
  DateTime? _dob;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = ref.read(myAstrologerAccountProvider);
    _name = TextEditingController(text: a?.fullName ?? '');
    _mobile = TextEditingController(text: a?.mobile ?? '');
    _email = TextEditingController(text: a?.email ?? '');
    _city = TextEditingController(text: a?.city ?? '');
    _state = TextEditingController(text: a?.state ?? '');
    _country = TextEditingController(text: a?.country ?? 'India');
    _gender = _genders.contains(a?.gender) ? a!.gender : 'Male';
    _dob = a?.dob;
  }

  @override
  void dispose() {
    for (final c in [_name, _mobile, _email, _city, _state, _country]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final a = ref.read(myAstrologerAccountProvider);
    if (a == null) return;
    setState(() => _saving = true);
    final ok = await _persist(
      context,
      ref,
      a.copyWith(
        fullName: _name.text.trim(),
        gender: _gender,
        dob: _dob,
        mobile: _mobile.text.trim(),
        email: _email.text.trim(),
        city: _city.text.trim(),
        state: _state.text.trim(),
        country: _country.text.trim(),
      ),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: astrologerSectionAppBar('Personal Details'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ProfileTextField(
                controller: _name,
                label: 'Full Name',
                icon: Icons.person_outline,
                requiredField: true),
            ProfileSingleSelect(
                label: 'Gender',
                options: _genders,
                value: _gender,
                onChanged: (v) => setState(() => _gender = v)),
            _dobField(),
            ProfileTextField(
                controller: _mobile,
                label: 'Phone Number',
                icon: Icons.phone_outlined,
                number: true),
            ProfileTextField(
                controller: _email,
                label: 'Email',
                icon: Icons.email_outlined),
            ProfileTextField(
                controller: _city,
                label: 'City',
                icon: Icons.location_city_outlined),
            ProfileTextField(controller: _state, label: 'State'),
            ProfileTextField(controller: _country, label: 'Country'),
            const SizedBox(height: 8),
            ProfileSaveButton(saving: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }

  Widget _dobField() => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _dob ?? DateTime(1990),
              firstDate: DateTime(1940),
              lastDate: DateTime.now(),
            );
            if (picked != null) setState(() => _dob = picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Date of Birth',
              prefixIcon: const Icon(Icons.cake_outlined, size: 20),
              filled: true,
              fillColor: Colors.white,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(
              _dob != null
                  ? '${_dob!.day}/${_dob!.month}/${_dob!.year}'
                  : 'Select date',
              style: TextStyle(
                  color: _dob != null ? Colors.black : Colors.grey[600]),
            ),
          ),
        ),
      );
}

// ════════════════════════ Professional Details ════════════════════════════
class AstrologerProfessionalDetailsScreen extends ConsumerStatefulWidget {
  const AstrologerProfessionalDetailsScreen({super.key});
  @override
  ConsumerState<AstrologerProfessionalDetailsScreen> createState() =>
      _ProfessionalState();
}

class _ProfessionalState
    extends ConsumerState<AstrologerProfessionalDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _experience, _qualification;
  late Set<String> _specializations, _modes2, _langs;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = ref.read(myAstrologerAccountProvider);
    _experience =
        TextEditingController(text: (a?.experienceYears ?? 0).toString());
    _qualification = TextEditingController(text: a?.qualification ?? '');
    _specializations = {...?a?.expertise};
    _modes2 = {...?a?.consultationModes};
    _langs = {...?a?.languages};
  }

  @override
  void dispose() {
    _experience.dispose();
    _qualification.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final a = ref.read(myAstrologerAccountProvider);
    if (a == null) return;
    setState(() => _saving = true);
    final ok = await _persist(
      context,
      ref,
      a.copyWith(
        experienceYears: int.tryParse(_experience.text.trim()) ?? 0,
        qualification: _qualification.text.trim(),
        expertise: _specializations.toList(),
        consultationModes: _modes2.toList(),
        languages: _langs.toList(),
      ),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final specOptions = <String>{
      ...AppConstants.astrologerSpecializations,
      ..._specializations,
    }.toList();
    final langOptions = <String>{..._languages, ..._langs}.toList();

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: astrologerSectionAppBar('Professional Details'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ProfileTextField(
                controller: _experience,
                label: 'Experience (years)',
                icon: Icons.work_history_outlined,
                number: true,
                requiredField: true),
            ProfileTextField(
                controller: _qualification,
                label: 'Qualification',
                hint: 'e.g. Jyotish Acharya, M.A. Astrology',
                icon: Icons.school_outlined),
            ProfileMultiSelect(
                label: 'Specializations',
                options: specOptions,
                selected: _specializations,
                onChanged: (s) => setState(() => _specializations = s)),
            ProfileMultiSelect(
                label: 'Consultation Methods',
                options: _methods,
                selected: _modes2,
                onChanged: (s) => setState(() => _modes2 = s)),
            ProfileMultiSelect(
                label: 'Languages',
                options: langOptions,
                selected: _langs,
                onChanged: (s) => setState(() => _langs = s)),
            const SizedBox(height: 8),
            ProfileSaveButton(saving: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════ Consultation Details ════════════════════════════
class AstrologerConsultationDetailsScreen extends ConsumerStatefulWidget {
  const AstrologerConsultationDetailsScreen({super.key});
  @override
  ConsumerState<AstrologerConsultationDetailsScreen> createState() =>
      _ConsultationState();
}

class _ConsultationState
    extends ConsumerState<AstrologerConsultationDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _fee, _availability, _hours;
  late String _mode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = ref.read(myAstrologerAccountProvider);
    _fee = TextEditingController(
        text: (a?.consultationFee ?? 0).toStringAsFixed(0));
    _availability = TextEditingController(text: a?.availability ?? '');
    _hours = TextEditingController(text: a?.workingHours ?? '');
    _mode = _modes.contains(a?.consultationMode) ? a!.consultationMode : 'Online';
  }

  @override
  void dispose() {
    _fee.dispose();
    _availability.dispose();
    _hours.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final a = ref.read(myAstrologerAccountProvider);
    if (a == null) return;
    setState(() => _saving = true);
    final ok = await _persist(
      context,
      ref,
      a.copyWith(
        consultationFee: double.tryParse(_fee.text.trim()) ?? 0,
        availability: _availability.text.trim(),
        workingHours: _hours.text.trim(),
        consultationMode: _mode,
      ),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: astrologerSectionAppBar('Consultation Details'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ProfileTextField(
                controller: _fee,
                label: 'Consultation Fee (₹)',
                icon: Icons.payments_outlined,
                number: true,
                requiredField: true),
            ProfileTextField(
                controller: _availability,
                label: 'Availability',
                hint: 'e.g. Monday – Saturday',
                icon: Icons.event_available_outlined),
            ProfileTextField(
                controller: _hours,
                label: 'Working Hours',
                hint: 'e.g. 10:00 AM – 6:00 PM',
                icon: Icons.access_time),
            ProfileSingleSelect(
                label: 'Consultation Mode',
                options: _modes,
                value: _mode,
                onChanged: (v) => setState(() => _mode = v)),
            const SizedBox(height: 8),
            ProfileSaveButton(saving: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════ About Me ═════════════════════════════════════════
class AstrologerAboutScreen extends ConsumerStatefulWidget {
  const AstrologerAboutScreen({super.key});
  @override
  ConsumerState<AstrologerAboutScreen> createState() => _AboutState();
}

class _AboutState extends ConsumerState<AstrologerAboutScreen> {
  late TextEditingController _about;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _about = TextEditingController(
        text: ref.read(myAstrologerAccountProvider)?.about ?? '');
  }

  @override
  void dispose() {
    _about.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final a = ref.read(myAstrologerAccountProvider);
    if (a == null) return;
    setState(() => _saving = true);
    final ok = await _persist(context, ref, a.copyWith(about: _about.text.trim()));
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expertise = ref.watch(myAstrologerAccountProvider)?.expertise ?? const [];
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: astrologerSectionAppBar('About Me'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Professional Biography',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ProfileTextField(
            controller: _about,
            label: 'About you & your experience summary',
            hint:
                'Share your background, approach and the kind of guidance you offer…',
            maxLines: 7,
          ),
          if (expertise.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text('Areas of Expertise',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in expertise)
                  Chip(
                    label: Text(e, style: const TextStyle(fontSize: 12)),
                    backgroundColor: AppColors.primary.withOpacity(0.08),
                    side: BorderSide.none,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Edit your areas of expertise under Professional Details.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
          const SizedBox(height: 16),
          ProfileSaveButton(saving: _saving, onPressed: _save),
        ],
      ),
    );
  }
}

// ════════════════════════ Account Settings ════════════════════════════════
class AstrologerAccountSettingsScreen extends ConsumerWidget {
  const AstrologerAccountSettingsScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(myAstrologerAccountProvider.notifier).signOut();
    if (!kBypassAuth) {
      await ref.read(authNotifierProvider.notifier).signOut();
    }
    if (context.mounted) context.go('/account-type');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(myAstrologerAccountProvider);
    final approved = account?.isApproved ?? false;
    final statusColor = approved
        ? AppColors.success
        : account?.status == VerificationStatus.rejected
            ? AppColors.error
            : AppColors.warning;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: astrologerSectionAppBar('Account Settings'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(approved ? Icons.verified : Icons.hourglass_top,
                    color: statusColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Verification Status',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text(account?.status.label ?? 'Pending Verification',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: statusColor)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.error),
            title: const Text('Sign Out',
                style: TextStyle(color: AppColors.error)),
            tileColor: AppColors.error.withOpacity(0.06),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () => _signOut(context, ref),
          ),
        ],
      ),
    );
  }
}
