import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/dev_config.dart';
import '../../core/services/horoscope_calculation_service.dart';
import '../../core/services/master_astrology_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../models/profile_model.dart';
import '../../providers/demo_data_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/searchable_field.dart';

/// Sentinel appended to the city list for birth places not in the master data.
const String _kOthers = 'Others';

/// Horoscope Details — generate Rasi / Nakshatra / Lagnam from birth details.
///
/// Flow:
/// 1. User enters Date of Birth, Time of Birth.
/// 2. User picks a **Birth City** from the searchable master-cities dropdown,
///    or selects **Others** and types a **Custom Birth Place**.
/// 3. User taps **Generate Horoscope** — only then does the app geocode the
///    place, run the Swiss Ephemeris (sidereal, Lahiri) engine via
///    [HoroscopeCalculationService] and show the calculated Rasi/Nakshatra/
///    Lagnam, persisting them to Firestore.
/// 4. Optionally the user enables **Override Horoscope Details** to replace the
///    generated values with manual selections from the master lists.
///
/// The city/override dropdowns open as modal bottom sheets so they never
/// overlap the result cards (the previous anchored-menu overlap bug).
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
  final _customPlaceController = TextEditingController();

  DateTime? _dob;
  TimeOfDay? _time;

  // Birth place: a master city, or a free-typed custom place via "Others".
  String? _selectedCity;
  bool _isOthers = false;

  // Engine-calculated (generated) values — always preserved.
  String? _genRasi;
  String? _genNakshatra;
  String? _genLagnam;
  double? _lat;
  double? _lng;
  bool _generated = false;

  // Manual override.
  bool _overrideEnabled = false;
  String? _ovrRasi;
  String? _ovrNakshatra;
  String? _ovrLagnam;

  // Master option lists (Tamil names) for the override dropdowns.
  List<String> _rasiOptions = const [];
  List<String> _nakOptions = const [];
  List<String> _lagnamOptions = const [];

  bool _loading = false;
  bool _showValidation = false;
  String? _error;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    _loadMaster();
    // Prefill immediately if the profile is already in cache.
    final p = ref.read(myProfileProvider).valueOrNull;
    if (p != null) _prefill(p);
  }

  @override
  void dispose() {
    _dobController.dispose();
    _timeController.dispose();
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

    final place = h.birthPlace.trim();
    if (place.isNotEmpty) {
      if (h.birthPlaceType == 'custom') {
        _isOthers = true;
        _customPlaceController.text = place;
      } else {
        _selectedCity = place;
      }
    }
    _lat = h.latitude != 0 ? h.latitude : null;
    _lng = h.longitude != 0 ? h.longitude : null;

    if (h.horoscopeGenerated) {
      _genRasi = h.generatedRasi.isNotEmpty ? h.generatedRasi : h.rasi;
      _genNakshatra =
          h.generatedNakshatra.isNotEmpty ? h.generatedNakshatra : h.nakshatra;
      _genLagnam = h.generatedLagnam.isNotEmpty ? h.generatedLagnam : h.lagnam;
      _generated = (_genRasi ?? '').isNotEmpty;
      _overrideEnabled = h.overrideEnabled;
      if (_overrideEnabled) {
        _ovrRasi = h.rasi;
        _ovrNakshatra = h.nakshatra;
        _ovrLagnam = h.lagnam;
      }
    }
  }

  // ── Effective (display/save) values ──────────────────────────────────────
  String? get _effRasi => _overrideEnabled ? _ovrRasi : _genRasi;
  String? get _effNakshatra => _overrideEnabled ? _ovrNakshatra : _genNakshatra;
  String? get _effLagnam => _overrideEnabled ? _ovrLagnam : _genLagnam;

  String? get _effectivePlace =>
      _isOthers ? _customPlaceController.text.trim() : _selectedCity;

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

  void _onPlaceChanged(String? v) {
    setState(() {
      if (v == _kOthers) {
        _isOthers = true;
        _selectedCity = null;
      } else {
        _isOthers = false;
        _selectedCity = v;
        _customPlaceController.clear();
      }
    });
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
    // Override changes the effective values → persist them.
    if (_generated) _save();
  }

  // ── Generate ───────────────────────────────────────────────────────────
  Future<void> _generate() async {
    FocusScope.of(context).unfocus();
    setState(() => _showValidation = true);
    final place = _effectivePlace;
    if (_dob == null || _time == null || place == null || place.isEmpty) {
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
        birthPlace: place,
      );
      if (!mounted) return;
      setState(() {
        _genRasi = res.rasi;
        _genNakshatra = res.nakshatra;
        _genLagnam = res.lagnam;
        _lat = res.latitude;
        _lng = res.longitude;
        _generated = true;
        _loading = false;
      });
      await _save();
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

  Future<void> _save() async {
    final profile = ref.read(myProfileProvider).valueOrNull;
    if (profile == null) return; // nothing to attach the horoscope to
    final age = _ageFromDob(_dob!);
    final birthTime = HoroscopeCalculationService.formatStoredTime(_time!);
    final place = _effectivePlace ?? '';
    final placeType = _isOthers ? 'custom' : 'city';

    final effRasi = _effRasi ?? '';
    final effNak = _effNakshatra ?? '';
    final effLag = _effLagnam ?? '';

    if (kBypassAuth) {
      final horo = profile.horoscope.copyWith(
        birthTime: birthTime,
        birthPlace: place,
        birthPlaceType: placeType,
        latitude: _lat ?? 0,
        longitude: _lng ?? 0,
        rasi: effRasi,
        nakshatra: effNak,
        lagnam: effLag,
        generatedRasi: _genRasi ?? '',
        generatedNakshatra: _genNakshatra ?? '',
        generatedLagnam: _genLagnam ?? '',
        overrideEnabled: _overrideEnabled,
        horoscopeGenerated: true,
        isUserEdited: _overrideEnabled,
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
        'horoscope.birthPlaceType': placeType,
        'horoscope.latitude': _lat ?? 0,
        'horoscope.longitude': _lng ?? 0,
        'horoscope.rasi': effRasi,
        'horoscope.nakshatra': effNak,
        'horoscope.lagnam': effLag,
        'horoscope.generatedRasi': _genRasi ?? '',
        'horoscope.generatedNakshatra': _genNakshatra ?? '',
        'horoscope.generatedLagnam': _genLagnam ?? '',
        'horoscope.overrideEnabled': _overrideEnabled,
        'horoscope.horoscopeGenerated': true,
        'horoscope.isAutoGenerated': !_overrideEnabled,
        'horoscope.isUserEdited': _overrideEnabled,
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

    final citiesAsync = ref.watch(allCityNamesProvider);
    final cityItems = <String>[
      ...(citiesAsync.valueOrNull ?? const <String>[]),
      _kOthers,
    ];
    final placeMissing =
        _effectivePlace == null || _effectivePlace!.trim().isEmpty;

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

          // Birth City (searchable, modal bottom sheet so it never overlaps)
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
              label: 'Birth City',
              isRequired: true,
              items: cityItems,
              selectedItem: _isOthers ? _kOthers : _selectedCity,
              prefixIcon: Icons.location_on_outlined,
              popupMode: SearchablePopupMode.modalBottomSheet,
              onChanged: _onPlaceChanged,
            ),

          // Custom Birth Place (only when "Others" is chosen)
          if (_isOthers) ...[
            const SizedBox(height: 12),
            AppTextField(
              controller: _customPlaceController,
              label: 'Custom Birth Place',
              hint: 'Village, town or foreign / unknown place',
              prefixIcon: const Icon(Icons.edit_location_alt_outlined),
              onChanged: (_) => setState(() {}),
            ),
          ],
          _fieldError(_showValidation && placeMissing,
              'Please select or enter your birth city'),
          const SizedBox(height: 24),

          // Generate
          GradientButton(
            text: _generated ? 'Regenerate Horoscope' : 'Generate Horoscope',
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
            Row(
              children: [
                const Icon(Icons.auto_awesome,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text('Calculated Horoscope',
                    style: TextStyle(
                        fontSize: 16,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_overrideEnabled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Overridden',
                        style: TextStyle(
                            fontSize: 11, color: Colors.orange[800])),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _ResultCard(
                icon: Icons.brightness_3_outlined,
                label: 'Rasi',
                value: _effRasi ?? '—'),
            const SizedBox(height: 12),
            _ResultCard(
                icon: Icons.star_outline,
                label: 'Nakshatra',
                value: _effNakshatra ?? '—'),
            const SizedBox(height: 12),
            _ResultCard(
                icon: Icons.wb_twilight_outlined,
                label: 'Lagnam',
                value: _effLagnam ?? '—'),

            // ── Manual override ────────────────────────────────────────────
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _overrideEnabled,
              onChanged: _onOverrideToggled,
              activeColor: AppColors.primary,
              title: const Text('Override Horoscope Details',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text(
                  'Choose Rasi, Nakshatra and Lagnam manually.',
                  style: TextStyle(fontSize: 12)),
            ),
            if (_overrideEnabled) ...[
              const SizedBox(height: 8),
              SearchableField(
                label: 'Rasi',
                isRequired: true,
                items: _rasiOptions,
                selectedItem: _ovrRasi,
                prefixIcon: Icons.brightness_3_outlined,
                popupMode: SearchablePopupMode.modalBottomSheet,
                onChanged: (v) {
                  setState(() => _ovrRasi = v);
                  _save();
                },
              ),
              const SizedBox(height: 16),
              SearchableField(
                label: 'Nakshatra',
                isRequired: true,
                items: _nakOptions,
                selectedItem: _ovrNakshatra,
                prefixIcon: Icons.star_outline,
                popupMode: SearchablePopupMode.modalBottomSheet,
                onChanged: (v) {
                  setState(() => _ovrNakshatra = v);
                  _save();
                },
              ),
              const SizedBox(height: 16),
              SearchableField(
                label: 'Lagnam',
                isRequired: true,
                items: _lagnamOptions,
                selectedItem: _ovrLagnam,
                prefixIcon: Icons.wb_twilight_outlined,
                popupMode: SearchablePopupMode.modalBottomSheet,
                onChanged: (v) {
                  setState(() => _ovrLagnam = v);
                  _save();
                },
              ),
            ],
          ],

          // ── Uploaded Horoscope (PDF / image) ──────────────────────────────
          const SizedBox(height: 28),
          _uploadedHoroscopeSection(),
        ],
      ),
    );
  }

  /// Shows the user's UPLOADED horoscope documents (PDFs + images) alongside the
  /// generated one above, with View / Download actions, plus an entry point to
  /// add or manage uploads. Horoscope upload is optional.
  Widget _uploadedHoroscopeSection() {
    final h = ref.watch(myProfileProvider).valueOrNull?.horoscope;
    final pdfs = h?.allPdfUrls ?? const <String>[];
    final images = h?.horoscopeImages ?? const <String>[];
    final hasUploads = pdfs.isNotEmpty || images.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.upload_file_outlined,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('Uploaded Horoscope',
                style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => context.push('/horoscope-files'),
              icon: Icon(hasUploads ? Icons.edit_outlined : Icons.add,
                  size: 16),
              label: Text(hasUploads ? 'Manage' : 'Upload'),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!hasUploads)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Text(
              'No horoscope document uploaded yet. You can optionally upload a '
              'JPG, PNG or PDF of your horoscope (jathagam).',
              style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
            ),
          )
        else ...[
          // PDF documents — tap to view, download via the tile action.
          for (var i = 0; i < pdfs.length; i++)
            RemotePdfTile(
                url: pdfs[i],
                label: 'Horoscope Document ${i + 1}',
                index: i),
          // Image documents — thumbnails open a zoomable gallery (with download).
          if (images.isNotEmpty) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => showImageGallery(context, images, initialIndex: i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      images[i],
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 92,
                        height: 92,
                        color: Colors.grey[200],
                        child: const Icon(Icons.broken_image_outlined,
                            color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
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
