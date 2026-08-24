import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/dev_config.dart';
import '../../core/services/horoscope_calculation_service.dart';
import '../../core/services/master_astrology_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/location_model.dart';
import '../../models/profile_model.dart';
import '../../providers/demo_data_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/calculated_horoscope_card.dart';
import '../../widgets/common/place_picker_field.dart';

/// Horoscope Details — generate Rasi / Nakshatra / Lagnam from birth details.
///
/// The same structure as the profile wizard's Horoscope step (§13), so a
/// member sees one horoscope form wherever they reach it:
/// 1. Date of Birth, Time of Birth.
/// 2. Place of Birth, through the app's ONE place picker.
/// 3. **Generate Horoscope** geocodes the place, runs the Swiss Ephemeris
///    (sidereal, Lahiri) engine via [HoroscopeCalculationService] and shows the
///    calculated Rasi / Nakshatra / Lagnam, persisting them to Firestore.
/// 4. Each of those three values is then **editable directly inside the
///    Calculated Horoscope card** (§12). The "Override Horoscope Details"
///    switch is gone (§11) — there is no edit mode to turn on; an edit saves
///    immediately, and the engine's own values are always preserved alongside.
///
/// Every picker opens as a modal bottom sheet so a list never overlaps the
/// result card (the previous anchored-menu overlap bug).
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

  /// Birth place as "City, District, State" (or a free-typed place), chosen in
  /// the app's ONE place picker (spec §31). The district + state also make the
  /// geocoding lookup unambiguous for repeated village names.
  String? _birthPlace;
  bool _placeIsCustom = false;

  // Engine-calculated (generated) values — always preserved.
  String? _genRasi;
  String? _genNakshatra;
  String? _genLagnam;
  double? _lat;
  double? _lng;
  bool _generated = false;

  // The member's own edits. Null means "use what the engine calculated".
  String? _ovrRasi;
  String? _ovrNakshatra;
  String? _ovrLagnam;

  // Master option lists (Tamil names) for the in-card pickers.
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
      _birthPlace = place;
      _placeIsCustom = h.birthPlaceType == 'custom';
    }
    _lat = h.latitude != 0 ? h.latitude : null;
    _lng = h.longitude != 0 ? h.longitude : null;

    if (h.horoscopeGenerated) {
      _genRasi = h.generatedRasi.isNotEmpty ? h.generatedRasi : h.rasi;
      _genNakshatra =
          h.generatedNakshatra.isNotEmpty ? h.generatedNakshatra : h.nakshatra;
      _genLagnam = h.generatedLagnam.isNotEmpty ? h.generatedLagnam : h.lagnam;
      _generated = (_genRasi ?? '').isNotEmpty;
      // A saved value that differs from the generated one is a member edit,
      // whether or not the (removed) override flag was ever set.
      if (h.rasi.isNotEmpty && h.rasi != _genRasi) _ovrRasi = h.rasi;
      if (h.nakshatra.isNotEmpty && h.nakshatra != _genNakshatra) {
        _ovrNakshatra = h.nakshatra;
      }
      if (h.lagnam.isNotEmpty && h.lagnam != _genLagnam) _ovrLagnam = h.lagnam;
    }
  }

  // ── Effective (display/save) values ──────────────────────────────────────
  // A member edit wins over the calculated value; otherwise the engine's
  // result is what shows and what is saved.
  String? get _effRasi => _ovrRasi ?? _genRasi;
  String? get _effNakshatra => _ovrNakshatra ?? _genNakshatra;
  String? get _effLagnam => _ovrLagnam ?? _genLagnam;

  /// True once the member has changed any value away from what was
  /// calculated. Replaces the old override switch — DERIVED, never toggled.
  bool get _isUserEdited =>
      (_ovrRasi != null && _ovrRasi != _genRasi) ||
      (_ovrNakshatra != null && _ovrNakshatra != _genNakshatra) ||
      (_ovrLagnam != null && _ovrLagnam != _genLagnam);

  String? get _effectivePlace => _birthPlace?.trim();

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

  void _onPlaceChanged(PlaceSelection p) {
    setState(() {
      _birthPlace = p.display;
      _placeIsCustom = p.custom;
    });
  }

  /// A value edited inside the Calculated Horoscope card. The change is saved
  /// straight away — there is no separate confirm step.
  void _onValueEdited(void Function() apply) {
    setState(apply);
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
    final placeType = _placeIsCustom ? 'custom' : 'city';

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
        overrideEnabled: _isUserEdited,
        horoscopeGenerated: true,
        isUserEdited: _isUserEdited,
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
        // Derived from the values themselves — there is no override switch
        // any more (§11). Still written so existing readers (the astrologer
        // report, the website) keep working unchanged.
        'horoscope.overrideEnabled': _isUserEdited,
        'horoscope.horoscopeGenerated': true,
        'horoscope.isAutoGenerated': !_isUserEdited,
        'horoscope.isUserEdited': _isUserEdited,
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

    final placeMissing =
        _effectivePlace == null || _effectivePlace!.trim().isEmpty;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(context.l10n.horoscopeDetails),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      // One clean vertical rhythm (§10): description, the three birth-detail
      // fields evenly spaced, Generate, then the Calculated Horoscope card and
      // the uploaded documents. Nothing overlaps and nothing is clipped.
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          Text(
            context.l10n.horoscopeStepSubtitle,
            style: const TextStyle(
                color: Colors.black54, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 24),

          // ── Birth details ────────────────────────────────────────────────
          AppTextField(
            controller: _dobController,
            label: '${context.l10n.dateOfBirth} *',
            hint: context.l10n.selectDateHint,
            readOnly: true,
            onTap: _pickDob,
            suffixIcon: const Icon(Icons.calendar_today_outlined),
          ),
          _fieldError(_showValidation && _dob == null,
              context.l10n.pleaseSelect(context.l10n.dateOfBirth)),
          const SizedBox(height: 18),
          AppTextField(
            controller: _timeController,
            label: '${context.l10n.timeOfBirth} *',
            hint: context.l10n.selectTimeHint,
            readOnly: true,
            onTap: _pickTime,
            suffixIcon: const Icon(Icons.access_time),
          ),
          _fieldError(_showValidation && _time == null,
              context.l10n.pleaseSelectTimeOfBirth),
          const SizedBox(height: 18),
          PlacePickerField(
            label: context.l10n.placeOfBirthLabel,
            isRequired: true,
            value: _birthPlace,
            onChanged: _onPlaceChanged,
          ),
          _fieldError(_showValidation && placeMissing,
              context.l10n.pleaseSelectBirthPlace),
          const SizedBox(height: 28),

          // ── Generate ─────────────────────────────────────────────────────
          GradientButton(
            text: _generated
                ? context.l10n.regenerateHoroscope
                : context.l10n.generateHoroscope,
            isLoading: _loading,
            onPressed: _loading ? null : _generate,
          ),

          if (_error != null) ...[
            const SizedBox(height: 24),
            HoroscopeErrorBox(message: _error!),
          ],

          // ── Calculated Horoscope — each value editable in place (§12) ────
          if (_generated && _error == null) ...[
            const SizedBox(height: 28),
            CalculatedHoroscopeCard(
              rasi: _effRasi ?? '',
              nakshatra: _effNakshatra ?? '',
              lagnam: _effLagnam ?? '',
              rasiOptions: _rasiOptions,
              nakshatraOptions: _nakOptions,
              lagnamOptions: _lagnamOptions,
              onRasiChanged: (v) => _onValueEdited(() => _ovrRasi = v),
              onNakshatraChanged: (v) =>
                  _onValueEdited(() => _ovrNakshatra = v),
              onLagnamChanged: (v) => _onValueEdited(() => _ovrLagnam = v),
            ),
          ],

          // ── Uploaded Horoscope (PDF / image) ─────────────────────────────
          const SizedBox(height: 32),
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
            Text(context.l10n.horoscopeDocuments,
                style: const TextStyle(
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
