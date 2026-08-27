import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/services/horoscope_calculation_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/location_model.dart';
import '../../models/profile_model.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/network_photo.dart';
import '../../widgets/common/place_picker_field.dart';
import '../../widgets/common/searchable_field.dart';

/// One person's horoscope details inside a Horoscope Report Request
/// (spec §3/§4).
///
/// Deliberately a plain mutable holder rather than an immutable model: it backs
/// a live form where every field is independently editable, and the form is the
/// only writer. [toMap] is what actually gets stored — a SNAPSHOT taken at
/// submission time, so later edits to the member's own profile can never
/// rewrite a request that has already been sent (spec §7).
class HoroscopePersonDraft {
  final TextEditingController name = TextEditingController();

  DateTime? dob;

  /// Birth time as entered: hour is 1–12 (never 0), with [isPm] carrying the
  /// AM/PM half. Stored separately from a formatted string so the AM/PM
  /// selector is a first-class field the member can flip on its own (spec §3).
  int? hour;
  int? minute;
  bool isPm = false;

  /// City + District + State, from the app's ONE place picker. Used only for
  /// THIS request — nothing is written back to shared location data.
  PlaceSelection? place;

  /// Optional (spec §3): a blank Nakshatra / Rasi never blocks submission.
  String? nakshatra;
  String? rasi;

  /// Optional uploaded horoscope. Images and PDFs are both accepted; the image
  /// is what the admin previews, the PDF is linked.
  String imageUrl = '';
  String pdfUrl = '';

  bool get hasBirthTime => hour != null && minute != null;

  /// "06:45 AM" — the display and stored form of the birth time.
  String get birthTimeText {
    if (!hasBirthTime) return '';
    final h = hour!.toString().padLeft(2, '0');
    final m = minute!.toString().padLeft(2, '0');
    return '$h:$m ${isPm ? 'PM' : 'AM'}';
  }

  /// True once the member has typed anything at all — drives whether "Clear"
  /// is worth offering.
  bool get isBlank =>
      name.text.trim().isEmpty &&
      dob == null &&
      !hasBirthTime &&
      place == null &&
      (nakshatra ?? '').isEmpty &&
      (rasi ?? '').isEmpty &&
      imageUrl.isEmpty &&
      pdfUrl.isEmpty;

