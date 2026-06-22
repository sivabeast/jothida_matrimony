import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/searchable_field.dart';

/// Step 3 — Physical Details: Height (req), Physical Status (req), Weight (opt).
class StepPhysical extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepPhysical({super.key, required this.onNext});

  @override
  ConsumerState<StepPhysical> createState() => _StepPhysicalState();
}

class _StepPhysicalState extends ConsumerState<StepPhysical> {
  final _weightController = TextEditingController();
  String? _height;
  String? _physicalStatus;

  @override
  void initState() {
    super.initState();
    final data = ref.read(profileCreationProvider).data;
    _height = data['height'] as String?;
    _physicalStatus = data['physicalStatus'] as String?;
    _weightController.text = (data['weight'] as String?) ?? '';
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  void _saveAndNext() {
    if (_height == null || _height!.isEmpty) {
      _snack('Please select your height');
      return;
    }
    if (_physicalStatus == null || _physicalStatus!.isEmpty) {
      _snack('Please select your physical status');
      return;
    }
    ref.read(profileCreationProvider.notifier).updateData({
      'height': _height,
      'physicalStatus': _physicalStatus,
      'weight': _weightController.text.trim(),
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
          Text('Physical Details', style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          const Text('A few details about your appearance.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          SearchableField(
            label: 'Height',
            isRequired: true,
            items: AppConstants.heightList,
            selectedItem: _height,
            prefixIcon: Icons.height,
            onChanged: (v) => setState(() => _height = v),
          ),
          const SizedBox(height: 16),
          SearchableField(
            label: 'Physical Status',
            isRequired: true,
            items: AppConstants.physicalStatusList,
            selectedItem: _physicalStatus,
            prefixIcon: Icons.accessibility_new,
            onChanged: (v) => setState(() => _physicalStatus = v),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _weightController,
            label: 'Weight (kg)',
            hint: '60',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
          ),
          const SizedBox(height: 36),
          GradientButton(onPressed: _saveAndNext, text: 'Continue'),
        ],
      ),
    );
  }
}
