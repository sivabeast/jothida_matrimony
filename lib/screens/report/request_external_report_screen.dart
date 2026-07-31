import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/services/master_astrology_data.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/location_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/network_photo.dart';
import '../../widgets/common/searchable_field.dart';
import '../../widgets/common/searchable_with_others_field.dart';

/// Spec §4 — **Request New Horoscope Report** (external).
///
/// Lets a signed-in user request a Horoscope Compatibility Report between
/// themselves (details auto-filled from their profile) and a SECOND person who
/// is NOT registered in the app (details entered manually + a horoscope
/// image/PDF uploaded here). After payment the request is created as a paid
/// `matching` request tagged `externalRequest`, auto-assigned to an employee,
/// and tracked on the user's Reports page exactly like an internal report.
///
/// Second-person input rules (spec §1):
///   * Gender is auto-set to the opposite of the logged-in user's gender and is
///     read-only.
///   * Age is derived from the Date of Birth and is read-only.
///   * Place of Birth reuses the profile-creation searchable city picker.
///   * Nakshatra / Rasi are searchable dropdowns backed by the master astrology
///     data.
///   * Name, DOB, Time of Birth, Place, Nakshatra and Rasi are required; the
///     horoscope image/PDF is optional.
class RequestExternalReportScreen extends ConsumerStatefulWidget {
  const RequestExternalReportScreen({super.key});

  @override
  ConsumerState<RequestExternalReportScreen> createState() =>
      _RequestExternalReportScreenState();
}