  int get age {
    final d = dob;
    if (d == null) return 0;
    final now = DateTime.now();
    var a = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) a--;
    return a < 0 ? 0 : a;
  }

  /// Wipes every field so a completely different person can be entered
  /// (spec §6 — "Clear / Replace").
  void clear() {
    name.clear();
    dob = null;
    hour = null;
    minute = null;
    isPm = false;
    place = null;
    nakshatra = null;
    rasi = null;
    imageUrl = '';
    pdfUrl = '';
  }

  /// Pre-fills from a matrimony profile (spec §5). Everything stays editable
  /// afterwards — this only supplies DEFAULTS, never a locked value.
  void fillFromProfile(ProfileModel p) {
    final h = p.horoscope;
    name.text = p.fullName;
    dob = p.dateOfBirth;

    final parsed = _parseTime(
        HoroscopeCalculationService.formatBirthTimeForDisplay(h.birthTime));
    if (parsed != null) {
      hour = parsed.$1;
      minute = parsed.$2;
      isPm = parsed.$3;
    }

    final birthPlace = h.birthPlace.trim();
    if (birthPlace.isNotEmpty) {
      final parts = birthPlace.split(',').map((s) => s.trim()).toList();
      place = PlaceSelection(
        city: parts.isNotEmpty ? parts.first : '',
        district: parts.length > 1 ? parts[1] : p.district,
        state: parts.length > 2 ? parts[2] : (p.state.isEmpty ? '' : p.state),
      );
    } else if (p.city.trim().isNotEmpty) {
      place = PlaceSelection(
          city: p.city, district: p.district, state: p.state);
    }

    nakshatra = h.nakshatra.trim().isEmpty ? null : h.nakshatra.trim();
    rasi = h.rasi.trim().isEmpty ? null : h.rasi.trim();
    if (h.horoscopeImages.isNotEmpty) imageUrl = h.horoscopeImages.first;
    if (h.horoscopePdfUrls.isNotEmpty) pdfUrl = h.horoscopePdfUrls.first;
  }

  /// Parses "06:45 AM" / "6:45 pm" back into (hour, minute, isPm).
  static (int, int, bool)? _parseTime(String raw) {
    final m = RegExp(r'(\d{1,2})[:.](\d{2})\s*([AaPp])?')
        .firstMatch(raw.trim());
    if (m == null) return null;
    var h = int.tryParse(m.group(1) ?? '') ?? 0;
    final min = int.tryParse(m.group(2) ?? '') ?? 0;
    final marker = (m.group(3) ?? '').toLowerCase();
    var pm = marker == 'p';
    if (marker.isEmpty) {
      // 24-hour text — convert.
      pm = h >= 12;
      if (h > 12) h -= 12;
    }
    if (h == 0) h = 12;
    if (h < 1 || h > 12 || min < 0 || min > 59) return null;
    return (h, min, pm);
  }

  /// The stored snapshot. Field names match what the admin / employee detail
  /// pages already read, with the new District / City / AM-PM parts added
  /// alongside rather than replacing anything (spec §10/§35).
  Map<String, dynamic> toMap({String gender = ''}) {
    final p = place;
    final city =
        p == null ? '' : (p.cityEn.isNotEmpty ? p.cityEn : p.city);
    final district =
        p == null ? '' : (p.districtEn.isNotEmpty ? p.districtEn : p.district);
    return {
      'name': name.text.trim(),
      'age': age,
      'gender': gender,
      'dob': dob == null ? '' : DateFormat('dd MMM yyyy').format(dob!),
      'dobIso': dob?.toIso8601String() ?? '',
      'tob': birthTimeText,
      'tobHour': hour ?? 0,
      'tobMinute': minute ?? 0,
      'tobPeriod': isPm ? 'PM' : 'AM',
      'place': p?.display ?? '',
      'placeCity': city,
      'placeDistrict': district,
      'placeState': p?.state ?? '',
      'nakshatra': (nakshatra ?? '').trim(),
      'rasi': (rasi ?? '').trim(),
      'horoscopeImageUrl': imageUrl,
      'horoscopePdfUrl': pdfUrl,
    };
  }

  void dispose() => name.dispose();
}

/// The editable card for ONE person in the horoscope request.
///
/// Used for BOTH Person 1 and Person 2 (spec §4/§6): the same fields, the same
/// validation and the same Auto-fill / Clear actions, so a member can request a
/// horoscope for themselves, for their child, or for two people they have
/// never met, without the form treating any of those as a special case.
class HoroscopePersonForm extends ConsumerStatefulWidget {
  final HoroscopePersonDraft draft;
  final String title;
  final String subtitle;
  final IconData icon;

  /// Nakshatra / Rasi option lists (Tamil master astrology data).
  final List<String> nakshatraOptions;
  final List<String> rasiOptions;

  /// Shown as "Use my profile details" when the member has a profile. Null
  /// hides the action entirely (a guest, or a profile that is still loading).
  final VoidCallback? onAutofill;

  /// Rebuilds the parent so its Continue button can re-evaluate validity.
  final VoidCallback onChanged;

  const HoroscopePersonForm({
    super.key,
    required this.draft,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.nakshatraOptions,
    required this.rasiOptions,
    required this.onChanged,
    this.onAutofill,
  });

  @override
  ConsumerState<HoroscopePersonForm> createState() =>
      _HoroscopePersonFormState();
}

class _HoroscopePersonFormState extends ConsumerState<HoroscopePersonForm> {
  bool _uploading = false;

  HoroscopePersonDraft get d => widget.draft;

