import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/data/sample_astrologer_dashboard.dart';
import '../../core/data/selection_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';
import '../../models/astrologer_account_model.dart';
import '../../providers/astrologer_session_provider.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/searchable_field.dart';

/// First-time astrologer onboarding. Must be completed before the dashboard
/// is accessible. Certificate submission is mandatory; the resulting account
/// starts as "Pending Verification" until an admin approves it.
class AstrologerOnboardingScreen extends ConsumerStatefulWidget {
  const AstrologerOnboardingScreen({super.key});

  @override
  ConsumerState<AstrologerOnboardingScreen> createState() =>
      _AstrologerOnboardingScreenState();
}

class _AstrologerOnboardingScreenState
    extends ConsumerState<AstrologerOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _experience = TextEditingController();
  final _about = TextEditingController();
  final _certName = TextEditingController();
  final _certOrg = TextEditingController();
  final _certNumber = TextEditingController();

  String? _gender;
  String? _country = 'India';
  String? _state;
  String? _city;
  DateTime? _dob;
  final _dobText = TextEditingController();
  final Set<String> _expertise = {};
  final Set<String> _languages = {};
  final Set<String> _modes = {};
  String? _certFileName;

  static const _expertiseOptions = [
    'Marriage Matching', 'Porutham', 'Jathagam', 'Horoscope Matching',
    'Career', 'Dosha Analysis', 'Numerology', 'Muhurtham', 'General Astrology',
  ];
  static const _languageOptions = [
    'Tamil', 'English', 'Telugu', 'Hindi', 'Kannada', 'Malayalam',
  ];
  static const _modeOptions = ['Chat', 'Audio Call', 'Video Call', 'In-Person'];

  @override
  void dispose() {
    for (final c in [
      _name, _mobile, _email, _experience, _about, _certName, _certOrg,
      _certNumber, _dobText
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDob() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(1985),
      firstDate: DateTime(1950),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 21)),
    );
    if (d != null) {
      setState(() {
        _dob = d;
        _dobText.text = '${d.day}/${d.month}/${d.year}';
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final missing = <String>[];
    if (_gender == null) missing.add('Gender');
    if (_dob == null) missing.add('Date of Birth');
    if (_city == null) missing.add('City');
    if (_expertise.isEmpty) missing.add('Areas of Expertise');
    if (_languages.isEmpty) missing.add('Languages');
    if (_modes.isEmpty) missing.add('Consultation Mode');
    if (_certFileName == null) missing.add('Certificate upload');
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please complete: ${missing.join(', ')}')),
      );
      return;
    }

    final account = AstrologerAccount(
      id: 'astro_me',
      fullName: _name.text.trim(),
      gender: _gender!,
      dob: _dob,
      mobile: _mobile.text.trim(),
      email: _email.text.trim(),
      city: _city!,
      state: _state ?? '',
      country: _country ?? 'India',
      experienceYears: int.tryParse(_experience.text.trim()) ?? 0,
      expertise: _expertise.toList(),
      languages: _languages.toList(),
      about: _about.text.trim(),
      consultationModes: _modes.toList(),
      certName: _certName.text.trim(),
      certOrg: _certOrg.text.trim(),
      certNumber: _certNumber.text.trim(),
      certFileName: _certFileName!,
      status: VerificationStatus.pending,
      services: defaultAstrologerServices(),
      rating: 0,
      reviewCount: 0,
    );
    ref.read(myAstrologerAccountProvider.notifier).completeOnboarding(account);
    context.go('/astrologer/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Astrologer Onboarding'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _banner(),
            _section('Basic Information'),
            AppTextField(controller: _name, label: 'Full Name *', validator: Validators.name),
            const SizedBox(height: 14),
            SearchableField(
              label: 'Gender',
              isRequired: true,
              items: const ['Male', 'Female', 'Other'],
              selectedItem: _gender,
              onChanged: (v) => setState(() => _gender = v),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _dobText,
              label: 'Date of Birth *',
              readOnly: true,
              onTap: _pickDob,
              suffixIcon: const Icon(Icons.calendar_today),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _mobile,
              label: 'Mobile Number *',
              prefixText: '+91 ',
              keyboardType: TextInputType.number,
              maxLength: 10,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              validator: Validators.phone,
            ),
            AppTextField(
                controller: _email, label: 'Email *', validator: Validators.email),
            const SizedBox(height: 14),
            SearchableField(
              label: 'Country',
              isRequired: true,
              items: SelectionData.countries,
              selectedItem: _country,
              onChanged: (v) => setState(() {
                _country = v;
                _state = null;
                _city = null;
              }),
            ),
            const SizedBox(height: 14),
            SearchableField(
              label: 'State',
              items: _country == 'India'
                  ? SelectionData.indianStates
                  : const ['Other'],
              selectedItem: _state,
              onChanged: (v) => setState(() {
                _state = v;
                _city = null;
              }),
            ),
            const SizedBox(height: 14),
            SearchableField(
              label: 'City',
              isRequired: true,
              items: SelectionData.citiesFor(_state),
              selectedItem: _city,
              enabled: _state != null,
              onChanged: (v) => setState(() => _city = v),
            ),
            _section('Professional Information'),
            AppTextField(
              controller: _experience,
              label: 'Years of Experience *',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            _chipGroup('Areas of Expertise *', _expertiseOptions, _expertise),
            const SizedBox(height: 14),
            _chipGroup('Languages Known *', _languageOptions, _languages),
            const SizedBox(height: 14),
            _chipGroup('Consultation Mode *', _modeOptions, _modes),
            const SizedBox(height: 14),
            AppTextField(
              controller: _about,
              label: 'About Me',
              hint: 'Brief introduction…',
              maxLines: 3,
            ),
            _section('Certification (Mandatory)'),
            AppTextField(controller: _certName, label: 'Certification Name *',
                validator: (v) => v == null || v.isEmpty ? 'Required' : null),
            const SizedBox(height: 14),
            AppTextField(controller: _certOrg, label: 'Issuing Organization *',
                validator: (v) => v == null || v.isEmpty ? 'Required' : null),
            const SizedBox(height: 14),
            AppTextField(controller: _certNumber, label: 'Certificate Number *',
                validator: (v) => v == null || v.isEmpty ? 'Required' : null),
            const SizedBox(height: 14),
            _certUpload(),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Submit for Verification'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _banner() => Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.gold.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.gold.withOpacity(0.5)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.goldDark),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Complete your profile to start. Your account stays "Pending '
                'Verification" until an admin approves your certificate.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
      );

  Widget _chipGroup(String label, List<String> options, Set<String> selected) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: options.map((o) {
              final isSel = selected.contains(o);
              return FilterChip(
                label: Text(o),
                selected: isSel,
                onSelected: (_) => setState(() {
                  isSel ? selected.remove(o) : selected.add(o);
                }),
                selectedColor: AppColors.primary.withOpacity(0.15),
                checkmarkColor: AppColors.primary,
              );
            }).toList(),
          ),
        ],
      );

  Widget _certUpload() => InkWell(
        // TODO(upload): wire to image_picker / file_picker + Firebase Storage.
        onTap: () => setState(() => _certFileName = 'certificate_${DateTime.now().millisecondsSinceEpoch}.pdf'),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _certFileName != null ? AppColors.success : Colors.grey,
                style: BorderStyle.solid),
          ),
          child: Column(
            children: [
              Icon(
                _certFileName != null ? Icons.check_circle : Icons.upload_file,
                color: _certFileName != null ? AppColors.success : AppColors.primary,
                size: 32,
              ),
              const SizedBox(height: 6),
              Text(
                _certFileName ?? 'Upload Certificate (Image / PDF) *',
                style: TextStyle(
                    color: _certFileName != null ? AppColors.success : Colors.grey[700]),
              ),
            ],
          ),
        ),
      );
}
