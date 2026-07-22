import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../providers/location_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/location_picker_section.dart';
import '../../../widgets/common/searchable_with_others_field.dart';

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
      _snack(context.l10n.selectStateDistrictCity);
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
          Text(context.l10n.locationDetails, style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          Text(context.l10n.locationStepSubtitle,
              style: const TextStyle(color: Colors.grey)),
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
          SearchableWithOthersField(
            label: context.l10n.citizenship,
            items: AppConstants.citizenshipList,
            value: _citizenship,
            prefixIcon: Icons.flag_outlined,
            onChanged: (v) => setState(() => _citizenship = v),
          ),
          const SizedBox(height: 36),
          GradientButton(
              onPressed: _saveAndNext, text: context.l10n.continueLabel),
        ],
      ),
    );
  }

  /// Native Place — searchable master-city list, with "Others" → custom
  /// textbox for a village/town that isn't in the list.
  Widget _nativePlaceField() {
    final items =
        ref.watch(allCityNamesProvider).valueOrNull ?? const <String>[];
    return SearchableWithOthersField(
      label: context.l10n.nativePlace,
      prefixIcon: Icons.home_outlined,
      items: items,
      value: _nativePlace,
      popupMode: SearchablePopupMode.modalBottomSheet,
      onChanged: (v) => setState(() => _nativePlace = v),
    );
  }
}
