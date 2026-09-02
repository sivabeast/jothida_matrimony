import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/services/horoscope_calculation_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/horoscope_roles.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/value_l10n.dart';
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

  /// Canonical `'Male'` / `'Female'` (never localized — Tamil is a DISPLAY
  /// concern, handled by `context.localizeValue`). Empty means "not decided
  /// yet", which only ever happens for a cleared Person 1 whose owner has not
  /// picked a side.
  ///
  /// This is what drives the Bride / Groom mapping (spec §1E): Female → Bride,
  /// Male → Groom, regardless of which slot the person was typed into.
  String gender = '';

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
  /// The bride/groom role this person maps to, or `''` while the gender is
  /// still unknown. Female → Bride, Male → Groom (spec §1E/§4C).
  String get role => switch (gender) {
        'Female' => kRoleBride,
        'Male' => kRoleGroom,
        _ => '',
      };

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
    gender = '';
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
    // Gender comes from the profile and is never asked for again (spec §1B).
    gender = normalizeHoroscopeGender(p.gender);
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
  Map<String, dynamic> toMap({String? gender}) {
    final g = normalizeHoroscopeGender(gender ?? this.gender);
    final p = place;
    final city =
        p == null ? '' : (p.cityEn.isNotEmpty ? p.cityEn : p.city);
    final district =
        p == null ? '' : (p.districtEn.isNotEmpty ? p.districtEn : p.district);
    return {
      'name': name.text.trim(),
      'age': age,
      'gender': g,
      // Denormalized so every reader — the employee report screen, the admin
      // list, the PDF — gets the Bride/Groom side without re-deriving it.
      'role': g == 'Female' ? kRoleBride : (g == 'Male' ? kRoleGroom : ''),
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

/// How this person's GENDER is decided — which is also how it is presented
/// (spec §1B/§1D).
enum HoroscopeGenderMode {
  /// Person 1, seeded from the signed-in member's own profile. Read-only, and
  /// captioned "Based on your profile" so it is obvious where it came from.
  fromProfile,

  /// Person 2. Always the opposite of Person 1, computed — never asked.
  auto,

  /// Person 1 after "Clear": this is now somebody else entirely, so the one
  /// thing that cannot be inferred is asked for exactly once.
  manual,
}

/// The editable card for ONE person in the horoscope request.
///
/// Used for BOTH Person 1 and Person 2 (spec §1A/§1C): the same fields and the
/// same validation, so a member can request a horoscope for themselves, for
/// their child, or for two people they have never met.
///
/// The two sides differ in exactly two ways, both driven by [genderMode]:
///
///  * Person 1 opens ALREADY FILLED from the profile and offers a single
///    **Clear** action — there is deliberately no "Use my profile details"
///    button, because the details are already there (spec §1A).
///  * Person 2 never offers either action: it is a different person by
///    definition, and its gender is derived from Person 1 (spec §1C/§1D).
class HoroscopePersonForm extends ConsumerStatefulWidget {
  final HoroscopePersonDraft draft;
  final String title;
  final String subtitle;
  final IconData icon;

  /// Nakshatra / Rasi option lists (Tamil master astrology data).
  final List<String> nakshatraOptions;
  final List<String> rasiOptions;

  /// How the gender field behaves and reads.
  final HoroscopeGenderMode genderMode;

  /// Wipes the card so a completely different person can be entered. Null
  /// hides the action — Person 2 has nothing pre-filled to clear (spec §1C).
  final VoidCallback? onClear;

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
    this.genderMode = HoroscopeGenderMode.manual,
    this.onClear,
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
    // The PARENT owns the clear, because clearing Person 1 also re-opens the
    // gender question and invalidates Person 2's derived gender.
    (widget.onClear ?? d.clear).call();
    _touch();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        // ONE action, and only where it means something: Person 1 opens
        // pre-filled from the profile, so the only thing left to offer is a way
        // to empty it and type somebody else (spec §1A). Person 2 passes no
        // callback and therefore shows nothing here.
        if (widget.onClear != null && !d.isBlank) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _confirmClear,
              icon: const Icon(Icons.backspace_outlined, size: 16),
              label: Text(l10n.clearDetails,
                  style: const TextStyle(fontSize: 12.5)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey[700],
                side: BorderSide(color: Colors.grey[400]!),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _genderField(),
        const SizedBox(height: 12),
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

  // ── Gender (spec §1B / §1D) ───────────────────────────────────────────────

  /// The gender control.
  ///
  /// For Person 1 seeded from the profile, and for Person 2 always, this is
  /// **not an input** — it is a statement of a fact the app already knows,
  /// captioned with where that fact came from. Only a cleared Person 1 (now
  /// somebody else entirely) is ever asked.
  ///
  /// Whichever way it is decided, the Bride / Groom role is shown right next to
  /// it, so the member can see the mapping the astrologer will work from before
  /// they pay for anything.
  Widget _genderField() {
    final l10n = context.l10n;
    final known = d.gender.isNotEmpty;
    final caption = switch (widget.genderMode) {
      HoroscopeGenderMode.fromProfile => l10n.genderBasedOnProfile,
      HoroscopeGenderMode.auto => l10n.genderAutoFromPersonOne,
      HoroscopeGenderMode.manual => l10n.genderPickForThisPerson,
    };
    final editable = widget.genderMode == HoroscopeGenderMode.manual;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: editable ? Colors.white : AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: editable
                ? Colors.grey[400]!
                : AppColors.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.wc_outlined,
                size: 18,
                color: editable ? Colors.grey[600] : AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${l10n.gender} *',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700])),
            ),
            if (known) _roleChip(),
          ]),
          const SizedBox(height: 9),
          if (editable)
            _genderChoice()
          else
            Text(known ? context.localizeValue(d.gender) : '—',
                style: TextStyle(
                    fontSize: 15.5,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: known ? AppColors.textPrimary : Colors.grey[500])),
          const SizedBox(height: 5),
          // Tamil captions run longer than English — this wraps freely inside a
          // height-less container rather than being clipped (spec §5A).
          Text(caption,
              style: TextStyle(
                  fontSize: 11.5, height: 1.45, color: Colors.grey[600])),
        ],
      ),
    );
  }

  /// Male / Female, for a cleared Person 1 only. A Wrap (not a Row) so the two
  /// options drop onto separate lines rather than overflowing when the Tamil
  /// labels are wider than the card.
  Widget _genderChoice() => Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          for (final g in const ['Male', 'Female'])
            ChoiceChip(
              label: Text(context.localizeValue(g)),
              selected: d.gender == g,
              showCheckmark: false,
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: d.gender == g ? Colors.white : Colors.grey[800],
              ),
              selectedColor: AppColors.primary,
              backgroundColor: Colors.white,
              side: BorderSide(
                  color: d.gender == g
                      ? AppColors.primary
                      : Colors.grey[400]!),
              onSelected: (_) {
                d.gender = g;
                _touch();
              },
            ),
        ],
      );

  /// "Bride" / "Groom" — the mapping this gender produces (spec §1E).
  Widget _roleChip() {
    final l10n = context.l10n;
    final isBride = d.role == kRoleBride;
    final color = isBride ? const Color(0xFFC2185B) : AppColors.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(isBride ? l10n.brideRole : l10n.groomRole,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
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
