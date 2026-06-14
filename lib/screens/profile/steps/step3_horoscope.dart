import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/horoscope_calculation_service.dart';
import '../../../core/services/master_astrology_data.dart';
import '../../../providers/master_location_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/searchable_field.dart';

/// Sentinel appended to the city list for "not in the list" birth places.
const String _kOthers = 'Others';

/// Step 3 — Horoscope.
///
/// Rasi / Nakshatra / Lagnam are calculated automatically from Date of Birth +
/// Time of Birth + Birth Place via the Vedic engine. Birth Place is a
/// searchable dropdown over the master cities (with an "Others" → custom input
/// escape hatch). Users may optionally **override** the calculated values with
/// manually-chosen ones from the master Rasi / Nakshatra / Lagnam lists.
class Step3Horoscope extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const Step3Horoscope({super.key, required this.onNext});

  @override
  ConsumerState<Step3Horoscope> createState() => _Step3State();
}

class _Step3State extends ConsumerState<Step3Horoscope> {
  final _calc = HoroscopeCalculationService();
  final _birthTimeController = TextEditingController();
  final _dobController = TextEditingController();
  final _customPlaceController = TextEditingController();
  Timer? _customDebounce;

  DateTime? _dob;
  TimeOfDay? _birthTime;

  // Birth place
  String? _selectedCity; // when a master city is chosen
  bool _isOthers = false; // "Others" → custom text input

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
    _customDebounce?.cancel();
    _birthTimeController.dispose();
    _dobController.dispose();
    _customPlaceController.dispose();
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
        if (type == 'custom') {
          _isOthers = true;
          _customPlaceController.text = place;
        } else {
          _selectedCity = place;
        }
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

  String? get _effectivePlace =>
      _isOthers ? _customPlaceController.text.trim() : _selectedCity;

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

  void _onPlaceChanged(String? v) {
    setState(() {
      if (v == _kOthers) {
        _isOthers = true;
        _selectedCity = null;
      } else {
        _isOthers = false;
        _selectedCity = v;
      }
    });
    if (!_isOthers) _recalculate();
  }

  void _onCustomPlaceChanged(String v) {
    _customDebounce?.cancel();
    _customDebounce =
        Timer(const Duration(milliseconds: 700), () => _recalculate());
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
    final messenger = ScaffoldMessenger.of(context);
    if (_dob == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Please select your date of birth')));
      return;
    }
    if (_birthTime == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Please select your time of birth')));
      return;
    }
    if (_effectivePlace == null || _effectivePlace!.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Please select your birth place')));
      return;
    }
    if ((_effRasi ?? '').isEmpty ||
        (_effNakshatra ?? '').isEmpty ||
        (_effLagnam ?? '').isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text(
          'Unable to generate horoscope details. Please verify date, time and '
          'birth place.')));
      return;
    }

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
        'birthPlaceType': _isOthers ? 'custom' : 'city',
        'latitude': _lat ?? 0,
        'longitude': _lng ?? 0,
        'horoscopeGenerated': true,
        'isAutoGenerated': !_overrideEnabled,
        'isUserEdited': _overrideEnabled,
        'isAstrologerVerified': false,
      },
    });
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final citiesAsync = ref.watch(allCityNamesProvider);
    final cityItems = <String>[
      ...(citiesAsync.valueOrNull ?? const <String>[]),
      _kOthers,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Horoscope Details',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Rasi, Nakshatra and Lagnam are calculated automatically from your '
            'birth date, time and place. Enable override to set them manually.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),

          // ── Inputs ──────────────────────────────────────────────────────
          AppTextField(
            controller: _dobController,
            label: 'Date of Birth',
            hint: 'Select date',
            readOnly: true,
            onTap: _pickDob,
            suffixIcon: const Icon(Icons.calendar_today_outlined),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _birthTimeController,
            label: 'Time of Birth',
            hint: 'Select time',
            readOnly: true,
            onTap: _pickTime,
            suffixIcon: const Icon(Icons.access_time),
          ),
          const SizedBox(height: 16),
          if (citiesAsync.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Loading cities…'),
              ]),
            )
          else
            SearchableField(
              label: 'Birth Place',
              isRequired: true,
              items: cityItems,
              selectedItem: _isOthers ? _kOthers : _selectedCity,
              prefixIcon: Icons.location_on_outlined,
              onChanged: _onPlaceChanged,
            ),
          if (_isOthers) ...[
            const SizedBox(height: 12),
            AppTextField(
              controller: _customPlaceController,
              label: 'Custom Birth Place',
              hint: 'Village, town or city name',
              prefixIcon: const Icon(Icons.edit_location_alt_outlined),
              onChanged: _onCustomPlaceChanged,
            ),
          ],
          const SizedBox(height: 24),

          // ── Status / generated results ───────────────────────────────────
          if (_calculating)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Calculating horoscope…'),
              ]),
            )
          else if (_error != null)
            _ErrorBox(message: _error!)
          else if (_hasGenerated && !_overrideEnabled)
            _ResultCard(
                rasi: _genRasi!, nakshatra: _genNakshatra!, lagnam: _genLagnam!)
          else if (!_hasGenerated)
            Text(
              'Select date, time and place to calculate your horoscope.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),

          // ── Override ─────────────────────────────────────────────────────
          if (_hasGenerated || _overrideEnabled) ...[
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _overrideEnabled,
              onChanged: _onOverrideToggled,
              title: const Text('Override automatically calculated horoscope',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: const Text(
                  'Choose Rasi, Nakshatra and Lagnam manually.',
                  style: TextStyle(fontSize: 12)),
            ),
          ],
          if (_overrideEnabled) ...[
            const SizedBox(height: 8),
            SearchableField(
              label: 'Rasi',
              isRequired: true,
              items: _rasiOptions,
              selectedItem: _ovrRasi,
              prefixIcon: Icons.brightness_3_outlined,
              onChanged: (v) => setState(() => _ovrRasi = v),
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: 'Nakshatra',
              isRequired: true,
              items: _nakOptions,
              selectedItem: _ovrNakshatra,
              prefixIcon: Icons.star_outline,
              onChanged: (v) => setState(() => _ovrNakshatra = v),
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: 'Lagnam',
              isRequired: true,
              items: _lagnamOptions,
              selectedItem: _ovrLagnam,
              prefixIcon: Icons.wb_twilight_outlined,
              onChanged: (v) => setState(() => _ovrLagnam = v),
            ),
          ],

          const SizedBox(height: 32),
          GradientButton(onPressed: _saveAndNext, text: 'Next'),
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

/// Read-only display of the calculated horoscope values.
class _ResultCard extends StatelessWidget {
  final String rasi;
  final String nakshatra;
  final String lagnam;
  const _ResultCard(
      {required this.rasi, required this.nakshatra, required this.lagnam});

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: Colors.amber),
              const SizedBox(width: 8),
              const Text('Calculated Horoscope',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Icon(Icons.lock_outline, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text('Read-only',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
          ),
          const Divider(height: 18),
          _row('Rasi (Moon Sign)', rasi),
          _row('Nakshatra (Star)', nakshatra),
          _row('Lagnam (Ascendant)', lagnam),
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
