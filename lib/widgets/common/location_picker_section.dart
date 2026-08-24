import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/location_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/location_model.dart';
import '../../providers/locale_provider.dart';
import '../../providers/location_provider.dart';
import 'place_picker_field.dart';

/// The app's ONE location picker — a single **City** field plus **Use My
/// Location** (spec §7).
///
///  • The member answers ONE question: which city or town are they in. The
///    separate State / District / City dropdowns were removed: they asked for
///    the same answer three times and duplicated the city field above them.
///  • State and District are still RESOLVED and emitted — the place picker
///    returns City/Village + District + State together, so every stored
///    profile keeps its full location mapping and existing matching, filtering
///    and export code is untouched. That relationship is maintained
///    internally; it is simply no longer something the member has to type.
///  • Labels and option names follow the app language (English / Tamil) from
///    the master rows, but the values EMITTED are always the canonical English
///    name + stable numeric id — so stored profiles are language-independent
///    and existing data keeps working.
///  • "📍 Use My Location" reverse-geocodes the device position and matches it
///    against the master data (Tamil Nadu only — anything else asks for a
///    manual pick). Failures never crash; a friendly message is shown.
///  • A saved value that no longer exists in the master data (legacy custom
///    entries) is still displayed so old profiles render unchanged.
class LocationPickerSection extends ConsumerStatefulWidget {
  final String? initialCountry; // legacy parameter — country is always India
  final String? initialState;
  final String? initialDistrict;
  final String? initialCity;
  final double? initialLatitude;
  final double? initialLongitude;
  final ValueChanged<LocationSelection> onChanged;

  /// When true District and City are required (adds the Form validators).
  final bool isRequired;

  const LocationPickerSection({
    super.key,
    this.initialCountry,
    this.initialState,
    this.initialDistrict,
    this.initialCity,
    this.initialLatitude,
    this.initialLongitude,
    required this.onChanged,
    this.isRequired = true,
  });

  @override
  ConsumerState<LocationPickerSection> createState() =>
      _LocationPickerSectionState();
}

class _LocationPickerSectionState extends ConsumerState<LocationPickerSection> {
  TnDistrict? _district;
  TnCity? _city;

  // Legacy saved values that don't resolve to master rows (old custom
  // entries) — kept only for DISPLAY so existing profiles stay readable.
  String? _legacyDistrict;
  String? _legacyCity;

  double? _lat, _lng;
  bool _detecting = false;
  String? _locError;

  String get _lang => ref.watch(localeProvider)?.languageCode ?? 'en';