  void _touch() {
    setState(() {});
    widget.onChanged();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: d.dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1940),
      lastDate: now,
    );
    if (picked != null) {
      d.dob = picked;
      _touch();
    }
  }

  Future<void> _pickTime() async {
    final initial = d.hasBirthTime
        ? TimeOfDay(
            hour: (d.hour! % 12) + (d.isPm ? 12 : 0), minute: d.minute!)
        : const TimeOfDay(hour: 6, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    d.hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
    d.minute = picked.minute;
    d.isPm = picked.period == DayPeriod.pm;
    _touch();
  }

  Future<void> _upload({required bool isImage}) async {
    File file;
    if (isImage) {
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      file = File(picked.path);
    } else {
      final res = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      final path = res?.files.single.path;
      if (path == null) return;
      file = File(path);
    }
    setState(() => _uploading = true);
    try {
      final url = await ref.read(storageServiceProvider).uploadChatAttachment(
          threadId: 'horoscope_request_media', file: file, isImage: isImage);
      if (!mounted) return;
      if (isImage) {
        d.imageUrl = url;
      } else {
        d.pdfUrl = url;
      }
      _touch();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.uploadFailedRetry)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _confirmClear() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.clearDetailsTitle),
        content: Text(l10n.clearDetailsBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.clearAll),
          ),
        ],
      ),
    );
    if (ok != true) return;
    d.clear();
    _touch();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 12),
        // Auto-fill / Clear — the two actions that make a pre-filled form
        // usable for somebody OTHER than the member (spec §6).
        Row(
          children: [
            if (widget.onAutofill != null)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    widget.onAutofill!.call();
                    _touch();
                  },
                  icon: const Icon(Icons.person_pin_circle_outlined, size: 17),
                  label: Text(l10n.useMyProfileDetails,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
            if (widget.onAutofill != null && !d.isBlank)
              const SizedBox(width: 10),
            if (!d.isBlank)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _confirmClear,
                  icon: const Icon(Icons.backspace_outlined, size: 16),
                  label: Text(l10n.clearAndEnterNew,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    side: BorderSide(color: Colors.grey[400]!),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: d.name,
          textCapitalization: TextCapitalization.words,
          decoration: _dec(l10n.fullName, Icons.person_outline, required: true),
          validator: (v) =>
              (v ?? '').trim().length < 2 ? l10n.pleaseEnterFullName : null,
          onChanged: (_) => widget.onChanged(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _tapField(
                label: l10n.dateOfBirth,
                icon: Icons.cake_outlined,
                value: d.dob == null
                    ? ''
                    : DateFormat('dd MMM yyyy').format(d.dob!),
                onTap: _pickDob,
                required: true,
              ),
            ),
            const SizedBox(width: 10),
            if (d.dob != null)
              _pill('${l10n.age}: ${d.age}', AppColors.primary),
          ],
        ),
        const SizedBox(height: 12),
        // Birth time + the AM/PM selector as its own control (spec §3): the
        // member can flip the half without reopening the time picker, which is
        // exactly the mistake that ruins a horoscope.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _tapField(
                label: l10n.timeOfBirth,
                icon: Icons.access_time,
                value: d.hasBirthTime
                    ? '${d.hour!.toString().padLeft(2, '0')}:'
                        '${d.minute!.toString().padLeft(2, '0')}'
                    : '',
                onTap: _pickTime,
                required: true,
              ),
            ),
            const SizedBox(width: 10),
            _amPmToggle(),
          ],
        ),
        const SizedBox(height: 12),
        // Place of birth = City / Village + District + State in ONE control,
        // so District and City can never disagree with each other.
        PlacePickerField(
          label: l10n.placeOfBirthLabel,
          isRequired: true,
          value: d.place?.display,
          onChanged: (p) {
            d.place = p;
            _touch();
          },
        ),
        const SizedBox(height: 12),
        SearchableField(
          label: '${l10n.nakshatra} (${l10n.optional})',
          selectedItem: d.nakshatra,
          items: widget.nakshatraOptions,
          popupMode: SearchablePopupMode.modalBottomSheet,
          prefixIcon: Icons.star_border,
          onChanged: (v) {
            d.nakshatra = v;
            _touch();
          },
        ),
        const SizedBox(height: 12),
        SearchableField(
          label: '${l10n.rasi} (${l10n.optional})',
          selectedItem: d.rasi,
          items: widget.rasiOptions,
          popupMode: SearchablePopupMode.modalBottomSheet,
          prefixIcon: Icons.brightness_3_outlined,
          onChanged: (v) {
            d.rasi = v;
            _touch();
          },
        ),
        const SizedBox(height: 16),
        _horoscopeUpload(),
      ],
    );
  }

  Widget _header() => Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(widget.icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(widget.subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      );

  Widget _amPmToggle() {
    Widget half(String label, bool pm) {
      final on = d.isPm == pm && d.hasBirthTime;
      return InkWell(
        onTap: () {
          d.isPm = pm;
          // Choosing AM/PM before a time is meaningless — default to 6 o'clock
          // in the chosen half so the field is never half-filled.
          d.hour ??= 6;
          d.minute ??= 0;
          _touch();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          color: on ? AppColors.primary : Colors.transparent,
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : Colors.grey[700])),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[400]!),
        color: Colors.white,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        half('AM', false),
        Container(width: 1, height: 44, color: Colors.grey[300]),
        half('PM', true),
      ]),
    );
  }

  Widget _horoscopeUpload() {
    final l10n = context.l10n;
    final has = d.imageUrl.isNotEmpty || d.pdfUrl.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome_outlined,
                size: 17, color: AppColors.primary),
            const SizedBox(width: 7),
            Expanded(
              child: Text('${l10n.horoscopeImage} (${l10n.optional})',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(l10n.horoscopeUploadHint,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
          const SizedBox(height: 10),
          if (_uploading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4))),
            )
          else ...[
            if (d.imageUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 150,
                  width: double.infinity,
                  child: NetworkPhoto(url: d.imageUrl, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (d.pdfUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.picture_as_pdf,
                      size: 17, color: AppColors.error),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(l10n.horoscopePdfAttached,
                          style: const TextStyle(fontSize: 12.5))),
                ]),
              ),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _upload(isImage: true),
                  icon: const Icon(Icons.image_outlined, size: 16),
                  label: Text(
                      d.imageUrl.isEmpty ? l10n.uploadImage : l10n.replace,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _upload(isImage: false),
                  icon: const Icon(Icons.attach_file, size: 16),
                  label: Text(d.pdfUrl.isEmpty ? l10n.uploadPdf : l10n.replace,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary)),
                ),
              ),
            ]),
            if (has)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    d.imageUrl = '';
                    d.pdfUrl = '';
                    _touch();
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(l10n.removeAttachment,
                      style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ── Small building blocks ─────────────────────────────────────────────────

  InputDecoration _dec(String label, IconData icon, {bool required = false}) =>
      InputDecoration(
        labelText: required ? '$label *' : label,
        prefixIcon: Icon(icon, size: 19),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
      );

  Widget _tapField({
    required String label,
    required IconData icon,
    required String value,
    required VoidCallback onTap,
    bool required = false,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: _dec(label, icon, required: required),
          child: Text(value.isEmpty ? '—' : value,
              style: TextStyle(
                  fontSize: 14,
                  color: value.isEmpty ? Colors.grey[500] : null)),
        ),
      );

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 13)),
      );
}

/// Input formatter that keeps a WhatsApp field to DIGITS ONLY, at most 10 —
/// the strict rule from spec §8/§34. Pasting "+91 98765 43210" leaves
/// "9876543210"; a letter simply cannot be typed.
class WhatsAppNumberFormatter extends TextInputFormatter {
  const WhatsAppNumberFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    // A pasted number with the country code still resolves to the 10 digits.
    if (digits.length > 10 && digits.startsWith('91')) {
      digits = digits.substring(2);
    }
    if (digits.length > 10) digits = digits.substring(0, 10);
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
