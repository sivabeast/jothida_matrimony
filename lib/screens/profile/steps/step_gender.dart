import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/gradient_button.dart';

/// Step 2 — "Select Gender".
///
/// A single required selection (Male / Female). Stored as `gender`, it is the
/// only field that drives opposite-gender matching downstream.
class GenderStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const GenderStep({super.key, required this.onNext});

  @override
  ConsumerState<GenderStep> createState() => _GenderStepState();
}

class _GenderStepState extends ConsumerState<GenderStep> {
  String? _gender;

  @override
  void initState() {
    super.initState();
    _gender = ref.read(profileCreationProvider).data['gender'] as String?;
  }

  void _saveAndNext() {
    if (_gender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a gender')));
      return;
    }
    ref.read(profileCreationProvider.notifier).updateData({'gender': _gender});
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select Gender', style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          const Text(
            'This is used to show you matches of the opposite gender.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _genderCard('Male', Icons.male)),
              const SizedBox(width: 16),
              Expanded(child: _genderCard('Female', Icons.female)),
            ],
          ),
          const SizedBox(height: 40),
          GradientButton(onPressed: _saveAndNext, text: 'Next'),
        ],
      ),
    );
  }

  Widget _genderCard(String gender, IconData icon) {
    final selected = _gender == gender;
    return GestureDetector(
      onTap: () => setState(() => _gender = gender),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 48, color: selected ? Colors.white : Colors.grey[600]),
            const SizedBox(height: 8),
            Text(
              gender,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
