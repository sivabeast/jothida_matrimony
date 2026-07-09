import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/location_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/master_location_model.dart';
import '../../providers/master_location_provider.dart';
import '../../providers/master_options_provider.dart';
import 'searchable_field.dart';

/// Cascading, searchable **State → District → City** picker backed by the
/// bundled JSON master data (`assets/master_data/location/*.json`) PLUS the
/// Firestore `master_options` overlay of user-added values, with a
/// "📍 Use My Location" button that GPS-detects and auto-fills all fields.
///
/// Behaviour:
///  • There is NO Country dropdown (removed per spec) — the app serves India.
///  • Selecting a state loads only that state's districts; selecting a district
///    loads only that district's cities (children reset when a parent changes).
///  • Every field has a search box AND a "+" Add button — a missing state /
///    district / city is saved PERMANENTLY to the master database and becomes
///    visible to every user immediately (this replaced "Others → textbox").
///  • "Use My Location" reverse-geocodes the device position and maps it
///    INTELLIGENTLY to the nearest available master entries: exact → partial
///    match on state/district/city, district falls back to matching the
///    detected city name, and an unmatched locality (e.g. a small village)
///    still fills the City field as a custom value instead of failing.
///  • Permission denied / failure never crashes — a friendly message is shown
///    and manual selection remains available.
///
/// The host form receives the current selection (names + lat/lng) through
/// [onChanged] and persists `state` / `district` / `city` / `latitude` /
/// `longitude`. `country` is always reported as India.
class LocationPickerSection extends ConsumerStatefulWidget {
  final String? initialCountry; // legacy parameter — country was removed
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
  String? _stateId, _stateName;
  String? _districtId, _districtName;
  String? _cityId, _cityName;
  double? _lat, _lng;

  bool _detecting = false;
  String? _locError;

