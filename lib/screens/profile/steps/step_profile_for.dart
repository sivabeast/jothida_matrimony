import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/gradient_button.dart';

/// Step 1 — "Who are you creating this profile for?".
///
/// A single required selection. Stored as `profileFor` in the profile-creation
/// data and used purely for context (it does not affect matching).
class ProfileForStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const ProfileForStep({super.key, required this.onNext});

  @override
  ConsumerState<ProfileForStep> createState() => _ProfileForStepState();
}

class _ProfileForStepState extends ConsumerState<ProfileForStep> {
  String? _profileFor;

  static const _options = [
    'Myself',
    'Son',
    'Daughter',
    'Brother',
    'Sister',
    'Relative',
    'Friend',
  ];

  @override
  void initState() {
    super.initState();
    // Prefill when revisiting (or editing) so the choice is preserved.
    _profileFor = ref.read(profileCreationProvider).data['profileFor'] as String?;
  }

  void _saveAndNext() {
    if (_profileFor == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select who this profile is for')));
      return;
    }
    ref.read(profileCreationProvider.notifier).updateData({
      'profileFor': _profileFor,
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
          Text('Who are you creating this profile for?',
              style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          const Text(
            'This helps us personalise the experience.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ..._options.map(_optionTile),
          const SizedBox(height: 32),
          GradientButton(onPressed: _saveAndNext, text: 'Next'),
        ],
      ),
    );
  }

  Widget _optionTile(String option) {
    final selected = _profileFor == option;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => setState(() => _profileFor = option),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withOpacity(0.08)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.grey[300]!,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : Colors.grey[500],
              ),
              const SizedBox(width: 14),
              Text(
                option,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected ? AppColors.primary : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