class _RequestExternalReportScreenState
    extends ConsumerState<RequestExternalReportScreen> {
  final _formKey = GlobalKey<FormState>();

  // Second-person fields.
  final _name = TextEditingController();
  final _tob = TextEditingController();
  String? _place; // city name or a custom "Others" value
  String? _nakshatra;
  String? _rasi;
  DateTime? _dob;

  // Master astrology option lists (searchable Nakshatra / Rasi).
  List<String> _rasiOptions = const [];
  List<String> _nakOptions = const [];

  // Second-person uploaded horoscope.
  String _otherImageUrl = '';
  String _otherPdfUrl = '';
  bool _uploading = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadMasterOptions();
  }

  @override
  void dispose() {
    _name.dispose();
    _tob.dispose();
    super.dispose();
  }

  Future<void> _loadMasterOptions() async {
    final m = await MasterAstrologyData.load();
    if (!mounted) return;
    setState(() {
      _rasiOptions = m.rasis.map((e) => e.nameTamil).toList();
      _nakOptions = m.nakshatras.map((e) => e.nameTamil).toList();
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // ── Derived values ─────────────────────────────────────────────────────────

  /// The second person is always the opposite gender to the logged-in user.
  /// Falls back to Female when the user's gender is unknown (still read-only).
  String _lockedGender(ProfileModel? me) {
    final g = (me?.gender ?? '').trim().toLowerCase();
    if (g == 'male') return 'Female';
    if (g == 'female') return 'Male';
    return 'Female';
  }

  int _ageFromDob(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age < 0 ? 0 : age;
  }

  // ── Build the requester (self) details from the profile ──────────────────
  Map<String, dynamic> _requesterMap(ProfileModel? me) {
    final h = me?.horoscope;
    return {
      'name': me?.fullName ?? '',
      'age': me?.age ?? 0,
      'gender': me?.gender ?? '',
      'dob': me == null ? '' : DateFormat('dd MMM yyyy').format(me.dateOfBirth),
      'tob': h?.birthTime ?? '',
      'place': (h?.birthPlace.trim().isNotEmpty ?? false)
          ? h!.birthPlace
          : (me == null
              ? ''
              : [me.city, me.state].where((s) => s.trim().isNotEmpty).join(', ')),
      'nakshatra': h?.nakshatra ?? '',
      'rasi': h?.rasi ?? '',
      'horoscopeImageUrl':
          (h?.horoscopeImages.isNotEmpty ?? false) ? h!.horoscopeImages.first : '',
      'horoscopePdfUrl':
          (h?.horoscopePdfUrls.isNotEmpty ?? false) ? h!.horoscopePdfUrls.first : '',
    };
  }

  Map<String, dynamic> _otherMap(ProfileModel? me) => {
        'name': _name.text.trim(),
        'age': _dob == null ? 0 : _ageFromDob(_dob!),
        'gender': _lockedGender(me),
        'dob': _dob == null ? '' : DateFormat('dd MMM yyyy').format(_dob!),
        'tob': _tob.text.trim(),
        'place': (_place ?? '').trim(),
        'nakshatra': (_nakshatra ?? '').trim(),
        'rasi': (_rasi ?? '').trim(),
        'horoscopeImageUrl': _otherImageUrl,
        'horoscopePdfUrl': _otherPdfUrl,
      };

  // ── Uploads (reuse the generic attachment uploader) ──────────────────────
  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    await _upload(File(picked.path), isImage: true);
  }

  Future<void> _pickPdf() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = res?.files.single.path;
    if (path == null) return;
    await _upload(File(path), isImage: false);
  }

  Future<void> _upload(File file, {required bool isImage}) async {
    setState(() => _uploading = true);
    try {
      final url = await ref.read(storageServiceProvider).uploadChatAttachment(
          threadId: 'external_report_media', file: file, isImage: isImage);
      if (!mounted) return;
      setState(() {
        if (isImage) {
          _otherImageUrl = url;
        } else {
          _otherPdfUrl = url;
        }
      });
    } catch (_) {
      _snack('Upload failed — please try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1940),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _pickTob() async {
    final picked = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 6, minute: 0));
    if (picked != null && mounted) {
      setState(() => _tob.text = picked.format(context));
    }
  }

  // ── Pay + create ──────────────────────────────────────────────────────────
  void _payAndRequest() {
    if (_busy) return;
    // Field-level (Name, Place, Nakshatra, Rasi) validation.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Picker fields are not FormFields, so validate them explicitly.
    if (_dob == null) {
      _snack('Please select the second person\'s date of birth.');
      return;
    }
    if (_tob.text.trim().isEmpty) {
      _snack('Please select the second person\'s time of birth.');
      return;
    }
    if ((_place ?? '').trim().isEmpty) {
      _snack('Please select the second person\'s place of birth.');
      return;
    }
    if ((_nakshatra ?? '').trim().isEmpty) {
      _snack('Please select the second person\'s Nakshatra.');
      return;
    }
    if ((_rasi ?? '').trim().isEmpty) {
      _snack('Please select the second person\'s Rasi.');
      return;
    }
    setState(() => _busy = true);
    // No in-app payment (Razorpay removed) — create the request directly. It is
    // auto-assigned for verification, same as the internal report flow.
    _createRequest(
      amount: 0,
      note: 'Requested in-app (no online payment) — assigned for verification.',
    );
  }

  Future<void> _createRequest({
    required int amount,
    String? paymentId,
    String note = '',
  }) async {
    final me = ref.read(myProfileProvider).valueOrNull;
    try {
      final id =
          await ref.read(matchAnalysisControllerProvider.notifier).requestExternalReport(
                requester: _requesterMap(me),
                other: _otherMap(me),
                amount: amount,
                paymentId: paymentId,
                note: note,
              );
      if (!mounted) return;
      _snack('Request #$id has been submitted — track it on the Reports tab.');
      ref.read(homeTabIndexProvider.notifier).state = kReportsTabIndex;
      context.go('/home');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Could not create the request. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(myProfileProvider).valueOrNull;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Request New Horoscope Report'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _intro(),
            const SizedBox(height: 14),
            _selfCard(me),
            const SizedBox(height: 14),
            _otherCard(me),
            const SizedBox(height: 16),
          ],
        ),
      ),
      bottomNavigationBar: _payBar(),
    );
  }

  Widget _intro() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.description_outlined, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text('Compatibility report with anyone',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            SizedBox(height: 8),
            Text(
              'Get a professional horoscope compatibility report between you and '
              'a person who is not on the app. Your details are filled in '
              'automatically — just add the second person\'s details below.',
              style: TextStyle(color: Colors.white, fontSize: 12.5, height: 1.5),
            ),
          ],
        ),
      );

  // ── Your (auto-filled) details ────────────────────────────────────────────
  Widget _selfCard(ProfileModel? me) {
    final h = me?.horoscope;
    final hasHoro = (h?.horoscopeImages.isNotEmpty ?? false) ||
        (h?.horoscopePdfUrls.isNotEmpty ?? false);
    return _card('Your Details (auto-filled)', Icons.person_outline, [
      if (me == null)
        const Text('Your profile is still loading…',
            style: TextStyle(color: Colors.grey))
      else ...[
        _readRow('Name', me.fullName),
        _readRow('Age', me.age > 0 ? '${me.age}' : '—'),
        _readRow('Gender', me.gender),
        _readRow('Date of Birth',
            DateFormat('dd MMM yyyy').format(me.dateOfBirth)),
        _readRow('Time of Birth', h?.birthTime ?? ''),
        _readRow(
            'Place of Birth',
            (h?.birthPlace.trim().isNotEmpty ?? false)
                ? h!.birthPlace
                : [me.city, me.state]
                    .where((s) => s.trim().isNotEmpty)
                    .join(', ')),
        _readRow('Nakshatra', h?.nakshatra ?? ''),
        _readRow('Rasi', h?.rasi ?? ''),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(hasHoro ? Icons.check_circle : Icons.info_outline,
                size: 16,
                color: hasHoro ? AppColors.success : Colors.grey),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                hasHoro
                    ? 'Your horoscope document will be attached automatically.'
                    : 'No horoscope document on your profile — the employee will '
                        'use the details above.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      ],
    ]);
  }

  // ── Second person (manual) details ────────────────────────────────────────
  Widget _otherCard(ProfileModel? me) {
    final lockedGender = _lockedGender(me);
    final ageText = _dob == null ? '—' : '${_ageFromDob(_dob!)}';
    return _card('Second Person\'s Details', Icons.person_add_alt_1_outlined, [
      TextFormField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: _dec('Full name *'),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Name is required' : null,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          // Age is derived from the DOB below and cannot be edited.
          Expanded(child: _readOnlyBox('Age', ageText, Icons.cake_outlined)),
          const SizedBox(width: 10),
          // Gender is auto-set to the opposite of the logged-in user.
          Expanded(
              child: _readOnlyBox('Gender', lockedGender, Icons.wc_outlined)),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        'Gender is set automatically to the opposite of your gender. Age is '
        'calculated from the date of birth.',
        style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: _pickerField('Date of Birth *',
              _dob == null ? '' : DateFormat('dd MMM yyyy').format(_dob!),
              Icons.calendar_today_outlined, _pickDob)),
          const SizedBox(width: 10),
          Expanded(child: _pickerField('Time of Birth *', _tob.text,
              Icons.schedule, _pickTob)),
        ],
      ),
      const SizedBox(height: 12),
      // Place of Birth — same searchable city picker as profile creation, with
      // an "Others" fallback for places not in the database.
      _placeField(),
      const SizedBox(height: 12),
      // Nakshatra / Rasi — searchable dropdowns backed by the master data.
      SearchableField(
        label: 'Nakshatra',
        isRequired: true,
        items: _nakOptions,
        selectedItem: _nakshatra,
        prefixIcon: Icons.auto_awesome_outlined,
        popupMode: SearchablePopupMode.modalBottomSheet,
        onChanged: (v) => setState(() => _nakshatra = v),
      ),
      const SizedBox(height: 12),
      SearchableField(
        label: 'Rasi',
        isRequired: true,
        items: _rasiOptions,
        selectedItem: _rasi,
        prefixIcon: Icons.brightness_3_outlined,
        popupMode: SearchablePopupMode.modalBottomSheet,
        onChanged: (v) => setState(() => _rasi = v),
      ),
      const SizedBox(height: 14),
      const Text('Horoscope Image / PDF (optional)',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _uploadRow(),
    ]);
  }

  Widget _placeField() {
    final citiesAsync = ref.watch(allCityNamesProvider);
    final cities = citiesAsync.valueOrNull ?? const <String>[];
    if (citiesAsync.isLoading && cities.isEmpty) {
      return Row(children: [
        const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Expanded(child: Text('Loading places…',
            style: TextStyle(color: Colors.grey[600], fontSize: 13))),
      ]);
    }
    return SearchableWithOthersField(
      label: 'Place of Birth',
      isRequired: true,
      prefixIcon: Icons.location_on_outlined,
      popupMode: SearchablePopupMode.modalBottomSheet,
      items: cities,
      value: _place,
      customLabel: 'Custom place of birth',
      onChanged: (v) => setState(() => _place = v),
    );
  }

  Widget _uploadRow() {
    final hasImage = _otherImageUrl.isNotEmpty;
    final hasPdf = _otherPdfUrl.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasImage || hasPdf) ...[
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (hasImage)
                _attachmentChip(
                  preview: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child:
                        NetworkPhoto(url: _otherImageUrl, width: 52, height: 52),
                  ),
                  label: 'Image attached',
                  onRemove: () => setState(() => _otherImageUrl = ''),
                ),
              if (hasPdf)
                _attachmentChip(
                  preview: const Icon(Icons.picture_as_pdf,
                      color: AppColors.error, size: 40),
                  label: 'PDF attached',
                  onRemove: () => setState(() => _otherPdfUrl = ''),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Optional — attach the second person\'s horoscope.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _uploading ? null : _pickImage,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.image_outlined, size: 18),
              label: Text(hasImage ? 'Replace image' : 'Image'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _uploading ? null : _pickPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(hasPdf ? 'Replace PDF' : 'PDF'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary)),
            ),
          ),
        ]),
      ],
    );
  }

  /// A preview tile with its own Remove button, shown for each attachment.
  Widget _attachmentChip({
    required Widget preview,
    required String label,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 52, height: 52, child: Center(child: preview)),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.success,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 18, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sticky pay bar ────────────────────────────────────────────────────────
  Widget _payBar() => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, -2)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _payAndRequest,
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome, size: 20),
              label: Text(
                _busy ? 'Processing…' : 'Request Report',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      );

  // ── Reusable bits ─────────────────────────────────────────────────────────
  Widget _card(String title, IconData icon, List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ]),
            const Divider(height: 18),
            ...children,
          ],
        ),
      );

  Widget _readRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 120,
                child: Text(k,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[600]))),
            Expanded(
              child: Text(v.trim().isEmpty ? '—' : v,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  /// A read-only display box that looks like an input but cannot be edited
  /// (used for the auto-derived Age and locked Gender).
  Widget _readOnlyBox(String label, String value, IconData icon) =>
      InputDecorator(
        decoration: _dec(label).copyWith(
          fillColor: Colors.grey[200],
          suffixIcon: const Icon(Icons.lock_outline, size: 16),
          prefixIcon: Icon(icon, size: 18),
        ),
        child: Text(value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      );

  Widget _pickerField(
          String label, String value, IconData icon, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: _dec(label).copyWith(suffixIcon: Icon(icon, size: 18)),
          child: Text(value.isEmpty ? '' : value,
              style: const TextStyle(fontSize: 14)),
        ),
      );

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.scaffoldBg,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}
