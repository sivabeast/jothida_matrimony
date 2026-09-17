import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/location_catalog.dart';
import '../../core/data/master_option.dart';
import '../../core/services/location_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/place_additions.dart';
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
///  • A place the member ADDS (see [PlacePickerField]) is emitted like any
///    other: under a Tamil Nadu district it is a real town row with its own
///    id; in another state or country it carries that state / country.
class LocationPickerSection extends ConsumerStatefulWidget {
  final String? initialCountry;
  final String? initialState;
  final String? initialDistrict;
  final String? initialCity;

  /// The saved city id — resolves a member-added place (whose id is in the
  /// added range) even before the live list of added places has arrived.
  final String? initialCityId;
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
    this.initialCityId,
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
      final savedCityId = int.tryParse((widget.initialCityId ?? '').trim());

      TnCity? city;
      if (savedCityId != null) {
        if (savedCityId >= kFirstAddedPlaceId) {
          // A member-added place: make sure the added places are merged
          // before resolving it, or it would reopen as bare text and lose its
          // id on the next save.
          try {
            repo.mergeAdditions(await ref
                .read(placeAdditionsProvider.future)
                .timeout(const Duration(seconds: 6)));
          } catch (_) {
            // Offline / unavailable — the name fallback below still shows it.
          }
        }
        city = await repo.cityById(savedCityId);
      }
      var district = city != null
          ? await repo.districtById(city.districtId)
          : await repo.findDistrict(savedDistrict);
      city ??= await repo.findCity(savedCity, districtId: district?.id);
      // A saved city under a legacy/renamed district can still locate its
      // district through the city row itself.
      if (district == null && savedCity.isNotEmpty) {
        city ??= await repo.findCity(savedCity);
        if (city != null) district = await repo.districtById(city.districtId);
      }

      if (!mounted) return;
      final savedState = (widget.initialState ?? '').trim();
      final savedCountry = (widget.initialCountry ?? '').trim();
      setState(() {
        _district = district;
        _legacyDistrict =
            district == null && savedDistrict.isNotEmpty ? savedDistrict : null;
        _city = city;
        _legacyCity = city == null && savedCity.isNotEmpty ? savedCity : null;
        // Re-editing a place outside Tamil Nadu must not silently re-home it.
        _customState = city == null &&
                savedState.isNotEmpty &&
                savedState != TnState.nameEn
            ? savedState
            : null;
        _customCountry = city == null &&
                savedCountry.isNotEmpty &&
                savedCountry != kDefaultCountry
            ? savedCountry
            : null;
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
          _customState = null;
          _customCountry = null;
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
  /// A place with no town row (custom) is kept as a display value exactly like
  /// an old profile's custom entry — under its district when it has one.
  Future<void> _onPlaceSearched(PlaceSelection p) async {
    final repo = ref.read(locationRepositoryProvider);
    // The picker returns the EXACT rows by id — resolving them again by name
    // could land on a different town that shares the name, or on the district
    // when district and town are spelt alike. Names are only a fallback for a
    // selection without ids.
    TnCity? city;
    TnDistrict? district;
    if (p.districtId != null) {
      district = await repo.districtById(p.districtId!);
    }
    if (!p.custom) {
      if (p.cityId != null) city = await repo.cityById(p.cityId!);
      district ??= await repo
          .findDistrict(p.districtEn.isNotEmpty ? p.districtEn : p.district);
      city ??= await repo.findCity(p.cityEn.isNotEmpty ? p.cityEn : p.city,
          districtId: district?.id);
    }
    if (!mounted) return;
    final cityName = p.cityEn.trim().isNotEmpty ? p.cityEn : p.city;
    setState(() {
      _district = district;
      _legacyDistrict =
          district == null && p.district.trim().isNotEmpty ? p.district : null;
      _city = city;
      _legacyCity = city == null && cityName.trim().isNotEmpty ? cityName : null;
      // A place outside the listed data keeps the state / country it names.
      _customState = p.custom && district == null && p.state.trim().isNotEmpty
          ? p.state
          : null;
      _customCountry = p.custom &&
              p.country.trim().isNotEmpty &&
              p.country.trim() != kDefaultCountry
          ? p.country
          : null;
      _locError = null;
    });
    _emit();
  }

  /// The state of a place outside Tamil Nadu ("Kochi, Kerala").
  String? _customState;

  /// The country of a place outside India ("Dubai, UAE").
  String? _customCountry;

  void _emit() {
    final customCountry = _city == null ? _customCountry : null;
    final customState = _city == null ? _customState : null;
    // A place abroad has no Indian state.
    final state = customCountry != null
        ? (customState ?? '')
        : (customState ?? TnState.nameEn);
    widget.onChanged(LocationSelection(
      country: customCountry ?? kDefaultCountry,
      state: state,
      stateId: customState == null && customCountry == null
          ? TnState.id
          : (LocationCatalog.indianStates.byValue(state)?.id ?? ''),
      district: _district?.nameEn ?? _legacyDistrict ?? '',
      districtId: _district?.id.toString() ?? '',
      city: _city?.nameEn ?? _legacyCity ?? '',
      cityId: _city?.id.toString() ?? '',
      latitude: _lat,
      longitude: _lng,
    ));
  }

  /// "City, District, Tamil Nadu" for a town; a place without a town row
  /// still names its district, state or country when it has one.
  String get _displayValue {
    if (_city != null) {
      return '${_city!.nameFor(_lang)}, ${_district?.nameFor(_lang) ?? ''}, '
          '${TnState.nameFor(_lang)}';
    }
    final legacy = (_legacyCity ?? '').trim();
    if (legacy.isEmpty) return '';
    return [
      legacy,
      if (_district != null) ...[
        _district!.nameFor(_lang),
        TnState.nameFor(_lang),
      ] else ...[
        _customState ?? '',
        _customCountry ?? '',
      ],
    ].where((s) => s.trim().isNotEmpty).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── City * — the ONE location field the member fills in ──
        PlacePickerField(
          label: _label('city'),
          isRequired: widget.isRequired,
          // An unlisted place is ADDED from the picker under its district,
          // state or country — never stored as a bare, unplaced name.
          value: _displayValue,
          onChanged: _onPlaceSearched,
        ),
        const SizedBox(height: 10),
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
        // The resolved place already reads back inside the field above, so
        // there is no second "City, State" summary line under it — one answer
        // is shown once.
        if (_locError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 2),
            child: Text(_locError!,
                style: const TextStyle(
                    color: AppColors.error, fontSize: 12.5, height: 1.35)),
          ),
      ],
    );
  }
}
