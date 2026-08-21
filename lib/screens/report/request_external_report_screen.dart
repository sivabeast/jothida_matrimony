import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/master_astrology_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/location_model.dart';
import '../../models/profile_model.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/billing/play_billing_service.dart';
import '../../widgets/auth/account_required_sheet.dart';
import '../../widgets/common/network_photo.dart';
import '../../widgets/common/place_picker_field.dart';
import '../../widgets/common/searchable_field.dart';

/// **Request New Horoscope Report** — the compatibility report for someone who
/// is NOT on the app (spec §9–§13).
///
/// The signed-in member's own details are auto-filled from their profile (they
/// never retype them); only the SECOND person's details are entered here,
/// together with an optional horoscope image/PDF. The flow is identical to the
/// in-app profile flow:
///
///   Fill second-person details → ₹200 payment → payment success → request
///
/// Both flows share the SAME price, the SAME Google Play Billing validation
/// and the SAME request-creation + Reports delivery path (spec §14). A
/// cancelled or failed payment creates nothing.
///
/// Second-person input rules (spec §11):
///   * Gender is auto-set to the opposite of the logged-in user's gender and is
///     read-only.
///   * Age is derived from the Date of Birth and is read-only.
///   * Place of Birth uses the app's ONE place picker — City/Village +
///     District + State (spec §27–§32). The place is used only for THIS
///     request; nothing is written back to the shared location data.
///   * Nakshatra / Rasi are searchable dropdowns backed by the master
///     astrology data.
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
  /// Fallback price, shown only until Play's own price arrives — the exact
  /// same constant the in-app profile flow uses (spec §14).
  static const int _fee = AppConstants.horoscopeAnalysisFee; // ₹200

  final _formKey = GlobalKey<FormState>();

  // Second-person fields.
  final _name = TextEditingController();
  final _tob = TextEditingController();

  /// The second person's birth place. Held in local state ONLY — a place added
  /// here is never saved to the member's own profile and never appears in
  /// anyone else's suggestions (spec §30).
  PlaceSelection? _place;
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

  /// Play's localized price for `horoscope_report`, when the store answers.
  String? _storePrice;
  String get _priceText => _storePrice ?? '₹$_fee';

  @override
  void initState() {
    super.initState();
    _loadMasterOptions();
    _loadStorePrice();
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

  /// Best-effort: an unreachable store (emulator without Play, no network)
  /// must never surface an error here — the button simply keeps showing the
  /// built-in ₹200 until Play answers.
  Future<void> _loadStorePrice() async {
    try {
      final billing = ref.read(playBillingServiceProvider);
      await billing.init();
      if (!mounted) return;
      setState(() =>
          _storePrice = billing.priceLabel(BillingProducts.horoscopeReport));
    } catch (_) {
      // Keep the fallback price.
    }
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

  Map<String, dynamic> _otherMap(ProfileModel? me) {
    final place = _place;
    return {
      'name': _name.text.trim(),
      'age': _dob == null ? 0 : _ageFromDob(_dob!),
      'gender': _lockedGender(me),
      'dob': _dob == null ? '' : DateFormat('dd MMM yyyy').format(_dob!),
      'tob': _tob.text.trim(),
      // Full "City, District, State" so the astrologer can never confuse two
      // villages that share a name (spec §27/§32).
      'place': place?.display ?? '',
      'placeCity': place?.cityEn.isNotEmpty == true ? place!.cityEn : (place?.city ?? ''),
      'placeDistrict':
          place?.districtEn.isNotEmpty == true ? place!.districtEn : (place?.district ?? ''),
      'placeState': place?.state ?? '',
      'nakshatra': (_nakshatra ?? '').trim(),
      'rasi': (_rasi ?? '').trim(),
      'horoscopeImageUrl': _otherImageUrl,
      'horoscopePdfUrl': _otherPdfUrl,
    };
  }

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
      _snack(context.l10n.uploadFailedRetry);
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

  // ── Validate → account → pay → create ────────────────────────────────────
  /// The single entry point behind "Pay ₹200 · Request Report".
  ///
  /// Nothing is created until Google Play reports a VERIFIED purchase, so a
  /// cancelled or failed payment leaves no request behind (spec §13).
  Future<void> _payAndRequest() async {
    if (_busy) return;
    final l10n = context.l10n;
    // Field-level (Name) validation first.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Picker fields are not FormFields, so validate them explicitly.
    if (_dob == null) return _snack(l10n.pleaseSelectSecondDob);
    if (_tob.text.trim().isEmpty) return _snack(l10n.pleaseSelectSecondTob);
    if (_place == null || _place!.isEmpty) {
      return _snack(l10n.pleaseSelectSecondPlace);
    }
    if ((_nakshatra ?? '').trim().isEmpty) {
      return _snack(l10n.pleaseSelectSecondNakshatra);
    }
    if ((_rasi ?? '').trim().isEmpty) return _snack(l10n.pleaseSelectSecondRasi);

    setState(() => _busy = true);

    // An ACCOUNT is required to own the request — but a matrimony profile is
    // not: this report is about two other people's charts. Asked for here,
    // after both horoscopes are filled in, so a guest never retypes anything.
    if (!await ensureAccount(context, ref,
        reason: context.l10n.accountNeededForRequest)) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;

    try {
      // Google Play Billing purchase sheet — the SAME one-time product the
      // in-app profile flow charges for (spec §14).
      final result = await ref
          .read(playBillingServiceProvider)
          .buyConsumable(BillingProducts.horoscopeReport);
      if (!mounted) return;

      if (!result.isPurchased) {
        switch (result.outcome) {
          case BillingOutcome.canceled:
            _snack(l10n.paymentCancelledNotCharged);
            break;
          case BillingOutcome.unavailable:
            _snack(result.message ?? l10n.billingUnavailable);
            break;
          default:
            _snack(result.message ?? l10n.paymentCouldNotComplete);
        }
        setState(() => _busy = false);
        return;
      }

      // Record what Play ACTUALLY charged rather than the hardcoded constant.
      final raw = ref
          .read(playBillingServiceProvider)
          .rawPrice(BillingProducts.horoscopeReport);
      final chargedAmount = (raw != null && raw > 0) ? raw.round() : _fee;

      await _createRequest(
        amount: chargedAmount,
        paymentId: result.purchaseToken.isNotEmpty
            ? result.purchaseToken
            : 'play_billing',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(l10n.couldNotStartPayment);
    }
  }

  Future<void> _createRequest({
    required int amount,
    String? paymentId,
  }) async {
    final l10n = context.l10n;
    final me = ref.read(myProfileProvider).valueOrNull;
    try {
      final id = await ref
          .read(matchAnalysisControllerProvider.notifier)
          .requestExternalReport(
            requester: _requesterMap(me),
            other: _otherMap(me),
            amount: amount,
            paymentId: paymentId,
            note: 'External horoscope report — paid via Google Play Billing.',
          );
      if (!mounted) return;
      _snack(l10n.requestSubmittedTrackReports(id));
      ref.read(homeTabIndexProvider.notifier).state = kReportsTabIndex;
      context.go('/home');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(l10n.couldNotCreateRequest);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(myProfileProvider).valueOrNull;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(context.l10n.requestNewHoroscopeReport),
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
            const SizedBox(height: 14),
            _chargeCard(),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.description_outlined,
                  color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.l10n.compatibilityReportWithAnyone,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(context.l10n.compatibilityReportWithAnyoneBody,
                style: const TextStyle(
                    color: Colors.white, fontSize: 12.5, height: 1.5)),
          ],
        ),
      );

  // ── Your (auto-filled) details ────────────────────────────────────────────
  Widget _selfCard(ProfileModel? me) {
    final l10n = context.l10n;
    final h = me?.horoscope;
    final hasHoro = (h?.horoscopeImages.isNotEmpty ?? false) ||
        (h?.horoscopePdfUrls.isNotEmpty ?? false);
    return _card(l10n.yourDetailsAutoFilled, Icons.person_outline, [
      if (me == null)
        Text(l10n.yourProfileStillLoading,
            style: const TextStyle(color: Colors.grey))
      else ...[
        _readRow(l10n.fullName, me.fullName),
        _readRow(l10n.age, me.age > 0 ? '${me.age}' : '—'),
        _readRow(l10n.gender, me.gender),
        _readRow(l10n.dateOfBirth,
            DateFormat('dd MMM yyyy').format(me.dateOfBirth)),
        _readRow(l10n.timeOfBirth, h?.birthTime ?? ''),
        _readRow(
            l10n.placeOfBirthLabel,
            (h?.birthPlace.trim().isNotEmpty ?? false)
                ? h!.birthPlace
                : [me.city, me.state]
                    .where((s) => s.trim().isNotEmpty)
                    .join(', ')),
        _readRow(l10n.nakshatra, h?.nakshatra ?? ''),
        _readRow(l10n.rasi, h?.rasi ?? ''),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(hasHoro ? Icons.check_circle : Icons.info_outline,
                size: 16, color: hasHoro ? AppColors.success : Colors.grey),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                hasHoro
                    ? l10n.horoscopeWillBeAttached
                    : l10n.noHoroscopeDocOnProfile,
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
    final l10n = context.l10n;
    final lockedGender = _lockedGender(me);
    final ageText = _dob == null ? '—' : '${_ageFromDob(_dob!)}';
    return _card(l10n.secondPersonDetails, Icons.person_add_alt_1_outlined, [
      TextFormField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: _dec('${l10n.fullNameLabel} *'),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? l10n.nameIsRequired : null,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          // Age is derived from the DOB below and cannot be edited.
          Expanded(
              child: _readOnlyBox(l10n.age, ageText, Icons.cake_outlined)),
          const SizedBox(width: 10),
          // Gender is auto-set to the opposite of the logged-in user.
          Expanded(
              child:
                  _readOnlyBox(l10n.gender, lockedGender, Icons.wc_outlined)),
        ],
      ),
      const SizedBox(height: 6),
      Text(l10n.genderAgeAutoNote,
          style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
              child: _pickerField(
                  '${l10n.dateOfBirth} *',
                  _dob == null
                      ? ''
                      : DateFormat('dd MMM yyyy').format(_dob!),
                  Icons.calendar_today_outlined,
                  _pickDob)),
          const SizedBox(width: 10),
          Expanded(
              child: _pickerField('${l10n.timeOfBirth} *', _tob.text,
                  Icons.schedule, _pickTob)),
        ],
      ),
      const SizedBox(height: 12),
      // Place of Birth — the app's ONE place picker: search → City/Village +
      // District + State → + → Save (spec §27–§31).
      PlacePickerField(
        label: l10n.placeOfBirthLabel,
        isRequired: true,
        value: _place?.display,
        onChanged: (p) => setState(() => _place = p),
      ),
      const SizedBox(height: 12),
      // Nakshatra / Rasi — searchable dropdowns backed by the master data.
      SearchableField(
        label: l10n.nakshatra,
        isRequired: true,
        items: _nakOptions,
        selectedItem: _nakshatra,
        prefixIcon: Icons.auto_awesome_outlined,
        popupMode: SearchablePopupMode.modalBottomSheet,
        onChanged: (v) => setState(() => _nakshatra = v),
      ),
      const SizedBox(height: 12),
      SearchableField(
        label: l10n.rasi,
        isRequired: true,
        items: _rasiOptions,
        selectedItem: _rasi,
        prefixIcon: Icons.brightness_3_outlined,
        popupMode: SearchablePopupMode.modalBottomSheet,
        onChanged: (v) => setState(() => _rasi = v),
      ),
      const SizedBox(height: 14),
      Text(l10n.horoscopeImageOrPdfOptional,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _uploadRow(),
    ]);
  }

  /// The ₹200 service charge, shown before the pay button so the price is
  /// never a surprise — the same charge the in-app profile flow states.
  Widget _chargeCard() {
    final l10n = context.l10n;
    return _card(l10n.serviceDetails, Icons.info_outline, [
      _metaRow(Icons.cloud_done_outlined, l10n.serviceTypeLabel,
          l10n.onlineReportNoVisit),
      const Divider(height: 18),
      _metaRow(Icons.schedule_outlined, l10n.estimatedDelivery,
          l10n.deliveryWithinTwoDays),
      const Divider(height: 18),
      _metaRow(Icons.payments_outlined, l10n.serviceCharge, _priceText),
    ]);
  }

  Widget _metaRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700])),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  Widget _uploadRow() {
    final l10n = context.l10n;
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
                  label: l10n.imageAttached,
                  onRemove: () => setState(() => _otherImageUrl = ''),
                ),
              if (hasPdf)
                _attachmentChip(
                  preview: const Icon(Icons.picture_as_pdf,
                      color: AppColors.error, size: 40),
                  label: l10n.pdfAttached,
                  onRemove: () => setState(() => _otherPdfUrl = ''),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(l10n.attachSecondPersonHoroscope,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
              label: Text(hasImage ? l10n.replaceImage : l10n.imageLabel),
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
              label: Text(hasPdf ? l10n.replacePdf : l10n.pdfLabel),
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
        color: AppColors.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
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
                color: Colors.black.withValues(alpha: 0.06),
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
                _busy
                    ? context.l10n.processingPayment
                    : context.l10n.payAndRequestReport(_priceText),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              ),
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
