import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/razorpay/razorpay_service.dart';
import '../../widgets/common/network_photo.dart';

/// Spec §4 — **Request New Horoscope Report** (external).
///
/// Lets a signed-in user request a Horoscope Compatibility Report between
/// themselves (details auto-filled from their profile) and a SECOND person who
/// is NOT registered in the app (details entered manually + a horoscope
/// image/PDF uploaded here). After payment the request is created as a paid
/// `matching` request tagged `externalRequest`, auto-assigned to an employee,
/// and tracked on the user's Reports page exactly like an internal report.
class RequestExternalReportScreen extends ConsumerStatefulWidget {
  const RequestExternalReportScreen({super.key});

  @override
  ConsumerState<RequestExternalReportScreen> createState() =>
      _RequestExternalReportScreenState();
}

class _RequestExternalReportScreenState
    extends ConsumerState<RequestExternalReportScreen> {
  static const int _fee = AppConstants.horoscopeAnalysisFee; // ₹199

  final _formKey = GlobalKey<FormState>();
  final RazorpayService _razorpay = RazorpayService();

  // Second-person fields.
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _place = TextEditingController();
  final _tob = TextEditingController();
  final _nakshatra = TextEditingController();
  final _rasi = TextEditingController();
  String _gender = 'Female';
  DateTime? _dob;

  // Second-person uploaded horoscope.
  String _otherImageUrl = '';
  String _otherPdfUrl = '';
  bool _uploading = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _razorpay.init(onSuccess: _onPaymentSuccess, onFailure: _onPaymentFailure);
  }

  @override
  void dispose() {
    _razorpay.dispose();
    _name.dispose();
    _age.dispose();
    _place.dispose();
    _tob.dispose();
    _nakshatra.dispose();
    _rasi.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
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

  Map<String, dynamic> _otherMap() => {
        'name': _name.text.trim(),
        'age': int.tryParse(_age.text.trim()) ?? 0,
        'gender': _gender,
        'dob': _dob == null ? '' : DateFormat('dd MMM yyyy').format(_dob!),
        'tob': _tob.text.trim(),
        'place': _place.text.trim(),
        'nakshatra': _nakshatra.text.trim(),
        'rasi': _rasi.text.trim(),
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
      _tob.text = picked.format(context);
    }
  }

  // ── Pay + create ──────────────────────────────────────────────────────────
  void _payAndRequest() {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_dob == null) {
      _snack('Please select the second person\'s date of birth.');
      return;
    }
    setState(() => _busy = true);
    final user = ref.read(currentUserProvider).valueOrNull;
    final me = ref.read(myProfileProvider).valueOrNull;
    _razorpay.openCheckout(
      amountPaise: _fee * 100,
      description: 'External Horoscope Report',
      notes: const {'type': 'external_horoscope_report'},
      userPhone: user?.phone ?? '',
      userEmail: user?.email ?? '',
      userName: me?.fullName ?? '',
    );
    // _busy stays true until the gateway returns.
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) =>
      _createRequest(amount: _fee, paymentId: response.paymentId);

  /// Payment not completed → still create the request (unpaid) for manual
  /// verification, so the user's request is never lost (mirrors the internal
  /// report flow).
  Future<void> _onPaymentFailure(PaymentFailureResponse response) => _createRequest(
        amount: 0,
        note: 'Payment not completed — assigned for manual verification.',
        failed: true,
      );

  Future<void> _createRequest({
    required int amount,
    String? paymentId,
    String note = '',
    bool failed = false,
  }) async {
    final me = ref.read(myProfileProvider).valueOrNull;
    try {
      final id =
          await ref.read(matchAnalysisControllerProvider.notifier).requestExternalReport(
                requester: _requesterMap(me),
                other: _otherMap(),
                amount: amount,
                paymentId: paymentId,
                note: note,
              );
      if (!mounted) return;
      _snack(failed
          ? 'Payment was not completed — you have not been charged. Request '
              '#$id was sent for manual verification; track it on Reports.'
          : 'Payment successful. Request #$id has been assigned — track it on '
              'the Reports tab.');
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
            _otherCard(),
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
  Widget _otherCard() {
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
          Expanded(
            child: TextFormField(
              controller: _age,
              keyboardType: TextInputType.number,
              decoration: _dec('Age'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _gender,
              decoration: _dec('Gender *'),
              items: const [
                DropdownMenuItem(value: 'Female', child: Text('Female')),
                DropdownMenuItem(value: 'Male', child: Text('Male')),
              ],
              onChanged: (v) => setState(() => _gender = v ?? 'Female'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: _pickerField('Date of Birth *',
              _dob == null ? '' : DateFormat('dd MMM yyyy').format(_dob!),
              Icons.calendar_today_outlined, _pickDob)),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _tob,
              readOnly: true,
              onTap: _pickTob,
              decoration: _dec('Time of Birth').copyWith(
                  suffixIcon: const Icon(Icons.schedule, size: 18)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _place,
        textCapitalization: TextCapitalization.words,
        decoration: _dec('Place of Birth'),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _nakshatra,
              textCapitalization: TextCapitalization.words,
              decoration: _dec('Nakshatra'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _rasi,
              textCapitalization: TextCapitalization.words,
              decoration: _dec('Rasi'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      const Text('Horoscope Image / PDF',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _uploadRow(),
    ]);
  }

  Widget _uploadRow() {
    final hasImage = _otherImageUrl.isNotEmpty;
    final hasPdf = _otherPdfUrl.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (hasImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child:
                    NetworkPhoto(url: _otherImageUrl, width: 52, height: 52),
              ),
            if (hasPdf)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.picture_as_pdf,
                    color: AppColors.error, size: 34),
              ),
            if (hasImage || hasPdf) const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasImage && hasPdf
                    ? 'Image + PDF attached'
                    : hasImage
                        ? 'Image attached'
                        : hasPdf
                            ? 'PDF attached'
                            : 'Optional — attach the second person\'s horoscope.',
                style: TextStyle(
                    fontSize: 12,
                    color: (hasImage || hasPdf)
                        ? AppColors.success
                        : Colors.grey[600]),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
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
              label: const Text('Image'),
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
              label: const Text('PDF'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary)),
            ),
          ),
        ]),
      ],
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
                _busy ? 'Processing…' : 'Pay ₹$_fee · Request Report',
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
