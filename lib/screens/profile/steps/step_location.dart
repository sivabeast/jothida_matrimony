import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/location_picker_section.dart';
import '../../../widgets/common/searchable_field.dart';

/// Step 8 — Location Details: Country / State / District / City (req), plus
/// Native Place and Citizenship (optional).
class StepLocation extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepLocation({super.key, required this.onNext});

  @override
  ConsumerState<StepLocation> createState() => _StepLocationState();
}

class _StepLocationState extends ConsumerState<StepLocation> {
  String? _country = 'India';
  String? _state;
  String? _stateId;
  String? _district;
  String? _districtId;
  String? _city;
  String? _cityId;
  double? _lat;
  double? _lng;
  String? _citizenship;
  final _nativePlace = TextEditingController();

  @override
  void initState() {
    super.initState();
    final data = ref.read(profileCreationProvider).data;
    _country = (data['country'] as String?) ?? 'India';
    _state = data['state'] as String?;
    _stateId = data['stateId'] as String?;
    _district = data['district'] as String?;
    _districtId = data['districtId'] as String?;
    _city = data['city'] as String?;
    _cityId = data['cityId'] as String?;
    _lat = (data['latitude'] as num?)?.toDouble();
    _lng = (data['longitude'] as num?)?.toDouble();
    _citizenship = data['citizenship'] as String?;
    _nativePlace.text = (data['nativePlace'] as String?) ?? '';
  }

  @override
  void dispose() {
    _nativePlace.dispose();
    super.dispose();
  }

  void _saveAndNext() {
    if (_country == null || _country!.isEmpty) {
      _snack('Please select your country');
      return;
    }
    if (_state == null || _district == null || _city == null) {
      _snack('Please select your state, district and city');
      return;
    }
    ref.read(profileCreationProvider.notifier).updateData({
      'country': _country,
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
      'nativePlace': _nativePlace.text.trim(),
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
            initialCountry: _country,
            initialState: _state,
            initialDistrict: _district,
            initialCity: _city,
            initialLatitude: _lat,
            initialLongitude: _lng,
            onChanged: (loc) => setState(() {
              _country = loc.country.isEmpty ? 'India' : loc.country;
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
          AppTextField(
            controller: _nativePlace,
            label: 'Native Place',
            hint: 'Optional',
          ),
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
}
