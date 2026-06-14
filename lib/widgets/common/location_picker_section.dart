import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/location_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/master_location_model.dart';
import '../../providers/master_location_provider.dart';
import 'searchable_field.dart';

/// Cascading, searchable **Country → State → District → City** picker backed by
/// the bundled JSON master data (`assets/master_data/location/*.json`), plus a
/// "📍 Use My Location" button that GPS-detects and auto-fills all fields.
///
/// Behaviour:
///  • Selecting a state loads only that state's districts; selecting a district
///    loads only that district's cities (children reset when a parent changes).
///  • Every field has a search box (provided by [SearchableField]).
///  • "Use My Location" reverse-geocodes the device position and matches the
///    detected names against the master data, then selects them. The user can
///    still override any field manually afterwards.
///  • Permission denied / failure never crashes — a friendly message is shown
///    and manual selection remains available.
///
/// The host form receives the current selection (names + lat/lng) through
/// [onChanged] and persists `state` / `district` / `city` / `latitude` /
/// `longitude`.
class LocationPickerSection extends ConsumerStatefulWidget {
  final String? initialCountry;
  final String? initialState;
  final String? initialDistrict;
  final String? initialCity;
  final double? initialLatitude;
  final double? initialLongitude;
  final ValueChanged<LocationSelection> onChanged;

  /// When true the **City** field is marked required (adds the Form validator).
  /// The State field is always required; the District field is always optional
  /// (it may be absent in the master data for some locations).
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
  String? _country;
  String? _stateId, _stateName;
  String? _districtId, _districtName;
  String? _cityId, _cityName;
  double? _lat, _lng;

  bool _detecting = false;
  String? _locError;

  @override
  void initState() {
    super.initState();
    _country = (widget.initialCountry ?? '').trim().isEmpty
        ? 'India'
        : widget.initialCountry!.trim();
    _lat = widget.initialLatitude;
    _lng = widget.initialLongitude;
    // Pre-select any saved location (edit mode) once the master data resolves.
    if ((widget.initialState ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolveInitial());
    }
  }

  // ── Edit-mode pre-selection: resolve saved names → master rows ────────────
  Future<void> _resolveInitial() async {
    try {
      final states = await ref.read(statesProvider.future);
      final st = _match(states, widget.initialState ?? '', (s) => s.name);
      if (st == null || !mounted) return;
      setState(() {
        _stateId = st.id;
        _stateName = st.name;
      });

      if ((widget.initialDistrict ?? '').trim().isEmpty) {
        _emit();
        return;
      }
      final districts = await ref.read(districtsProvider(st.id).future);
      final di = _match(districts, widget.initialDistrict ?? '', (d) => d.name);
      if (di == null || !mounted) {
        _emit();
        return;
      }
      setState(() {
        _districtId = di.id;
        _districtName = di.name;
      });

      if ((widget.initialCity ?? '').trim().isEmpty) {
        _emit();
        return;
      }
      final cities = await ref.read(citiesProvider(di.id).future);
      final ci = _match(cities, widget.initialCity ?? '', (c) => c.name);
      if (ci != null && mounted) {
        setState(() {
          _cityId = ci.id;
          _cityName = ci.name;
        });
      }
      _emit();
    } catch (_) {
      // Master data unavailable — leave fields empty for manual entry.
    }
  }

