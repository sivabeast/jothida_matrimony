import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/aadhaar_details.dart';
import '../../models/profile_model.dart';
import '../../providers/notification_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/location_picker_section.dart';
import '../../widgets/common/network_photo.dart';
import '../../widgets/common/searchable_field.dart';

/// Admin → Edit User Profile — the admin-side editor whose changes flow
/// straight to the user app (the user's own profile is a LIVE snapshot
/// stream, so every save here appears immediately — no re-login needed).
///
/// Editable: profile details, horoscope details (+ horoscope PDF upload),
/// contact details, location, profile photo, Aadhaar verification and
/// partner preferences. Saving also drops an in-app "Profile updated by
/// admin" notification for the user.
class AdminEditUserScreen extends ConsumerStatefulWidget {
  final String uid;
  const AdminEditUserScreen({super.key, required this.uid});

  @override
  ConsumerState<AdminEditUserScreen> createState() =>
      _AdminEditUserScreenState();
}

class _AdminEditUserScreenState extends ConsumerState<AdminEditUserScreen> {
  ProfileModel? _profile;
  AadhaarDetails? _aadhaar;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  bool _uploadingPdf = false;

  final _c = <String, TextEditingController>{};
  String? _gender, _maritalStatus, _height;
  String? _rasi, _nakshatra, _lagnam;
  String _state = '', _district = '', _city = '';
  String _stateId = '', _districtId = '', _cityId = '';
  double? _lat, _lng;
  String _photoUrl = '';
  String _horoscopePdfUrl = '';

  TextEditingController _ctrl(String key, [String initial = '']) =>
      _c.putIfAbsent(key, () => TextEditingController(text: initial));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final svc = ref.read(firestoreServiceProvider);
      final profile = await svc.getProfileByUserId(widget.uid);
      AadhaarDetails? aadhaar;
      try {
        aadhaar = await svc.getAadhaar(widget.uid);
      } catch (_) {/* record may not exist */}
      ContactDetails? contact;
      try {
        contact = await svc.getContact(widget.uid);
      } catch (_) {/* contact may not exist */}

