import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/gradient_button.dart';

class Step1WhoAreYou extends ConsumerStatefulWidget {
  final VoidCallback onNext;

  const Step1WhoAreYou({super.key, required this.onNext});

  @override
  ConsumerState<Step1WhoAreYou> createState() => _Step1State();
}

class _Step1State extends ConsumerState<Step1WhoAreYou> {
  String? _profileFor;
  String? _gender;

  static const _profileForOptions = [
    'Myself', 'Son', 'Daughter', 'Brother', 'Sister', 'Friend',
  ];

  void _saveAndNext() {
    if (_profileFor == null || _gender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select all options')));
      return;
    }
    ref.read(profileCreationProvider.notifier).updateData({
      'profileFor': _profileFor,
      'gender': _gender,
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
          Text('Profile is for', style: AppTextStyles.heading2),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _profileForOptions.map((opt) {
              final selected = _profileFor == opt;
              return ChoiceChip(
                label: Text(opt),
                selected: selected,
                onSelected: (_) => setState(() => _profileFor = opt),
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
                backgroundColor: Colors.grey[100],
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          Text('Gender', style: AppTextStyles.heading2),
          const SizedBox(height: 16),
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