  @override
  void initState() {
    super.initState();
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
      if (!mounted) return;
      setState(() {
        if (st != null) {
          _stateId = st.id;
          _stateName = st.name;
        } else {
          // A saved CUSTOM state (user-added) — keep showing it.
          _stateName = widget.initialState!.trim();
          _stateId = null;
        }
      });

      final savedDistrict = (widget.initialDistrict ?? '').trim();
      if (savedDistrict.isNotEmpty) {
        MasterDistrict? di;
        if (st != null) {
          final districts = await ref.read(districtsProvider(st.id).future);
          di = _match(districts, savedDistrict, (d) => d.name);
        }
        if (!mounted) return;
        setState(() {
          _districtId = di?.id;
          _districtName = di?.name ?? savedDistrict;
        });
      }

      final savedCity = (widget.initialCity ?? '').trim();
      if (savedCity.isNotEmpty) {
        MasterCity? ci;
        if (_districtId != null) {
          final cities = await ref.read(citiesProvider(_districtId!).future);
          ci = _match(cities, savedCity, (c) => c.name);
        }
        if (!mounted) return;
        setState(() {
          _cityId = ci?.id;
          _cityName = ci?.name ?? savedCity;
        });
      }
      _emit();
    } catch (_) {
      // Master data unavailable — leave fields empty for manual entry.
    }
  }

  // ── Use My Location — intelligent nearest-available mapping ───────────────
  Future<void> _useMyLocation() async {
    setState(() {
      _detecting = true;
      _locError = null;
    });
    try {
      final loc = await LocationService().detect();
      _lat = loc.latitude;
      _lng = loc.longitude;

      // 1. State — exact/partial match against the master list.
      final states = await ref.read(statesProvider.future);
      final st = _match(states, loc.state, (s) => s.name);
      if (st != null) {
        _stateId = st.id;
        _stateName = st.name;
        _districtId = _districtName = _cityId = _cityName = null;

        // 2. District — try the detected district, then the detected CITY name
        //    (GPS often reports city == district for towns).
        final districts = await ref.read(districtsProvider(st.id).future);
        final di = _match(districts, loc.district, (d) => d.name) ??
            _match(districts, loc.city, (d) => d.name);
        if (di != null) {
          _districtId = di.id;
          _districtName = di.name;

          // 3. City — detected city, then sub-locality/district as fallbacks;
          //    an unmatched locality (e.g. "Pacharpalayam") still fills the
          //    field as a CUSTOM city so auto-selection never fails.
          final cities = await ref.read(citiesProvider(di.id).future);
          final ci = _match(cities, loc.city, (c) => c.name) ??
              _match(cities, loc.district, (c) => c.name);
          if (ci != null) {
            _cityId = ci.id;
            _cityName = ci.name;
          } else if (loc.city.trim().isNotEmpty) {
            _cityId = null;
            _cityName = loc.city.trim();
          }
        } else if (loc.city.trim().isNotEmpty) {
          // No district match at all — still surface the detected place.
          _cityId = null;
          _cityName = loc.city.trim();
        }
      } else if (loc.city.trim().isNotEmpty || loc.state.trim().isNotEmpty) {
        _locError = 'Detected "${[loc.city, loc.state].where((s) => s.trim().isNotEmpty).join(', ')}" '
            '— please pick the closest match below.';
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
  void _onStatePicked({String? id, String? name}) {
    setState(() {
      _stateId = id;
      _stateName = name;
      _districtId = _districtName = null; // reset children
      _cityId = _cityName = null;
      _locError = null;
    });
    _emit();
  }

  void _onDistrictPicked({String? id, String? name}) {
    setState(() {
      _districtId = id;
      _districtName = name;
      _cityId = _cityName = null; // reset child
    });
    _emit();
  }

  void _onCityPicked({String? id, String? name}) {
    setState(() {
      _cityId = id;
      _cityName = name;
    });
    _emit();
  }

  void _emit() => widget.onChanged(LocationSelection(
        country: 'India',
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

        // NO Country dropdown (removed per spec).
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

  Widget _stateField() {
    final async = ref.watch(statesProvider);
    final custom = customValues(ref, MasterOptionsService.state);
    return async.when(
      loading: () => _loadingField('State', required: true),
      error: (_, __) =>
          _errorField('State', () => ref.invalidate(statesProvider)),
      data: (states) {
        final items =
            mergeOptions(states.map((s) => s.name).toList(), custom);
        if ((_stateName ?? '').isNotEmpty && !items.contains(_stateName)) {
          items.insert(0, _stateName!);
        }
        return SearchableField(
          label: 'State',
          isRequired: true,
          prefixIcon: Icons.map_outlined,
          items: items,
          selectedItem: _stateName,
          onAddNew: (v) => ref
              .read(masterOptionsServiceProvider)
              .add(MasterOptionsService.state, value: v),
          onChanged: (name) {
            final master = _match(states, name ?? '', (s) => s.name);
            if (master != null) {
              _onStatePicked(id: master.id, name: master.name);
            } else if ((name ?? '').trim().isNotEmpty) {
              _onStatePicked(id: null, name: name!.trim()); // custom state
            }
          },
        );
      },
    );
  }

  Widget _districtField() {
    if ((_stateName ?? '').isEmpty) {
      return SearchableField(
        label: 'District',
        items: const [],
        selectedItem: null,
        enabled: false,
        prefixIcon: Icons.account_balance_outlined,
        onChanged: (_) {},
      );
    }
    final custom = customValues(ref, MasterOptionsService.district,
        parent: _stateName ?? '');
    // A CUSTOM state has no master districts — only the overlay applies.
    if (_stateId == null) {
      return _districtDropdown(const <MasterDistrict>[], custom);
    }
    final async = ref.watch(districtsProvider(_stateId!));
    return async.when(
      loading: () => _loadingField('District'),
      error: (_, __) => _errorField(
          'District', () => ref.invalidate(districtsProvider(_stateId!))),
      data: (districts) => _districtDropdown(districts, custom),
    );
  }

  Widget _districtDropdown(List<MasterDistrict> districts, List<String> custom) {
    final items =
        mergeOptions(districts.map((d) => d.name).toList(), custom);
    if ((_districtName ?? '').isNotEmpty && !items.contains(_districtName)) {
      items.insert(0, _districtName!);
    }
    return SearchableField(
      label: 'District',
      isRequired: false, // District is optional (may be absent for a location)
      prefixIcon: Icons.account_balance_outlined,
      items: items,
      selectedItem: _districtName,
      onAddNew: (v) => ref.read(masterOptionsServiceProvider).add(
          MasterOptionsService.district,
          value: v,
          parent: _stateName ?? ''),
      onChanged: (name) {
        final master = _match(districts, name ?? '', (d) => d.name);
        if (master != null) {
          _onDistrictPicked(id: master.id, name: master.name);
        } else if ((name ?? '').trim().isNotEmpty) {
          _onDistrictPicked(id: null, name: name!.trim()); // custom district
        }
      },
    );
  }

  Widget _cityField() {
    if ((_districtName ?? '').isEmpty) {
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
    final custom = customValues(ref, MasterOptionsService.city,
        parent: _districtName ?? '');
    if (_districtId == null) {
      return _cityDropdown(const <MasterCity>[], custom);
    }
    final async = ref.watch(citiesProvider(_districtId!));
    return async.when(
      loading: () => _loadingField('City', required: widget.isRequired),
      error: (_, __) => _errorField(
          'City', () => ref.invalidate(citiesProvider(_districtId!))),
      data: (cities) => _cityDropdown(cities, custom),
    );
  }

  Widget _cityDropdown(List<MasterCity> cities, List<String> custom) {
    final items = mergeOptions(cities.map((c) => c.name).toList(), custom);
    // Keep a GPS-detected / saved custom city visible in the list so the
    // SearchableField can show it as the selected value.
    if ((_cityName ?? '').trim().isNotEmpty && !items.contains(_cityName)) {
      items.insert(0, _cityName!);
    }
    return SearchableField(
      label: 'City',
      isRequired: widget.isRequired,
      prefixIcon: Icons.location_city,
      items: items,
      selectedItem: _cityName,
      onAddNew: (v) => ref.read(masterOptionsServiceProvider).add(
          MasterOptionsService.city,
          value: v,
          parent: _districtName ?? ''),
      onChanged: (name) {
        final master = _match(cities, name ?? '', (c) => c.name);
        if (master != null) {
          _onCityPicked(id: master.id, name: master.name);
        } else if ((name ?? '').trim().isNotEmpty) {
          _onCityPicked(id: null, name: name!.trim()); // custom city
        }
      },
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
