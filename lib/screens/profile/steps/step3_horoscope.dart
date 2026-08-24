import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/horoscope_calculation_service.dart';
import '../../../core/services/master_astrology_data.dart';
import '../../../core/utils/inline_validation.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../models/location_model.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/calculated_horoscope_card.dart';
import '../../../widgets/common/place_picker_field.dart';

/// Step 3 — Horoscope.
///
/// Rasi / Nakshatra / Lagnam are calculated automatically from Date of Birth +
/// Time of Birth + Birth Place via the Vedic engine. Birth Place uses the
/// app's ONE place picker — City/Village + District + State (spec §31) — which
/// also disambiguates the geocoding lookup.
///
/// The three calculated values are **editable in place, inside the Calculated
/// Horoscope card** (§12). The old "Override automatically calculated
/// horoscope" switch is gone (§11): there is no edit mode to turn on and no
/// separate override screen — automatic calculation is still the default, and
/// changing a value is simply tapping it.
///
/// The generated values are always kept alongside the effective ones, so a
/// member's manual change never destroys what the engine computed.
class Step3Horoscope extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const Step3Horoscope({super.key, required this.onNext});

  @override
  ConsumerState<Step3Horoscope> createState() => _Step3State();
}

class _Step3State extends ConsumerState<Step3Horoscope> {
  final _v = InlineValidation();
  final _calc = HoroscopeCalculationService();
  final _birthTimeController = TextEditingController();
  final _dobController = TextEditingController();

  DateTime? _dob;
  TimeOfDay? _birthTime;

  /// Birth place as "City, District, State" (or a free-typed place). Stored
  /// verbatim, and passed to the geocoder — the district + state make the
  /// lookup unambiguous for villages whose name repeats across districts.
  String? _birthPlace;
  bool _placeIsCustom = false;

  // Calculated (generated) values.
  String? _genRasi;
  String? _genNakshatra;
  String? _genLagnam;
  double? _lat;
  double? _lng;

  // The member's own edits, when they change a value in the card. Null means
  // "use what the engine calculated".
  String? _ovrRasi;
  String? _ovrNakshatra;
  String? _ovrLagnam;

  // Master option lists (Tamil names) for the in-card pickers.
  List<String> _rasiOptions = const [];
  List<String> _nakOptions = const [];
  List<String> _lagnamOptions = const [];

