import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/gradient_button.dart';

class Step5PartnerPrefs extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const Step5PartnerPrefs({super.key, required this.onNext});

  @override
  ConsumerState<Step5PartnerPrefs> createState() => _Step5State();
}

class _Step5State extends ConsumerState<Step5PartnerPrefs> {
  RangeValues _ageRange = const RangeValues(22, 35);
  String? _religion;
  String? _caste;
  String? _education;
  String? _rasi;

  void _saveAndNext() {
    ref.read(profileCreationProvider.notifier).updateData({
      'partnerPreferences': {
        'minAge': _ageRange.start.round(),
        'maxAge': _ageRange.end.round(),
        'religion': _religion ?? 'Any',
        'caste': _caste ?? 'Any',
        // education is a List<String> in the model — send a list, not a scalar.
        'education':
            (_education != null && _education != 'Any') ? [_education] : <String>[],
        'rasi': _rasi ?? 'Any',
      },
    });
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Partner Preferences', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Set optional filters to find your ideal match.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          Text(
            'Age Range: ${_ageRange.start.round()} - ${_ageRange.end.round()} years',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          RangeSlider(
            values: _ageRange,
            min: 18,
            max: 60,
            divisions: 42,
            activeColor: const Color(0xFF800020),
            labels: RangeLabels(
              _ageRange.start.round().toString(),
              _ageRange.end.round().toString(),
            ),
            onChanged: (v) => setState(() => _ageRange = v),
          ),
          const SizedBox(height: 16),
          _buildDropdown('Preferred Religion', ['Any', ...AppConstants.religions], _religion,
              (v) => setState(() => _religion = v)),
          const SizedBox(height: 16),
          _buildDropdown('Preferred Caste', ['Any', ...AppConstants.castes], _caste,
              (v) => setState(() => _caste = v)),
          const SizedBox(height: 16),
          _buildDropdown('Preferred Education', ['Any', ...AppConstants.educations], _education,
              (v) => setState(() => _education = v)),
          const SizedBox(height: 16),
          _buildDropdown('Preferred Rasi', ['Any', ...AppConstants.rasiList], _rasi,
              (v) => setState(() => _rasi = v)),
          const SizedBox(height: 32),
          GradientButton(onPressed: _saveAndNext, text: 'Next'),
        ],
      ),
    );
  }

  Widget _buildDropdown(String label, List<String> items, String? value, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      hint: Text(label),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
    );
  }
}
