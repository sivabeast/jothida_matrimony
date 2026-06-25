import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/dev_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_account_model.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/astrologer_session_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/service_providers.dart';
import '../../../widgets/astrologer/working_days_selector.dart';
import '../../../widgets/common/use_my_location_button.dart';
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
  double? _lat;
  double? _lng;
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
    // Persist GPS coordinates too (for nearby-astrologer features) when the
    // location was detected via "Use My Location".
    if (ok && _lat != null && !kBypassAuth) {
      try {
        await ref
            .read(astrologerServiceProvider)
            .updateAccount(a.id, {'latitude': _lat, 'longitude': _lng});
      } catch (_) {/* coordinates are best-effort */}
    }
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
            UseMyLocationButton(
              onDetected: (loc) => setState(() {
                if (loc.city.isNotEmpty) _city.text = loc.city;
                if (loc.state.isNotEmpty) _state.text = loc.state;
                if (loc.country.isNotEmpty) _country.text = loc.country;
                _lat = loc.latitude;
                _lng = loc.longitude;
              }),
            ),
            const SizedBox(height: 14),
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
  late TextEditingController _fee, _availability, _hours, _about;
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
    _about = TextEditingController(text: a?.about ?? '');
    _mode = _modes.contains(a?.consultationMode) ? a!.consultationMode : 'Online';
  }

  @override
  void dispose() {
    _fee.dispose();
    _availability.dispose();
    _hours.dispose();
    _about.dispose();
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
        about: _about.text.trim(),
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
            ProfileTextField(
                controller: _about,
                label: 'About Me',
                hint: 'Your background, approach and the guidance you offer…',
                maxLines: 5),
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

// ════════════════════════ Working Days & Availability ══════════════════════
class AstrologerWorkingDaysScreen extends ConsumerStatefulWidget {
  const AstrologerWorkingDaysScreen({super.key});
  @override
  ConsumerState<AstrologerWorkingDaysScreen> createState() =>
      _WorkingDaysState();
}

class _WorkingDaysState extends ConsumerState<AstrologerWorkingDaysScreen> {
  late Set<String> _days;
  late bool _available;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = ref.read(myAstrologerAccountProvider);
    _days = {...?a?.workingDays};
    _available = a?.manuallyAvailable ?? true;
  }

  Future<void> _save() async {
    final a = ref.read(myAstrologerAccountProvider);
    if (a == null) return;
    setState(() => _saving = true);
    final ok = await _persist(
      context,
      ref,
      a.copyWith(
        workingDays: _days.toList(),
        manuallyAvailable: _available,
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
    // Preview of the resulting status using the same rule as the rest of the
    // app: available only when today is a working day AND the switch is on.
    final worksToday = _days.contains(weekdayName());
    final availableNow = _available && worksToday;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: astrologerSectionAppBar('Working Days'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Manual availability switch ──────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.25)),
            ),
            child: SwitchListTile(
              value: _available,
              activeColor: AppColors.success,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _available = v),
              title: const Text('Accepting bookings',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                _available
                    ? 'You are marked Available'
                    : 'You are marked Not Available',
                style: TextStyle(
                    fontSize: 12,
                    color: _available ? AppColors.success : AppColors.error),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // ── Live status preview ─────────────────────────────────────────
          Row(
            children: [
              Icon(availableNow ? Icons.circle : Icons.circle_outlined,
                  size: 12,
                  color: availableNow ? AppColors.success : AppColors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  availableNow
                      ? 'Status today: Available'
                      : _available
                          ? 'Status today: Not Available (today is a day off)'
                          : 'Status today: Not Available',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Working Days',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            'Users can only book you on your working days. Unchecking a day '
            'shows you as "Not Available Today" to users on that day.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
          ),
          const SizedBox(height: 10),
          WorkingDaysSelector(
            selected: _days,
            onChanged: (days) => setState(() => _days = days),
          ),
          const SizedBox(height: 20),
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
    // Capture the router BEFORE the async gap: signing out tears down the
    // dashboard, so `context` may be unmounted before we navigate.
    final router = GoRouter.of(context);
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
    // Only signs out on explicit confirmation; Cancel / dismiss leaves the
    // session intact.
    if (confirmed != true) return;
    // Clear BOTH the astrologer session and (in real mode) the Firebase auth
    // session so nothing leaks into the next login.
    ref.read(myAstrologerAccountProvider.notifier).signOut();
    if (!kBypassAuth) {
      await ref.read(authNotifierProvider.notifier).signOut();
    }
    // Astrologer → return to the Astrologer login page only (never the
    // role-selection page).
    router.go('/astrologer-login');
  }

  /// Permanently deletes the astrologer account immediately (no admin approval)
  /// and returns to the Login screen with the stack cleared.
  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This action is permanent and cannot be undone.\n'
          'All your astrologer profile, services, certificates, ratings, '
          'reviews and account information will be permanently deleted.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await ref
          .read(accountControllerProvider.notifier)
          .deleteAccount(isAstrologer: true);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // dismiss progress
      context.go('/login');
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(SnackBar(
          content:
              Text('Could not delete your account. Please try again.\n$e')));
    }
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
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.error),
            title: const Text('Delete Account',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w600)),
            subtitle:
                const Text('Permanently delete your account and all data'),
            tileColor: AppColors.error.withOpacity(0.06),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.error.withOpacity(0.25)),
            ),
            onTap: () => _deleteAccount(context, ref),
          ),
        ],
      ),
    );
  }
}