  /// Field labels come from the shared l10n dictionary, so they follow the
  /// selected language exactly like every other label in the wizard.
  String _label(String key) => switch (key) {
        'state' => context.l10n.state,
        'district' => context.l10n.district,
        _ => context.l10n.city,
      };

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLatitude;
    _lng = widget.initialLongitude;
    if ((widget.initialDistrict ?? '').trim().isNotEmpty ||
        (widget.initialCity ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolveInitial());
    }
  }

  // ── Edit-mode pre-selection: resolve saved names → master rows ────────────
  Future<void> _resolveInitial() async {
    try {
      final repo = ref.read(locationRepositoryProvider);
      final savedDistrict = (widget.initialDistrict ?? '').trim();
      final savedCity = (widget.initialCity ?? '').trim();

      var district = await repo.findDistrict(savedDistrict);
      var city = await repo.findCity(savedCity,
          districtId: district?.id);
      // A saved city under a legacy/renamed district can still locate its
      // district through the city row itself.
      if (district == null && savedCity.isNotEmpty) {
        city ??= await repo.findCity(savedCity);
        if (city != null) district = await repo.districtById(city.districtId);
      }

      if (!mounted) return;
      setState(() {
        _district = district;
        _legacyDistrict =
            district == null && savedDistrict.isNotEmpty ? savedDistrict : null;
        _city = city;
        _legacyCity = city == null && savedCity.isNotEmpty ? savedCity : null;
      });
      _emit();
    } catch (_) {
      // Master data unavailable — leave the fields empty for manual entry.
    }
  }

  // ── Use My Location — match against the Tamil Nadu master data ────────────
  Future<void> _useMyLocation() async {
    setState(() {
      _detecting = true;
      _locError = null;
    });
    try {
      final loc = await LocationService().detect();
      _lat = loc.latitude;
      _lng = loc.longitude;

      final repo = ref.read(locationRepositoryProvider);
      final inTn = loc.state.trim().isEmpty ||
          loc.state.toLowerCase().contains('tamil') ||
          loc.state.contains('தமிழ');
      if (!inTn) {
        setState(() =>
            _locError = context.l10n.onlyTamilNaduSupported(loc.state));
        return;
      }

      // District: the detected district, else the detected city's name (GPS
      // often reports city == district for towns), else locate via the city.
      var district = await repo.findDistrict(loc.district) ??
          await repo.findDistrict(loc.city);
      TnCity? city;
      if (district != null) {
        city = await repo.findCity(loc.city, districtId: district.id) ??
            await repo.findCity(loc.district, districtId: district.id);
      } else {
        city = await repo.findCity(loc.city);
        if (city != null) district = await repo.districtById(city.districtId);
      }

      if (!mounted) return;
      setState(() {
        if (district != null) {
          _district = district;
          _legacyDistrict = null;
          _city = city;
          _legacyCity = null;
          if (city == null && loc.city.trim().isNotEmpty) {
            _locError = context.l10n.cityNotInListPickNearest(loc.city);
          }
        } else {
          _locError = context.l10n.couldNotMatchLocation;
        }
      });
      _emit();
    } on LocationException catch (e) {
      if (mounted) setState(() => _locError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _locError = context.l10n.locationAccessDenied);
      }
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  /// A place chosen in the shared search picker → set BOTH dropdowns at once.
  /// A free-typed place has no master row, so it is kept as a legacy display
  /// value exactly like an old profile's custom entry.
  Future<void> _onPlaceSearched(PlaceSelection p) async {
    final repo = ref.read(locationRepositoryProvider);
    final district = p.custom
        ? null
        : await repo.findDistrict(
            p.districtEn.isNotEmpty ? p.districtEn : p.district);
    final city = p.custom
        ? null
        : await repo.findCity(p.cityEn.isNotEmpty ? p.cityEn : p.city,
            districtId: district?.id);
    if (!mounted) return;
    setState(() {
      _district = district;
      _legacyDistrict =
          district == null && p.district.trim().isNotEmpty ? p.district : null;
      _city = city;
      _legacyCity = city == null && p.city.trim().isNotEmpty ? p.city : null;
      _locError = null;
    });
    _emit();
  }

  void _emit() => widget.onChanged(LocationSelection(
        country: 'India',
        state: TnState.nameEn,
        stateId: TnState.id,
        district: _district?.nameEn ?? _legacyDistrict ?? '',
        districtId: _district?.id.toString() ?? '',
        city: _city?.nameEn ?? _legacyCity ?? '',
        cityId: _city?.id.toString() ?? '',
        latitude: _lat,
        longitude: _lng,
      ));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── City * — the ONE location field the member fills in ──
        PlacePickerField(
          label: _label('city'),
          isRequired: widget.isRequired,
          value: _city == null
              ? (_legacyCity ?? '')
              : '${_city!.nameFor(_lang)}, ${_district?.nameFor(_lang) ?? ''}, ${TnState.nameFor(_lang)}',
          onChanged: _onPlaceSearched,
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(context.l10n.locationCityOnlyHint,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
        ),
        const SizedBox(height: 12),
        // ── 📍 Use My Location ──
        OutlinedButton.icon(
          onPressed: _detecting ? null : _useMyLocation,
          icon: _detecting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location, size: 18),
          label: Text(_detecting
              ? context.l10n.detectingLocation
              : '📍 ${context.l10n.useMyLocation}'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            minimumSize: const Size.fromHeight(44),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        if (_locError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(_locError!,
                style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
          ),

        // ── 📍 City, State summary — confirms what was resolved ──
        if (_city != null || (_legacyCity ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.place, size: 16, color: AppColors.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '${_city?.nameFor(_lang) ?? _legacyCity}, ${TnState.nameFor(_lang)}',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
