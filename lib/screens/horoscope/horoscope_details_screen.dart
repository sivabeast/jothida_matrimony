import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/dev_config.dart';
import '../../core/data/selection_data.dart';
import '../../core/services/horoscope_calculation_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/demo_data_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/searchable_field.dart';

/// Horoscope Details — generate Rasi / Nakshatra / Lagnam from birth details.
///
/// The user enters Date of Birth, Time of Birth and Birth Place and taps
/// **Generate Horoscope**. The app geocodes the place, runs the Swiss
/// Ephemeris (sidereal, Lahiri) engine via [HoroscopeCalculationService] and
/// shows the calculated values in result cards, then persists them to
/// Firestore. Re-running with changed inputs recalculates and updates.
class HoroscopeDetailsScreen extends ConsumerStatefulWidget {
  const HoroscopeDetailsScreen({super.key});

  @override
  ConsumerState<HoroscopeDetailsScreen> createState() =>
      _HoroscopeDetailsScreenState();
}

class _HoroscopeDetailsScreenState
    extends ConsumerState<HoroscopeDetailsScreen> {
  final _calc = HoroscopeCalculationService();
  final _dobController = TextEditingController();
  final _timeController = TextEditingController();

  DateTime? _dob;
  TimeOfDay? _time;
  String? _place;

  // Calculated, read-only results.
  String? _rasi;
  String? _nakshatra;
  String? _lagnam;
  bool _generated = false;

  bool _loading = false;
  bool _showValidation = false;
  String? _error;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    // Prefill immediately if the profile is already in cache.
    final p = ref.read(myProfileProvider).valueOrNull;
    if (p != null) _prefill(p);
  }

  @override
  void dispose() {
    _dobController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  /// Populate inputs/results from an existing profile (edit support).
  void _prefill(ProfileModel p) {
    if (_prefilled) return;
    _prefilled = true;
    final h = p.horoscope;
    _dob = p.dateOfBirth;
    _dobController.text = _fmtDate(p.dateOfBirth);

    final t = HoroscopeCalculationService.parseStoredTime(h.birthTime);
    if (t != null) {
      _time = t;
      _timeController.text = _fmtTime(t);
    }
    if (h.birthPlace.trim().isNotEmpty) _place = h.birthPlace.trim();

    if (h.horoscopeGenerated) {
      _rasi = h.rasi;
      _nakshatra = h.nakshatra;
      _lagnam = h.lagnam;
      _generated = h.rasi.isNotEmpty;
    }
  }

  // ── Pickers ────────────────────────────────────────────────────────────
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
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 6, minute: 30),
    );
    if (picked != null) {
      setState(() {
        _time = picked;
        _timeController.text = _fmtTime(picked);
      });
    }
  }

  // ── Generate ───────────────────────────────────────────────────────────
  Future<void> _generate() async {
    setState(() => _showValidation = true);
    final placeEmpty = _place == null || _place!.trim().isEmpty;
    if (_dob == null || _time == null || placeEmpty) {
      return; // inline field errors are shown
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _calc.calculate(
        dateOfBirth: _dob!,
        birthTime: _time!,
        birthPlace: _place!,
      );
      await _save(res);
      if (!mounted) return;
      setState(() {
        _rasi = res.rasi;
        _nakshatra = res.nakshatra;
        _lagnam = res.lagnam;
        _generated = true;
        _loading = false;
      });
    } catch (_) {
      // Any failure (geocoding, engine, validation, save) → single message.
      if (!mounted) return;
      setState(() {
        _generated = false;
        _loading = false;
        _error =
            'Unable to generate horoscope details.\nPlease verify your birth '
            'date, birth time and birth place.';
      });
    }
  }

  Future<void> _save(HoroscopeCalcResult res) async {
    final profile = ref.read(myProfileProvider).valueOrNull;
    if (profile == null) return; // nothing to attach the horoscope to
    final age = _ageFromDob(_dob!);
    final birthTime = HoroscopeCalculationService.formatStoredTime(_time!);
    final place = _place!.trim();

    if (kBypassAuth) {
      final horo = profile.horoscope.copyWith(
        birthTime: birthTime,
        birthPlace: place,
        latitude: res.latitude,
        longitude: res.longitude,
        rasi: res.rasi,
        nakshatra: res.nakshatra,
        lagnam: res.lagnam,
        horoscopeGenerated: true,
        isUserEdited: false,
      );
      ref.read(demoProfilesProvider.notifier).upsert(
            profile.copyWith(dateOfBirth: _dob!, age: age, horoscope: horo),
          );
    } else {
      await ref.read(profileRepositoryProvider).updateProfile(profile.id, {
        'dateOfBirth': Timestamp.fromDate(_dob!),
        'age': age,
        'horoscope.birthTime': birthTime,
        'horoscope.birthPlace': place,
        'horoscope.latitude': res.latitude,
        'horoscope.longitude': res.longitude,
        'horoscope.rasi': res.rasi,
        'horoscope.nakshatra': res.nakshatra,
        'horoscope.lagnam': res.lagnam,
        'horoscope.horoscopeGenerated': true,
        'horoscope.isAutoGenerated': true,
        'horoscope.isUserEdited': false,
      });
      ref.invalidate(myProfileProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prefill when the profile arrives after first build.
    ref.listen(myProfileProvider, (_, next) {
      final p = next.valueOrNull;
      if (p != null && !_prefilled && mounted) setState(() => _prefill(p));
    });

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Horoscope Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Enter your birth details to generate your Rasi, Nakshatra and '
            'Lagnam automatically.',
            style: TextStyle(color: Colors.black54, fontSize: 13.5),
          ),
          const SizedBox(height: 20),

          // Date of Birth
          AppTextField(
            controller: _dobController,
            label: 'Date of Birth',
            hint: 'Select date',
            readOnly: true,
            onTap: _pickDob,
            suffixIcon: const Icon(Icons.calendar_today_outlined),
          ),
          _fieldError(_showValidation && _dob == null,
              'Please select your date of birth'),
          const SizedBox(height: 16),

          // Time of Birth
          AppTextField(
            controller: _timeController,
            label: 'Time of Birth',
            hint: 'Select time',
            readOnly: true,
            onTap: _pickTime,
            suffixIcon: const Icon(Icons.access_time),
          ),
          _fieldError(_showValidation && _time == null,
              'Please select your time of birth'),
          const SizedBox(height: 16),

          // Birth Place
          SearchableField(
            label: 'Birth Place',
            isRequired: true,
            items: SelectionData.allCities,
            selectedItem: _place,
            prefixIcon: Icons.location_on_outlined,
            onChanged: (v) => setState(() => _place = v),
          ),
          _fieldError(
              _showValidation && (_place == null || _place!.trim().isEmpty),
              'Please select your birth place'),
          const SizedBox(height: 24),

          // Generate
          GradientButton(
            text: 'Generate Horoscope',
            isLoading: _loading,
            onPressed: _loading ? null : _generate,
          ),

          // Error
          if (_error != null) ...[
            const SizedBox(height: 20),
            _ErrorBox(message: _error!),
          ],

          // Results (hidden until generated)
          if (_generated && _error == null) ...[
            const SizedBox(height: 24),
            const Text('Your Horoscope',
                style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _ResultCard(
                icon: Icons.brightness_3_outlined,
                label: 'Rasi',
                value: _rasi ?? '—'),
            const SizedBox(height: 12),
            _ResultCard(
                icon: Icons.star_outline,
                label: 'Nakshatra',
                value: _nakshatra ?? '—'),
            const SizedBox(height: 12),
            _ResultCard(
                icon: Icons.wb_twilight_outlined,
                label: 'Lagnam',
                value: _lagnam ?? '—'),
          ],
        ],
      ),
    );
  }

  Widget _fieldError(bool show, String msg) => show
      ? Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(msg,
              style: TextStyle(color: Colors.red[600], fontSize: 12)),
        )
      : const SizedBox.shrink();

  // ── Formatting helpers ──────────────────────────────────────────────────
  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

  static String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  static int _ageFromDob(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age < 0 ? 0 : age;
  }
}

/// A single calculated-value card (modern, themed).
class _ResultCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ResultCard(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
        border: Border.all(color: AppColors.primary.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12.5)),
              const SizedBox(height: 3),
              Text(value,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins')),
            ],
          ),
        ],
      ),
    );
  }
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
