import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/location_provider.dart';
import '../../../providers/master_options_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/location_picker_section.dart';
import '../../../widgets/common/searchable_field.dart';

/// Step 8 — Location Details: State / District / City (req), plus Native
/// Place and Citizenship. There is NO Country dropdown (removed per spec).
class StepLocation extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepLocation({super.key, required this.onNext});

  @override
  ConsumerState<StepLocation> createState() => _StepLocationState();
}

class _StepLocationState extends ConsumerState<StepLocation> {
  String? _state;
  String? _stateId;
  String? _district;
  String? _districtId;
  String? _city;
  String? _cityId;
  double? _lat;
  double? _lng;
  String? _citizenship;
  String? _nativePlace;

  @override
  void initState() {
    super.initState();
    final data = ref.read(profileCreationProvider).data;
    _state = data['state'] as String?;
    _stateId = data['stateId'] as String?;
    _district = data['district'] as String?;
    _districtId = data['districtId'] as String?;
    _city = data['city'] as String?;
    _cityId = data['cityId'] as String?;
    _lat = (data['latitude'] as num?)?.toDouble();
    _lng = (data['longitude'] as num?)?.toDouble();
    _citizenship = data['citizenship'] as String?;
    final native = (data['nativePlace'] as String?) ?? '';
    _nativePlace = native.isEmpty ? null : native;
  }

  void _saveAndNext() {
    if (_state == null || _district == null || _city == null) {
      _snack('Please select your state, district and city');
      return;
    }
    ref.read(profileCreationProvider.notifier).updateData({
      'country': 'India',
      'state': _state ?? '',
      'stateId': _stateId ?? '',
      'stateName': _state ?? '',
      'district': _district ?? '',
      'districtId': _districtId ?? '',
      'districtName': _district ?? '',
      'city': _city,
      'cityId': _cityId ?? '',
      'cityName': _city ?? '',
      'latitude': _lat,
      'longitude': _lng,
      'nativePlace': (_nativePlace ?? '').trim(),
      'citizenship': _citizenship ?? '',
    });
    widget.onNext();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Location Details', style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          const Text('Where are you located?',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          LocationPickerSection(
            initialState: _state,
            initialDistrict: _district,
            initialCity: _city,
            initialLatitude: _lat,
            initialLongitude: _lng,
            onChanged: (loc) => setState(() {
              _state = loc.state.isEmpty ? null : loc.state;
              _stateId = loc.stateId.isEmpty ? null : loc.stateId;
              _district = loc.district.isEmpty ? null : loc.district;
              _districtId = loc.districtId.isEmpty ? null : loc.districtId;
              _city = loc.city.isEmpty ? null : loc.city;
              _cityId = loc.cityId.isEmpty ? null : loc.cityId;
              _lat = loc.latitude;
              _lng = loc.longitude;
            }),
          ),
          const SizedBox(height: 16),
          _nativePlaceField(),
          const SizedBox(height: 16),
          SearchableField(
            label: 'Citizenship',
            items: AppConstants.citizenshipList,
            selectedItem: _citizenship,
            prefixIcon: Icons.flag_outlined,
            onChanged: (v) => setState(() => _citizenship = v),
          ),
          const SizedBox(height: 36),
          GradientButton(onPressed: _saveAndNext, text: 'Continue'),
        ],
      ),
    );
  }

  /// Native Place — searchable master-city list + custom additions with the
  /// "+" Add button (replaced the old free-text box).
  Widget _nativePlaceField() {
    final cityNames =
        ref.watch(allCityNamesProvider).valueOrNull ?? const <String>[];
    final custom = customValues(ref, MasterOptionsService.nativePlace);
    final items = mergeOptions(cityNames, custom);
    if ((_nativePlace ?? '').isNotEmpty && !items.contains(_nativePlace)) {
      items.insert(0, _nativePlace!);
    }
    return SearchableField(
      label: 'Native Place',
      prefixIcon: Icons.home_outlined,
      items: items,
      selectedItem: _nativePlace,
      onAddNew: (v) => ref
          .read(masterOptionsServiceProvider)
          .add(MasterOptionsService.nativePlace, value: v),
      onChanged: (v) => setState(() => _nativePlace = v),
    );
  }
}
