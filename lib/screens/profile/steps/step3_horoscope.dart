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
import '../../../widgets/common/place_picker_field.dart';
import '../../../widgets/common/searchable_field.dart';

/// Step 3 — Horoscope.
///
/// Rasi / Nakshatra / Lagnam are calculated automatically from Date of Birth +
/// Time of Birth + Birth Place via the Vedic engine. Birth Place uses the
/// app's ONE place picker — City/Village + District + State (spec §31) — which
/// also disambiguates the geocoding lookup. Users may optionally **override**
/// the calculated values with manually-chosen ones from the master Rasi /
/// Nakshatra / Lagnam lists.
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

  // Manual override.
  bool _overrideEnabled = false;
  String? _ovrRasi;
  String? _ovrNakshatra;
  String? _ovrLagnam;

  // Master option lists (Tamil names) for the override dropdowns.
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
      _overrideEnabled = h['overrideEnabled'] == true;
      if (_overrideEnabled) {
        _ovrRasi = h['rasi'] as String?;
        _ovrNakshatra = h['nakshatra'] as String?;
        _ovrLagnam = h['lagnam'] as String?;
      }
    }
  }

  // ── Effective (display/save) values ──────────────────────────────────────
  String? get _effRasi => _overrideEnabled ? _ovrRasi : _genRasi;
  String? get _effNakshatra => _overrideEnabled ? _ovrNakshatra : _genNakshatra;
  String? get _effLagnam => _overrideEnabled ? _ovrLagnam : _genLagnam;

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

  void _onOverrideToggled(bool on) {
    setState(() {
      _overrideEnabled = on;
      if (on) {
        // Seed manual selections from the generated values.
        _ovrRasi ??= _genRasi;
        _ovrNakshatra ??= _genNakshatra;
        _ovrLagnam ??= _genLagnam;
      }
    });
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
        'overrideEnabled': _overrideEnabled,
        // Birth details
        'birthTime': HoroscopeCalculationService.formatStoredTime(_birthTime!),
        'birthPlace': _effectivePlace,
        'birthPlaceType': _placeIsCustom ? 'custom' : 'city',
        'latitude': _lat ?? 0,
        'longitude': _lng ?? 0,
        'horoscopeGenerated': true,
        'isAutoGenerated': !_overrideEnabled,
        'isUserEdited': _overrideEnabled,
      },
    });
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.horoscopeDetails,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(l10n.horoscopeStepSubtitle,
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),

          // ── Inputs ──────────────────────────────────────────────────────
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 24),

          // ── Status / generated results ───────────────────────────────────
          InlineFieldError(_v.errorOf('horoscope')),
          Container(key: _v.anchor('horoscope')),
          if (_calculating)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(child: Text(l10n.calculatingHoroscope)),
              ]),
            )
          else if (_error != null)
            _ErrorBox(message: _error!)
          else if (_hasGenerated && !_overrideEnabled)
            CalculatedHoroscopeCard(
                rasi: _genRasi!, nakshatra: _genNakshatra!, lagnam: _genLagnam!)
          else if (!_hasGenerated)
            Text(
              l10n.selectDateTimePlaceHint,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),

          // ── Override ─────────────────────────────────────────────────────
          if (_hasGenerated || _overrideEnabled) ...[
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _overrideEnabled,
              onChanged: _onOverrideToggled,
              title: Text(l10n.overrideHoroscope,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text(l10n.overrideHoroscopeSubtitle,
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
          if (_overrideEnabled) ...[
            const SizedBox(height: 8),
            // Rasi / Nakshatra / Lagnam come from the fixed Vedic master data —
            // they intentionally have NO "Others" entry, because a free-text
            // value would break porutham (star compatibility) matching.
            SearchableField(
              label: l10n.rasi,
              isRequired: true,
              items: _rasiOptions,
              selectedItem: _ovrRasi,
              prefixIcon: Icons.brightness_3_outlined,
              popupMode: SearchablePopupMode.modalBottomSheet,
              onChanged: (v) => setState(() => _ovrRasi = v),
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: l10n.nakshatra,
              isRequired: true,
              items: _nakOptions,
              selectedItem: _ovrNakshatra,
              prefixIcon: Icons.star_outline,
              popupMode: SearchablePopupMode.modalBottomSheet,
              onChanged: (v) => setState(() => _ovrNakshatra = v),
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: l10n.lagnam,
              isRequired: true,
              items: _lagnamOptions,
              selectedItem: _ovrLagnam,
              prefixIcon: Icons.wb_twilight_outlined,
              popupMode: SearchablePopupMode.modalBottomSheet,
              onChanged: (v) => setState(() => _ovrLagnam = v),
            ),
          ],

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

/// Read-only display of the calculated horoscope values. Public so the layout
/// has a direct overflow regression test (see test/horoscope_layout_test.dart).
class CalculatedHoroscopeCard extends StatelessWidget {
  final String rasi;
  final String nakshatra;
  final String lagnam;
  const CalculatedHoroscopeCard(
      {super.key,
      required this.rasi,
      required this.nakshatra,
      required this.lagnam});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Every child is either fixed-width or bounded, so this header can
          // never overflow — the title wraps to a second line on narrow phones
          // instead (the old `Spacer` + two unbounded Texts overflowed by a few
          // pixels once the labels were translated).
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.calculatedHoroscope,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Icon(Icons.lock_outline, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(l10n.readOnlyLabel,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ),
            ],
          ),
          const Divider(height: 18),
          _row(l10n.rasiMoonSign, rasi),
          _row(l10n.nakshatraStar, nakshatra),
          _row(l10n.lagnamAscendant, lagnam),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                flex: 5,
                child: Text(label,
                    style:
                        const TextStyle(color: Colors.black54, fontSize: 13))),
            Expanded(
              flex: 6,
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

/// Themed error box for generation failures.
class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red[400], size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(color: Colors.red[700], fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