  // ── Use My Location ───────────────────────────────────────────────────────
  Future<void> _useMyLocation() async {
    setState(() {
      _detecting = true;
      _locError = null;
    });
    try {
      final loc = await LocationService().detect();
      _lat = loc.latitude;
      _lng = loc.longitude;

      // Match the detected country against the local country list (default India).
      if (loc.country.trim().isNotEmpty) {
        final countries = await ref.read(countriesProvider.future);
        final matchedCountry = _matchString(countries, loc.country);
        _country = matchedCountry ?? _country ?? 'India';
      }

      // Match the reverse-geocoded names against the master data and select.
      final states = await ref.read(statesProvider.future);
      final st = _match(states, loc.state, (s) => s.name);
      if (st != null) {
        _stateId = st.id;
        _stateName = st.name;
        _districtId = _districtName = _cityId = _cityName = null;

        final districts = await ref.read(districtsProvider(st.id).future);
        final di = _match(districts, loc.district, (d) => d.name);
        if (di != null) {
          _districtId = di.id;
          _districtName = di.name;

          final cities = await ref.read(citiesProvider(di.id).future);
          final ci = _match(cities, loc.city, (c) => c.name);
          if (ci != null) {
            _cityId = ci.id;
            _cityName = ci.name;
          }
        }
      }
      if (!mounted) return;
      setState(() {}); // reflect matched selections in the dropdowns
      _emit();
    } on LocationException catch (e) {
      if (mounted) setState(() => _locError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _locError =
            'Location access denied. Please select your location manually.');
      }
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  // ── Manual selection handlers ─────────────────────────────────────────────
  void _onCountryPicked(String? c) {
    setState(() {
      _country = c;
      // Changing country invalidates the India-specific cascade below it.
      _stateId = _stateName = null;
      _districtId = _districtName = null;
      _cityId = _cityName = null;
      _locError = null;
    });
    _emit();
  }

  void _onStatePicked(MasterState? s) {
    setState(() {
      _stateId = s?.id;
      _stateName = s?.name;
      _districtId = _districtName = null; // reset children
      _cityId = _cityName = null;
      _locError = null;
    });
    _emit();
  }

  void _onDistrictPicked(MasterDistrict? d) {
    setState(() {
      _districtId = d?.id;
      _districtName = d?.name;
      _cityId = _cityName = null; // reset child
    });
    _emit();
  }

  void _onCityPicked(MasterCity? c) {
    setState(() {
      _cityId = c?.id;
      _cityName = c?.name;
    });
    _emit();
  }

  void _emit() => widget.onChanged(LocationSelection(
        country: _country ?? 'India',
        state: _stateName ?? '',
        stateId: _stateId ?? '',
        district: _districtName ?? '',
        districtId: _districtId ?? '',
        city: _cityName ?? '',
        cityId: _cityId ?? '',
        latitude: _lat,
        longitude: _lng,
      ));

  // ── Name matching (manual exact + GPS fuzzy) ──────────────────────────────
  String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\bdistrict\b'), '')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Normalised match against a plain string list (used for Country).
  String? _matchString(List<String> list, String name) {
    final hit = _match(list, name, (s) => s);
    return hit;
  }

  T? _match<T>(List<T> list, String name, String Function(T) nameOf) {
    if (name.trim().isEmpty) return null;
    final n = _norm(name);
    if (n.isEmpty) return null;
    for (final e in list) {
      if (_norm(nameOf(e)) == n) return e; // exact (normalised)
    }
    for (final e in list) {
      final en = _norm(nameOf(e));
      if (en.isEmpty) continue;
      if (en.contains(n) || n.contains(en)) return e; // partial
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 📍 Use My Location ──
        OutlinedButton.icon(
          onPressed: _detecting ? null : _useMyLocation,
          icon: _detecting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location, size: 18),
          label: Text(_detecting ? 'Detecting…' : '📍 Use My Location'),
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
        const SizedBox(height: 16),

        _countryField(),
        const SizedBox(height: 16),
        _stateField(),
        const SizedBox(height: 16),
        _districtField(),
        const SizedBox(height: 16),
        _cityField(),

        // ── 📍 City, State summary ──
        if ((_cityName ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.place, size: 16, color: AppColors.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  [_cityName, _stateName]
                      .where((s) => (s ?? '').trim().isNotEmpty)
                      .join(', '),
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

  Widget _countryField() {
    final async = ref.watch(countriesProvider);
    return async.when(
      loading: () => _loadingField('Country', required: true),
      error: (_, __) =>
          _errorField('Country', () => ref.invalidate(countriesProvider)),
      data: (countries) => SearchableField(
        label: 'Country',
        isRequired: true,
        prefixIcon: Icons.public,
        items: countries,
        selectedItem: _country,
        onChanged: _onCountryPicked,
      ),
    );
  }

  Widget _stateField() {
    final async = ref.watch(statesProvider);
    return async.when(
      loading: () => _loadingField('State', required: true),
      error: (_, __) =>
          _errorField('State', () => ref.invalidate(statesProvider)),
      data: (states) => SearchableField(
        label: 'State',
        isRequired: true,
        prefixIcon: Icons.map_outlined,
        items: states.map((s) => s.name).toList(),
        selectedItem: _stateName,
        onChanged: (name) =>
            _onStatePicked(_match(states, name ?? '', (s) => s.name)),
      ),
    );
  }

  Widget _districtField() {
    if (_stateId == null) {
      return SearchableField(
        label: 'District',
        items: const [],
        selectedItem: null,
        enabled: false,
        prefixIcon: Icons.account_balance_outlined,
        onChanged: (_) {},
      );
    }
    final async = ref.watch(districtsProvider(_stateId!));
    return async.when(
      loading: () => _loadingField('District'),
      error: (_, __) => _errorField(
          'District', () => ref.invalidate(districtsProvider(_stateId!))),
      data: (districts) => SearchableField(
        label: 'District',
        isRequired: false, // District is optional (may be absent for a location)
        prefixIcon: Icons.account_balance_outlined,
        items: districts.map((d) => d.name).toList(),
        selectedItem: _districtName,
        onChanged: (name) =>
            _onDistrictPicked(_match(districts, name ?? '', (d) => d.name)),
      ),
    );
  }

  Widget _cityField() {
    if (_districtId == null) {
      return SearchableField(
        label: 'City',
        isRequired: widget.isRequired,
        items: const [],
        selectedItem: null,
        enabled: false,
        prefixIcon: Icons.location_city,
        onChanged: (_) {},
      );
    }
    final async = ref.watch(citiesProvider(_districtId!));
    return async.when(
      loading: () => _loadingField('City', required: widget.isRequired),
      error: (_, __) => _errorField(
          'City', () => ref.invalidate(citiesProvider(_districtId!))),
      data: (cities) => SearchableField(
        label: 'City',
        isRequired: widget.isRequired,
        prefixIcon: Icons.location_city,
        items: cities.map((c) => c.name).toList(),
        selectedItem: _cityName,
        onChanged: (name) =>
            _onCityPicked(_match(cities, name ?? '', (c) => c.name)),
      ),
    );
  }

  /// A disabled field showing a spinner while its options load.
  Widget _loadingField(String label, {bool required = false}) => InputDecorator(
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          children: [
            const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('Loading $label…',
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ],
        ),
      );

  Widget _errorField(String label, VoidCallback onRetry) => InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text('Couldn\'t load ${label.toLowerCase()}s',
                  style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
