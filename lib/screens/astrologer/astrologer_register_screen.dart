import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/config/dev_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/data/sample_astrologer_dashboard.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../models/astrologer_account_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/astrologer_session_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/astrologer/working_days_selector.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/location_picker_section.dart';
import '../../widgets/common/searchable_field.dart';

/// Astrologer Profile Setup — shown once, immediately after a successful
/// "Continue with Google" sign-in, for an account that has no
/// `astrologers/{uid}` document yet.
///
/// Authentication is already complete by the time this screen opens: name,
/// email, and profile photo are read straight from the signed-in Firebase
/// user (i.e. the Google account) and are NOT asked for again. This screen
/// only collects astrologer-specific details. On submit, the account is
/// written to Firestore `astrologers/{uid}` with `profileCompleted: true`
/// and the user is taken to the Astrologer Dashboard.
class AstrologerRegisterScreen extends ConsumerStatefulWidget {
  const AstrologerRegisterScreen({super.key});

  @override
  ConsumerState<AstrologerRegisterScreen> createState() =>
      _AstrologerRegisterScreenState();
}

class _AstrologerRegisterScreenState
    extends ConsumerState<AstrologerRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _experienceController = TextEditingController();
  final _aboutController = TextEditingController();
  final _feeController = TextEditingController();
  final _dobText = TextEditingController();

  final _picker = ImagePicker();

  // Pre-filled from the authenticated Google account — never edited via a
  // text field, just displayed for confirmation.
  String _email = '';
  String? _googlePhotoUrl;

  String? _gender;
  String? _country = 'India';
  String? _state;
  String? _city;
  DateTime? _dob;

  final Set<String> _specializations = {};
  final Set<String> _languages = {};
  // Working days default to all 7 — astrologers can narrow this here or later
  // from Settings → Working Days.
  final Set<String> _workingDays = {...kWeekdays};

  File? _pickedPhoto;
  File? _pickedDocument;

  bool _submitting = false;

  static const _languageOptions = [
    'Tamil', 'English', 'Telugu', 'Hindi', 'Kannada', 'Malayalam',
  ];

  @override
  void initState() {
    super.initState();
    // Hydrate name/email/photo from the already-authenticated Google account.
    final user = ref.read(firebaseAuthStreamProvider).valueOrNull;
    _nameController.text = user?.displayName ?? '';
    _email = user?.email ?? '';
    _googlePhotoUrl = user?.photoURL;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _experienceController.dispose();
    _aboutController.dispose();
    _feeController.dispose();
    _dobText.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(1985),
      firstDate: DateTime(1950),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
    );
    if (d != null) {
      setState(() {
        _dob = d;
        _dobText.text = '${d.day}/${d.month}/${d.year}';
      });
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1000);
    if (picked != null) {
      setState(() => _pickedPhoto = File(picked.path));
    }
  }

  Future<void> _pickDocument() async {
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (picked != null) {
      setState(() => _pickedDocument = File(picked.path));
    }
  }

  AstrologerAccount _buildAccount({
    required String id,
    String photoUrl = '',
    String verificationDocUrl = '',
  }) =>
      AstrologerAccount(
        id: id,
        fullName: _nameController.text.trim(),
        gender: _gender ?? '',
        dob: _dob,
        mobile: _phoneController.text.trim(),
        email: _email,
        city: _city ?? '',
        state: _state ?? '',
        country: _country ?? 'India',
        photoUrl: photoUrl,
        experienceYears: int.tryParse(_experienceController.text.trim()) ?? 0,
        expertise: _specializations.toList(),
        languages: _languages.toList(),
        about: _aboutController.text.trim(),
        consultationModes: const ['Chat', 'Audio Call', 'Video Call'],
        certName: '',
        certOrg: '',
        certNumber: '',
        certFileName: verificationDocUrl,
        consultationFee:
            double.tryParse(_feeController.text.trim()) ?? 0,
        workingDays: _workingDays.toList(),
        profileCompleted: true,
        status: VerificationStatus.pending,
        services: defaultAstrologerServices(),
      );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_specializations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select at least one specialization')));
      return;
    }
    if (_languages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select at least one language')));
      return;
    }
    if (_gender == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please select your gender')));
      return;
    }
    if (_dob == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please select your date of birth')));
      return;
    }
    if (_city == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please select your city')));
      return;
    }

    // Demo bypass: create the session locally and open the dashboard.
    if (kBypassAuth) {
      final account = _buildAccount(
        id: 'demo-astrologer',
        photoUrl: _pickedPhoto?.path ?? _googlePhotoUrl ?? '',
      );
      ref.read(myAstrologerAccountProvider.notifier).completeOnboarding(account);
      context.go('/astrologer-dashboard');
      return;
    }

    final uid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please sign in with Google first.')));
      context.go('/login');
      return;
    }

    setState(() => _submitting = true);
    debugPrint('[AstrologerProfileSetup] Submitting profile for uid=$uid '
        '(photo picked: ${_pickedPhoto != null}, '
        'document picked: ${_pickedDocument != null})');
    try {
      final storage = ref.read(storageServiceProvider);

      // Profile photo: keep the Google photo unless the astrologer picked a
      // new one. An upload failure here is non-fatal — fall back to the
      // Google photo so profile creation can still complete.
      String photoUrl = _googlePhotoUrl ?? '';
      if (_pickedPhoto != null) {
        debugPrint('[AstrologerProfileSetup] Uploading profile photo: '
            '${_pickedPhoto!.path}');
        try {
          photoUrl = await storage.updateProfilePhoto(
            userId: uid,
            file: _pickedPhoto!,
            index: 0,
          );
          debugPrint('[AstrologerProfileSetup] Profile photo uploaded: $photoUrl');
        } catch (e, st) {
          debugPrint('[AstrologerProfileSetup] Profile photo upload failed: $e');
          debugPrint(st.toString());
          photoUrl = _googlePhotoUrl ?? '';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
                'Could not upload your new photo, kept your Google photo instead: $e')));
          }
        }
      }

      // Verification document (optional) — also non-fatal on failure.
      String verificationDocUrl = '';
      if (_pickedDocument != null) {
        debugPrint('[AstrologerProfileSetup] Uploading verification document: '
            '${_pickedDocument!.path}');
        try {
          verificationDocUrl = await storage.uploadIdProof(
            userId: uid,
            file: _pickedDocument!,
            docType: 'verification',
          );
          debugPrint('[AstrologerProfileSetup] Verification document uploaded: '
              '$verificationDocUrl');
        } catch (e, st) {
          debugPrint('[AstrologerProfileSetup] Verification document upload '
              'failed: $e');
          debugPrint(st.toString());
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
                'Could not upload your document — you can add it later from your profile: $e')));
          }
        }
      }

      final account = _buildAccount(
        id: uid,
        photoUrl: photoUrl,
        verificationDocUrl: verificationDocUrl,
      );

      debugPrint('[AstrologerProfileSetup] Saving astrologer profile to '
          'Firestore for uid=$uid');
      await ref.read(astrologerServiceProvider).createAccount(uid, account);
      debugPrint('[AstrologerProfileSetup] Firestore write succeeded for '
          'uid=$uid');
      ref.read(myAstrologerAccountProvider.notifier).completeOnboarding(account);
      // The account doc now has role: astrologer — refresh the cached user
      // model so router redirects see the up-to-date role.
      ref.invalidate(currentUserProvider);
      ref.invalidate(authNotifierProvider);

      if (mounted) context.go('/astrologer-dashboard');
    } catch (e, st) {
      debugPrint('[AstrologerProfileSetup] Profile save failed: $e');
      debugPrint(st.toString());
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save your profile: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Complete Your Profile'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Set up your astrologer profile', style: AppTextStyles.heading2),
              const SizedBox(height: 4),
              Text(
                "You're signed in${_email.isNotEmpty ? ' as $_email' : ''}. "
                'Just a few more details to start receiving consultations.',
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 24),
              Center(child: _photoPicker()),
              const SizedBox(height: 28),
              AppTextField(
                controller: _nameController,
                label: 'Full Name',
                hint: 'Your name',
                validator: Validators.name,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _phoneController,
                label: 'Mobile Number',
                hint: '9876543210',
                keyboardType: TextInputType.phone,
                prefixText: '+91 ',
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: Validators.phone,
              ),
              const SizedBox(height: 16),
              SearchableField(
                label: 'Gender',
                isRequired: true,
                items: const ['Male', 'Female', 'Other'],
                selectedItem: _gender,
                onChanged: (v) => setState(() => _gender = v),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _dobText,
                label: 'Date of Birth',
                readOnly: true,
                onTap: _pickDob,
                suffixIcon: const Icon(Icons.calendar_today),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              // ── Country → State → District → City (bundled JSON master data)
              // with a built-in "📍 Use My Location" button. ──
              LocationPickerSection(
                initialCountry: _country,
                initialState: _state,
                initialCity: _city,
                onChanged: (loc) => setState(() {
                  _country = loc.country.isEmpty ? 'India' : loc.country;
                  _state = loc.state.isEmpty ? null : loc.state;
                  _city = loc.city.isEmpty ? null : loc.city;
                }),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _experienceController,
                label: 'Years of Experience',
                hint: 'e.g. 8',
                keyboardType: TextInputType.number,
                maxLength: 2,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Experience is required';
                  final years = int.tryParse(v);
                  if (years == null || years < 0 || years > 70) {
                    return 'Enter valid years of experience';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              _chipGroup('Astrology Specializations',
                  AppConstants.astrologerSpecializations, _specializations),
              const SizedBox(height: 20),
              _chipGroup('Languages Known', _languageOptions, _languages),
              const SizedBox(height: 20),
              Text('Working Days',
                  style: AppTextStyles.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'Select the days you accept consultations. You can change this '
                'anytime from your dashboard.',
                style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              WorkingDaysSelector(
                selected: _workingDays,
                onChanged: (days) => setState(() {
                  _workingDays
                    ..clear()
                    ..addAll(days);
                }),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _feeController,
                label: 'Consultation Fee (₹ per session)',
                hint: 'e.g. 499',
                prefixText: '₹ ',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Consultation fee is required';
                  final fee = int.tryParse(v);
                  if (fee == null || fee < 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _aboutController,
                label: 'About Me',
                hint: 'Brief introduction for users browsing astrologers…',
                maxLines: 4,
                validator: Validators.about,
              ),
              const SizedBox(height: 20),
              Text('Verification Documents (optional)',
                  style: AppTextStyles.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _documentUpload(),
              const SizedBox(height: 32),
              GradientButton(
                onPressed: _submitting ? null : _submit,
                isLoading: _submitting,
                text: 'Save & Go to Dashboard',
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoPicker() => GestureDetector(
        onTap: _pickPhoto,
        child: Stack(
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              backgroundImage: _pickedPhoto != null
                  ? FileImage(_pickedPhoto!) as ImageProvider
                  : (_googlePhotoUrl != null && _googlePhotoUrl!.isNotEmpty)
                      ? CachedNetworkImageProvider(_googlePhotoUrl!)
                      : null,
              child: (_pickedPhoto == null &&
                      (_googlePhotoUrl == null || _googlePhotoUrl!.isEmpty))
                  ? const Icon(Icons.person, size: 44, color: AppColors.primary)
                  : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit, size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      );

  Widget _chipGroup(String label, List<String> options, Set<String> selected) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((o) {
              final isSel = selected.contains(o);
              return FilterChip(
                label: Text(o, style: const TextStyle(fontSize: 12.5)),
                selected: isSel,
                selectedColor: AppColors.primary.withOpacity(0.12),
                checkmarkColor: AppColors.primary,
                onSelected: (sel) => setState(() {
                  sel ? selected.add(o) : selected.remove(o);
                }),
              );
            }).toList(),
          ),
        ],
      );

  Widget _documentUpload() => InkWell(
        onTap: _pickDocument,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _pickedDocument != null ? AppColors.success : Colors.grey,
                style: BorderStyle.solid),
          ),
          child: Column(
            children: [
              Icon(
                _pickedDocument != null ? Icons.check_circle : Icons.upload_file,
                color: _pickedDocument != null ? AppColors.success : AppColors.primary,
                size: 32,
              ),
              const SizedBox(height: 6),
              Text(
                _pickedDocument != null
                    ? 'Document selected — will be uploaded on save'
                    : 'Upload certificate / ID proof (optional)',
                style: TextStyle(
                    color: _pickedDocument != null ? AppColors.success : Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}