  bool _calculating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefill();
    _loadMaster();
  }

  @override
  void dispose() {
    _birthTimeController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  Future<void> _loadMaster() async {
    final m = await MasterAstrologyData.load();
    if (!mounted) return;
    setState(() {
      _rasiOptions = m.rasis.map((e) => e.nameTamil).toList();
      _nakOptions = m.nakshatras.map((e) => e.nameTamil).toList();
      _lagnamOptions = m.lagnams.map((e) => e.nameTamil).toList();
    });
  }

  /// Prefill from the shared creation data (DOB from earlier steps, plus any
  /// previously entered horoscope details when re-visiting / editing).
  void _prefill() {
    final data = ref.read(profileCreationProvider).data;
    final dobStr = data['dateOfBirth'] as String?;
    if (dobStr != null) {
      _dob = DateTime.tryParse(dobStr);
      if (_dob != null) _dobController.text = _fmtDate(_dob!);
    }
    final h = data['horoscopeDetails'] as Map<String, dynamic>?;
    if (h != null) {
      final t = HoroscopeCalculationService.parseStoredTime(
          (h['birthTime'] as String?) ?? '');
      if (t != null) {
        _birthTime = t;
        _birthTimeController.text = _fmtTime(t);
      }
      final place = (h['birthPlace'] as String?)?.trim() ?? '';
      final type = (h['birthPlaceType'] as String?) ?? 'city';
      if (place.isNotEmpty) {
        _birthPlace = place;
        _placeIsCustom = type == 'custom';
      }
      _genRasi = (h['generatedRasi'] as String?)?.isNotEmpty == true
          ? h['generatedRasi'] as String
          : h['rasi'] as String?;
      _genNakshatra = (h['generatedNakshatra'] as String?)?.isNotEmpty == true
          ? h['generatedNakshatra'] as String
          : h['nakshatra'] as String?;
      _genLagnam = (h['generatedLagnam'] as String?)?.isNotEmpty == true
          ? h['generatedLagnam'] as String
          : h['lagnam'] as String?;
      _lat = (h['latitude'] as num?)?.toDouble();
      _lng = (h['longitude'] as num?)?.toDouble();
      // A saved value that differs from the generated one is a member edit,
      // whether or not the (removed) override flag was ever set.
      final savedRasi = (h['rasi'] as String?) ?? '';
      final savedNak = (h['nakshatra'] as String?) ?? '';
      final savedLag = (h['lagnam'] as String?) ?? '';
      if (savedRasi.isNotEmpty && savedRasi != _genRasi) _ovrRasi = savedRasi;
      if (savedNak.isNotEmpty && savedNak != _genNakshatra) {
        _ovrNakshatra = savedNak;
      }
      if (savedLag.isNotEmpty && savedLag != _genLagnam) _ovrLagnam = savedLag;
    }
  }

  // ── Effective (display/save) values ──────────────────────────────────────
  // A member edit wins over the calculated value; otherwise the engine's
  // result is what shows and what is saved.
  String? get _effRasi => _ovrRasi ?? _genRasi;
  String? get _effNakshatra => _ovrNakshatra ?? _genNakshatra;
  String? get _effLagnam => _ovrLagnam ?? _genLagnam;

  /// True once the member has changed any value away from what was
  /// calculated. Replaces the old override switch — it is DERIVED now, never
  /// something the member has to turn on.
  bool get _isUserEdited =>
      (_ovrRasi != null && _ovrRasi != _genRasi) ||
      (_ovrNakshatra != null && _ovrNakshatra != _genNakshatra) ||
      (_ovrLagnam != null && _ovrLagnam != _genLagnam);

  String? get _effectivePlace => _birthPlace?.trim();

  bool get _hasGenerated =>
      (_genRasi ?? '').isNotEmpty &&
      (_genNakshatra ?? '').isNotEmpty &&
      (_genLagnam ?? '').isNotEmpty;

  // ── Pickers / inputs ─────────────────────────────────────────────────────
  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1940),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobController.text = _fmtDate(picked);
      });
      ref
          .read(profileCreationProvider.notifier)
          .updateData({'dateOfBirth': picked.toIso8601String()});
      _recalculate();
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _birthTime ?? const TimeOfDay(hour: 6, minute: 30),
    );
    if (picked != null) {
      setState(() {
        _birthTime = picked;
        _birthTimeController.text = _fmtTime(picked);
      });
      _recalculate();
    }
  }

  void _onPlaceChanged(PlaceSelection p) {
    setState(() {
      _birthPlace = p.display;
      _placeIsCustom = p.custom;
    });
    _recalculate();
  }

  /// Recalculate whenever DOB + Time + Place are all present.
  Future<void> _recalculate() async {
    final dob = _dob;
    final time = _birthTime;
    final place = _effectivePlace;
    if (dob == null || time == null || place == null || place.isEmpty) return;

    setState(() {
      _calculating = true;
      _error = null;
    });
    try {
      final res = await _calc.calculate(
        dateOfBirth: dob,
        birthTime: time,
        birthPlace: place,
      );
      if (!mounted) return;
      setState(() {
        _genRasi = res.rasi;
        _genNakshatra = res.nakshatra;
        _genLagnam = res.lagnam;
        _lat = res.latitude;
        _lng = res.longitude;
        _calculating = false;
      });
    } on HoroscopeCalculationException catch (e) {
      if (!mounted) return;
      setState(() {
        _genRasi = _genNakshatra = _genLagnam = null;
        _lat = _lng = null;
        _calculating = false;
        _error = e.message;
      });
    }
  }

  void _saveAndNext() {
    final l10n = context.l10n;
    // Inline messages under each field, first invalid one scrolled to (§10).
    final checks = <FieldCheck>[
      FieldCheck(
          id: 'dob',
          valid: _dob != null,
          message: l10n.pleaseSelect(l10n.dateOfBirth)),
      FieldCheck(
          id: 'birthTime',
          valid: _birthTime != null,
          message: l10n.pleaseSelectTimeOfBirth),
      FieldCheck(
          id: 'birthPlace',
          valid: (_effectivePlace ?? '').isNotEmpty,
          message: l10n.pleaseSelectBirthPlace),
      FieldCheck(
          id: 'horoscope',
          valid: (_effRasi ?? '').isNotEmpty &&
              (_effNakshatra ?? '').isNotEmpty &&
              (_effLagnam ?? '').isNotEmpty,
          message: l10n.unableToGenerateHoroscope),
    ];
    if (!_v.validate(context, checks, onChanged: () => setState(() {}))) return;

    ref.read(profileCreationProvider.notifier).updateData({
      'horoscopeDetails': {
        // Effective values
        'rasi': _effRasi,
        'nakshatra': _effNakshatra,
        'lagnam': _effLagnam,
        // Generated values (always preserved)
        'generatedRasi': _genRasi ?? '',
        'generatedNakshatra': _genNakshatra ?? '',
        'generatedLagnam': _genLagnam ?? '',
        // Derived from the values themselves — there is no override switch
        // any more (§11). Kept in the document so existing readers (the
        // astrologer report, the website) keep working unchanged.
        'overrideEnabled': _isUserEdited,
        // Birth details
        'birthTime': HoroscopeCalculationService.formatStoredTime(_birthTime!),
        'birthPlace': _effectivePlace,
        'birthPlaceType': _placeIsCustom ? 'custom' : 'city',
        'latitude': _lat ?? 0,
        'longitude': _lng ?? 0,
        'horoscopeGenerated': true,
        'isAutoGenerated': !_isUserEdited,
        'isUserEdited': _isUserEdited,
      },
    });
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // One clean vertical rhythm for the whole page (§10): heading, then the
    // description, then the three birth-detail fields evenly spaced, then the
    // Calculated Horoscope card, then Continue. Nothing overlaps, nothing is
    // clipped, and the scroll view has enough bottom padding that the last
    // control is never flush against the edge on a small phone.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Heading ───────────────────────────────────────────────────────
          Text(
            l10n.horoscopeDetails,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.horoscopeStepSubtitle,
            style: const TextStyle(color: Colors.grey, height: 1.4),
          ),
          const SizedBox(height: 28),

          // ── Birth details ────────────────────────────────────────────────
          AppTextField(
            key: _v.anchor('dob'),
            controller: _dobController,
            label: '${l10n.dateOfBirth} *',
            hint: l10n.selectDateHint,
            readOnly: true,
            onTap: _pickDob,
            suffixIcon: const Icon(Icons.calendar_today_outlined),
            errorText: _v.errorOf('dob'),
          ),
          const SizedBox(height: 18),
          AppTextField(
            key: _v.anchor('birthTime'),
            controller: _birthTimeController,
            label: '${l10n.timeOfBirth} *',
            hint: l10n.selectTimeHint,
            readOnly: true,
            onTap: _pickTime,
            suffixIcon: const Icon(Icons.access_time),
            errorText: _v.errorOf('birthTime'),
          ),
          const SizedBox(height: 18),
          PlacePickerField(
            key: _v.anchor('birthPlace'),
            label: l10n.placeOfBirthLabel,
            isRequired: true,
            value: _birthPlace,
            errorText: _v.errorOf('birthPlace'),
            onChanged: (p) {
              _v.clear('birthPlace');
              _onPlaceChanged(p);
            },
          ),
          const SizedBox(height: 28),

          // ── Calculated Horoscope ─────────────────────────────────────────
          // Fills in automatically from the three fields above; each value is
          // then editable inside the card itself (§12).
          Container(key: _v.anchor('horoscope')),
          InlineFieldError(_v.errorOf('horoscope')),
          if (_calculating)
            Row(children: [
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.calculatingHoroscope)),
            ])
          else if (_error != null)
            HoroscopeErrorBox(message: _error!)
          else if (_hasGenerated)
            CalculatedHoroscopeCard(
              rasi: _effRasi ?? '',
              nakshatra: _effNakshatra ?? '',
              lagnam: _effLagnam ?? '',
              rasiOptions: _rasiOptions,
              nakshatraOptions: _nakOptions,
              lagnamOptions: _lagnamOptions,
              onRasiChanged: (v) => setState(() {
                _ovrRasi = v;
                _v.clear('horoscope');
              }),
              onNakshatraChanged: (v) => setState(() {
                _ovrNakshatra = v;
                _v.clear('horoscope');
              }),
              onLagnamChanged: (v) => setState(() {
                _ovrLagnam = v;
                _v.clear('horoscope');
              }),
            )
          else
            Text(
              l10n.selectDateTimePlaceHint,
              style: TextStyle(
                  color: Colors.grey[600], fontSize: 13, height: 1.4),
            ),

          const SizedBox(height: 32),
          GradientButton(onPressed: _saveAndNext, text: l10n.continueLabel),
        ],
      ),
    );
  }

  // ── Formatting helpers ──────────────────────────────────────────────────
  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

  static String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }
}
