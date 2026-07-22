import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/location_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/location_model.dart';
import '../../providers/locale_provider.dart';
import '../../providers/location_provider.dart';
import 'searchable_field.dart';

/// The app's ONE location picker: **State → District → City** for Tamil Nadu.
///
///  • State is fixed to Tamil Nadu (displayed read-only, no dropdown query).
///  • District lists the 38 Tamil Nadu districts; City lists only the chosen
///    district's cities and resets when the district changes.
///  • Labels and option names follow the app language (English / Tamil) from
///    the same master rows, but the values EMITTED are always the canonical
///    English name + stable numeric id — so stored profiles are
///    language-independent and existing data keeps working.
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
        const SizedBox(height: 16),

        _stateField(),
        const SizedBox(height: 16),
        _districtField(),
        const SizedBox(height: 16),
        _cityField(),

        // ── 📍 City, State summary ──
        if (_city != null || (_legacyCity ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
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

  /// State — fixed to Tamil Nadu, shown read-only in the app language.
  Widget _stateField() => InputDecorator(
        decoration: InputDecoration(
          labelText: '${_label('state')} *',
          prefixIcon: const Icon(Icons.map_outlined),
          filled: true,
          fillColor: Colors.grey[200],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
        ),
        child: Text(TnState.nameFor(_lang),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      );

  Widget _districtField() {
    final async = ref.watch(districtsProvider);
    return async.when(
      loading: () => _loadingField(_label('district'), required: widget.isRequired),
      error: (_, __) =>
          _errorField(_label('district'), () => ref.invalidate(districtsProvider)),
      data: (districts) {
        final names = [for (final d in districts) d.nameFor(_lang)]..sort();
        var selected = _district?.nameFor(_lang);
        if (selected == null && (_legacyDistrict ?? '').isNotEmpty) {
          selected = _legacyDistrict;
          names.insert(0, _legacyDistrict!); // legacy value — display only
        }
        return SearchableField(
          label: _label('district'),
          isRequired: widget.isRequired,
          prefixIcon: Icons.account_balance_outlined,
          items: names,
          selectedItem: selected,
          onChanged: (name) {
            TnDistrict? match;
            for (final d in districts) {
              if (d.nameFor(_lang) == name) {
                match = d;
                break;
              }
            }
            setState(() {
              _district = match;
              _legacyDistrict = match == null ? name : null;
              _city = null; // reset child
              _legacyCity = null;
              _locError = null;
            });
            _emit();
          },
        );
      },
    );
  }

  Widget _cityField() {
    final districtId = _district?.id;
    if (districtId == null) {
      return SearchableField(
        label: _label('city'),
        isRequired: widget.isRequired,
        items: (_legacyCity ?? '').isNotEmpty ? [_legacyCity!] : const [],
        selectedItem: (_legacyCity ?? '').isNotEmpty ? _legacyCity : null,
        enabled: false,
        prefixIcon: Icons.location_city,
        onChanged: (_) {},
      );
    }
    final async = ref.watch(citiesProvider(districtId));
    return async.when(
      loading: () => _loadingField(_label('city'), required: widget.isRequired),
      error: (_, __) => _errorField(
          _label('city'), () => ref.invalidate(citiesProvider(districtId))),
      data: (cities) {
        final names = [for (final c in cities) c.nameFor(_lang)]..sort();
        var selected = _city?.nameFor(_lang);
        if (selected == null && (_legacyCity ?? '').isNotEmpty) {
          selected = _legacyCity;
          names.insert(0, _legacyCity!); // legacy value — display only
        }
        return SearchableField(
          label: _label('city'),
          isRequired: widget.isRequired,
          prefixIcon: Icons.location_city,
          items: names,
          selectedItem: selected,
          onChanged: (name) {
            TnCity? match;
            for (final c in cities) {
              if (c.nameFor(_lang) == name) {
                match = c;
                break;
              }
            }
            setState(() {
              _city = match;
              _legacyCity = match == null ? name : null;
            });
            _emit();
          },
        );
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
            Expanded(
              child: Text(context.l10n.loadingField(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            ),
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
              child: Text(context.l10n.couldNotLoadField(label),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ),
            TextButton(
                onPressed: onRetry, child: Text(context.l10n.retry)),
          ],
        ),
      );
}
