import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';

class Step4Family extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const Step4Family({super.key, required this.onNext});

  @override
  ConsumerState<Step4Family> createState() => _Step4State();
}

class _Step4State extends ConsumerState<Step4Family> {
  final _fatherNameController = TextEditingController();
  final _fatherOccController = TextEditingController();
  final _motherNameController = TextEditingController();
  final _motherOccController = TextEditingController();
  int _brothers = 0;
  int _sisters = 0;
  String _familyType = 'Joint';
  String _familyStatus = 'Middle Class';

  @override
  void dispose() {
    _fatherNameController.dispose();
    _fatherOccController.dispose();
    _motherNameController.dispose();
    _motherOccController.dispose();
    super.dispose();
  }

  void _saveAndNext() {
    ref.read(profileCreationProvider.notifier).updateData({
      'familyDetails': {
        'fatherName': _fatherNameController.text.trim(),
        'fatherOccupation': _fatherOccController.text.trim(),
        'motherName': _motherNameController.text.trim(),
        'motherOccupation': _motherOccController.text.trim(),
        'brothersCount': _brothers,
        'sistersCount': _sisters,
        'familyType': _familyType,
        'familyStatus': _familyStatus,
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
          const Text('Family Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          AppTextField(controller: _fatherNameController, label: "Father's Name"),
          const SizedBox(height: 16),
          AppTextField(controller: _fatherOccController, label: "Father's Occupation"),
          const SizedBox(height: 16),
          AppTextField(controller: _motherNameController, label: "Mother's Name"),
          const SizedBox(height: 16),
          AppTextField(controller: _motherOccController, label: "Mother's Occupation"),
          const SizedBox(height: 24),
          _buildCounter('Brothers', _brothers, (v) => setState(() => _brothers = v)),
          const SizedBox(height: 16),
          _buildCounter('Sisters', _sisters, (v) => setState(() => _sisters = v)),
          const SizedBox(height: 24),
          _buildSegment('Family Type', ['Joint', 'Nuclear'], _familyType,
              (v) => setState(() => _familyType = v)),
          const SizedBox(height: 16),
          _buildSegment(
            'Family Status',
            ['Lower Class', 'Middle Class', 'Upper Middle Class', 'Rich'],
            _familyStatus,
            (v) => setState(() => _familyStatus = v),
          ),
          const SizedBox(height: 32),
          GradientButton(onPressed: _saveAndNext, text: 'Next'),
        ],
      ),
    );
  }

  Widget _buildCounter(String label, int value, ValueChanged<int> onChange) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        Row(
          children: [
            IconButton(
              onPressed: value > 0 ? () => onChange(value - 1) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(
              onPressed: () => onChange(value + 1),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSegment(String label, List<String> opts, String selected, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: opts.map((opt) {
            final isSelected = selected == opt;
            return ChoiceChip(
              label: Text(opt),
              selected: isSelected,
              onSelected: (_) => onChanged(opt),
              selectedColor: const Color(0xFF800020),
              labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
            );
          }).toList(),
        ),
      ],
    );
  }
}