      if (!mounted) return;
      if (profile != null) {
        final p = profile;
        _ctrl('fullName', p.fullName);
        _ctrl('education', p.education);
        _ctrl('occupation', p.occupation);
        _ctrl('annualIncome', p.annualIncome);
        _ctrl('aboutMe', p.aboutMe ?? '');
        _ctrl('nativePlace', p.nativePlace ?? '');
        _ctrl('birthTime', p.horoscope.birthTime);
        _ctrl('birthPlace', p.horoscope.birthPlace);
        _ctrl('dosham', p.horoscope.dosham);
        _ctrl('mobile', contact?.mobileNumber ?? '');
        _ctrl('whatsapp', contact?.whatsappNumber ?? '');
        _ctrl('contactPerson', contact?.contactPersonName ?? '');
        _ctrl('ppMinAge', '${p.partnerPreferences.minAge}');
        _ctrl('ppMaxAge', '${p.partnerPreferences.maxAge}');
        _ctrl('ppReligion', p.partnerPreferences.religion);
        _ctrl('ppCaste', p.partnerPreferences.caste ?? '');
        _gender = p.gender.isEmpty ? null : p.gender;
        _maritalStatus = p.maritalStatus.isEmpty ? null : p.maritalStatus;
        _height =
            AppConstants.heightList.contains(p.height) ? p.height : null;
        _rasi =
            AppConstants.rasiList.contains(p.horoscope.rasi) ? p.horoscope.rasi : null;
        _nakshatra = AppConstants.nakshatraList.contains(p.horoscope.nakshatra)
            ? p.horoscope.nakshatra
            : null;
        _lagnam = AppConstants.lagnamList.contains(p.horoscope.lagnam)
            ? p.horoscope.lagnam
            : null;
        _state = p.state;
        _stateId = p.stateId;
        _district = p.district;
        _districtId = p.districtId;
        _city = p.city;
        _cityId = p.cityId;
        _lat = p.latitude;
        _lng = p.longitude;
        _photoUrl = p.profilePhotoUrl ?? '';
        _horoscopePdfUrl = p.horoscope.horoscopePdfUrl ?? '';
      }
      setState(() {
        _profile = profile;
        _aadhaar = aadhaar;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Could not load the profile: $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // ── Media uploads ──────────────────────────────────────────────────────────
  Future<void> _replacePhoto() async {
    final p = _profile;
    if (p == null || _uploadingPhoto) return;
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1200);
    if (picked == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final url = await ref.read(profileRepositoryProvider).updateProfilePhoto(
            userId: p.userId,
            profileId: p.id,
            file: File(picked.path),
            index: 0,
            currentPhotos: p.photos,
          );
      if (!mounted) return;
      setState(() => _photoUrl = url);
      _snack('Profile photo updated.');
    } catch (e) {
      _snack('Photo upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _uploadHoroscopePdf() async {
    final p = _profile;
    if (p == null || _uploadingPdf) return;
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 90, maxWidth: 2000);
    if (picked == null) return;
    setState(() => _uploadingPdf = true);
    try {
      // Uploaded as a horoscope document (image); PDFs can also be attached by
      // the user from Horoscope Files — this covers the admin "upload
      // horoscope" action.
      final url = await ref.read(profileRepositoryProvider).uploadHoroscopeDoc(
          userId: p.userId, file: File(picked.path), isPdf: false);
      await ref.read(profileRepositoryProvider).updateProfile(p.id, {
        'horoscope.horoscopeImages': [...p.horoscope.horoscopeImages, url],
      });
      if (!mounted) return;
      setState(() => _horoscopePdfUrl = url);
      _snack('Horoscope document uploaded.');
    } catch (e) {
      _snack('Horoscope upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploadingPdf = false);
    }
  }

  // ── Aadhaar verification ───────────────────────────────────────────────────
  Future<void> _setAadhaarVerified(bool verified) async {
    final p = _profile;
    if (p == null) return;
    try {
      await ref.read(firestoreServiceProvider).setAadhaarVerified(
          userId: widget.uid, profileId: p.id, verified: verified);
      if (!mounted) return;
      setState(() => _aadhaar = AadhaarDetails(
            userId: widget.uid,
            number: _aadhaar?.number ?? '',
            frontUrl: _aadhaar?.frontUrl ?? '',
            backUrl: _aadhaar?.backUrl ?? '',
            verified: verified,
          ));
      _snack(verified
          ? 'Aadhaar verified — the profile now shows the Verified badge.'
          : 'Aadhaar verification removed.');
    } catch (e) {
      _snack('Could not update verification: $e');
    }
  }

  // ── Save ───────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    final p = _profile;
    if (p == null || _saving) return;
    setState(() => _saving = true);
    try {
      String t(String k) => _ctrl(k).text.trim();
      final updates = <String, dynamic>{
        'fullName': t('fullName'),
        if (_gender != null) 'gender': _gender,
        if (_height != null) 'height': _height,
        if (_maritalStatus != null) 'maritalStatus': _maritalStatus,
        'education': t('education'),
        'occupation': t('occupation'),
        'annualIncome': t('annualIncome'),
        'aboutMe': t('aboutMe'),
        'nativePlace': t('nativePlace'),
        // Location (names + ids, mirroring the profile write shape).
        'state': _state, 'stateId': _stateId, 'stateName': _state,
        'district': _district, 'districtId': _districtId,
        'districtName': _district,
        'city': _city, 'cityId': _cityId, 'cityName': _city,
        'latitude': _lat, 'longitude': _lng,
        // Horoscope.
        if (_rasi != null) 'horoscope.rasi': _rasi,
        if (_nakshatra != null) 'horoscope.nakshatra': _nakshatra,
        if (_lagnam != null) 'horoscope.lagnam': _lagnam,
        'horoscope.birthTime': t('birthTime'),
        'horoscope.birthPlace': t('birthPlace'),
        'horoscope.dosham': t('dosham'),
        // Partner preferences.
        'partnerPreferences.minAge':
            int.tryParse(t('ppMinAge')) ?? p.partnerPreferences.minAge,
        'partnerPreferences.maxAge':
            int.tryParse(t('ppMaxAge')) ?? p.partnerPreferences.maxAge,
        'partnerPreferences.religion': t('ppReligion'),
        'partnerPreferences.caste': t('ppCaste'),
        'updatedAt': DateTime.now(),
      };
      await ref.read(profileRepositoryProvider).updateProfile(p.id, updates);

      // Contact details live in the gated contacts/{uid} collection.
      await ref.read(firestoreServiceProvider).saveContact(
            widget.uid,
            ContactDetails(
              contactPersonName: t('contactPerson'),
              relationship: 'Self',
              mobileNumber: t('mobile'),
              whatsappNumber: t('whatsapp').isEmpty ? null : t('whatsapp'),
            ),
          );

      // Tell the user their profile was updated by the admin (best-effort).
      await ref.read(notificationNotifierProvider.notifier).notify(
            toUid: widget.uid,
            event: AppNotificationEvent.adminProfileUpdate,
          );

      if (!mounted) return;
      _snack('Profile saved. Changes are live in the user app.');
      Navigator.of(context).pop();
    } catch (e) {
      _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Edit User Profile'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _profile == null
              ? const Center(
                  child: Text('This user has no matrimony profile yet.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _photoCard(),
                    const SizedBox(height: 14),
                    _card('👤 Profile Details', [
                      _text('fullName', 'Full Name'),
                      _dropdown(
                          'Gender',
                          const ['Male', 'Female'],
                          _gender,
                          (v) => setState(() => _gender = v)),
                      _dropdown('Height', AppConstants.heightList, _height,
                          (v) => setState(() => _height = v)),
                      _dropdown('Marital Status',
                          AppConstants.maritalStatusOptions, _maritalStatus,
                          (v) => setState(() => _maritalStatus = v)),
                      _text('education', 'Education'),
                      _text('occupation', 'Occupation'),
                      _text('annualIncome', 'Annual Income'),
                      _text('aboutMe', 'About', maxLines: 3),
                    ]),
                    const SizedBox(height: 14),
                    _card('📍 Location', [
                      LocationPickerSection(
                        initialState: _state,
                        initialDistrict: _district,
                        initialCity: _city,
                        initialLatitude: _lat,
                        initialLongitude: _lng,
                        isRequired: false,
                        onChanged: (loc) {
                          _state = loc.state;
                          _stateId = loc.stateId;
                          _district = loc.district;
                          _districtId = loc.districtId;
                          _city = loc.city;
                          _cityId = loc.cityId;
                          _lat = loc.latitude;
                          _lng = loc.longitude;
                        },
                      ),
                      _text('nativePlace', 'Native Place'),
                    ]),
                    const SizedBox(height: 14),
                    _card('🔮 Horoscope Details', [
                      _dropdown('Rasi', AppConstants.rasiList, _rasi,
                          (v) => setState(() => _rasi = v)),
                      _dropdown('Nakshatra', AppConstants.nakshatraList,
                          _nakshatra, (v) => setState(() => _nakshatra = v)),
                      _dropdown('Lagnam', AppConstants.lagnamList, _lagnam,
                          (v) => setState(() => _lagnam = v)),
                      _text('birthTime', 'Birth Time'),
                      _text('birthPlace', 'Birth Place'),
                      _text('dosham', 'Dosham'),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: _uploadingPdf ? null : _uploadHoroscopePdf,
                        icon: _uploadingPdf
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.upload_file, size: 18),
                        label: Text(_horoscopePdfUrl.isEmpty
                            ? 'Upload Horoscope Document'
                            : 'Replace Horoscope Document'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary)),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    _card('📞 Contact Details', [
                      _text('contactPerson', 'Contact Person'),
                      _text('mobile', 'Mobile Number',
                          keyboard: TextInputType.phone),
                      _text('whatsapp', 'WhatsApp Number',
                          keyboard: TextInputType.phone),
                    ]),
                    const SizedBox(height: 14),
                    _aadhaarCard(),
                    const SizedBox(height: 14),
                    _card('💞 Partner Preferences', [
                      Row(children: [
                        Expanded(
                            child: _text('ppMinAge', 'Min Age',
                                keyboard: TextInputType.number,
                                digitsOnly: true)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _text('ppMaxAge', 'Max Age',
                                keyboard: TextInputType.number,
                                digitsOnly: true)),
                      ]),
                      _text('ppReligion', 'Preferred Religion'),
                      _text('ppCaste', 'Preferred Caste'),
                    ]),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving…' : 'Save Changes'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
    );
  }

  // ── Section widgets ────────────────────────────────────────────────────────
  Widget _photoCard() => _card('🖼️ Profile Photo', [
        Center(
          child: Column(children: [
            Container(
              width: 140,
              height: 170,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: _photoUrl.isEmpty
                  ? const Icon(Icons.person, size: 56, color: Colors.grey)
                  : NetworkPhoto(url: _photoUrl, fit: BoxFit.cover),
            ),
            TextButton.icon(
              onPressed: _uploadingPhoto ? null : _replacePhoto,
              icon: _uploadingPhoto
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Replace Photo'),
              style:
                  TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ]),
        ),
      ]);

  Widget _aadhaarCard() {
    final a = _aadhaar;
    return _card('🪪 Aadhaar Verification', [
      if (a == null || !a.isSubmitted)
        Text('The user has not submitted Aadhaar details yet.',
            style: TextStyle(color: Colors.grey[600], fontSize: 13))
      else ...[
        Row(children: [
          Expanded(
            child: Text('Aadhaar Number: ${a.masked}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (a.verified ? AppColors.success : AppColors.warning)
                  .withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(a.verified ? 'VERIFIED' : 'PENDING',
                style: TextStyle(
                    color:
                        a.verified ? AppColors.success : AppColors.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _aadhaarImage('Front', a.frontUrl)),
          const SizedBox(width: 10),
          Expanded(child: _aadhaarImage('Back', a.backUrl)),
        ]),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Aadhaar Verified',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: const Text(
              'Verifying also shows the "Verified" badge on the profile.',
              style: TextStyle(fontSize: 12)),
          value: a.verified,
          activeColor: AppColors.success,
          onChanged: _setAadhaarVerified,
        ),
      ],
    ]);
  }

  Widget _aadhaarImage(String label, String url) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Container(
            height: 110,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: url.isEmpty
                ? const Center(
                    child: Icon(Icons.image_not_supported_outlined,
                        color: Colors.grey))
                : NetworkPhoto(url: url, fit: BoxFit.cover),
          ),
        ],
      );

  Widget _card(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _text(String key, String label,
          {int maxLines = 1,
          TextInputType? keyboard,
          bool digitsOnly = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _ctrl(key),
          maxLines: maxLines,
          keyboardType: keyboard,
          inputFormatters:
              digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            filled: true,
            fillColor: Colors.grey[50],
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

  Widget _dropdown(String label, List<String> items, String? value,
          ValueChanged<String?> onChanged) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SearchableField(
          label: label,
          items: items,
          selectedItem: value,
          onChanged: onChanged,
        ),
      );
}
