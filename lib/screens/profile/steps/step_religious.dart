import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/religion_caste_fields.dart';

/// Step 5 — Religious Information: Religion (req), Caste (req), Sub Caste,
/// Gothram and Kuladeivam (all optional).
class StepReligious extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepReligious({super.key, required this.onNext});

  @override
  ConsumerState<StepReligious> createState() => _StepReligiousState();
}

class _StepReligiousState extends ConsumerState<StepReligious> {
  String? _religion;
  String? _religionId;
  String? _caste;
  String? _casteId;
  String? _subCaste;
  String? _subCasteId;
  final _gothramController = TextEditingController();
  final _kuladeivamController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final data = ref.read(profileCreationProvider).data;
    _religion = data['religion'] as String?;
    _religionId = data['religionId'] as String?;
    _caste = data['caste'] as String?;
    _casteId = data['casteId'] as String?;
    _subCaste = data['subCaste'] as String?;
    _subCasteId = data['subCasteId'] as String?;
    _gothramController.text = (data['gothram'] as String?) ?? '';
    _kuladeivamController.text = (data['kuladeivam'] as String?) ?? '';
  }

  @override
  void dispose() {
    _gothramController.dispose();
    _kuladeivamController.dispose();
    super.dispose();
  }

  void _saveAndNext() {
    if (_religion == null || _religion!.isEmpty) {
      _snack('Please select your religion');
      return;
    }
    if (_caste == null || _caste!.isEmpty) {
      _snack('Please select your caste');
      return;
    }
    ref.read(profileCreationProvider.notifier).updateData({
      'religion': _religion,
      'religionId': _religionId,
      'caste': _caste,
      'casteId': _casteId,
      'subCaste': _subCaste ?? '',
      'subCasteId': _subCasteId,
      'gothram': _gothramController.text.trim(),
      'kuladeivam': _kuladeivamController.text.trim(),
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
          Text('Religious Information', style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          const Text('Helps find matches within your community.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ReligionCasteFields(
            religionId: _religionId,
            religionName: _religion,
            casteId: _casteId,
            casteName: _caste,
            subCasteId: _subCasteId,
            subCasteName: _subCaste,
            onReligionChanged: (id, name) => setState(() {
              _religionId = id;
              _religion = name;
              _casteId = null;
              _caste = null;
              _subCasteId = null;
              _subCaste = null;
            }),
            onCasteChanged: (id, name) => setState(() {
              _casteId = id;
              _caste = name;
              _subCasteId = null;
              _subCaste = null;
            }),
            onSubcasteChanged: (id, name) => setState(() {
              _subCasteId = id;
              _subCaste = name;
            }),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _gothramController,
            label: 'Gothram',
            hint: 'Optional',
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _kuladeivamController,
            label: 'Kuladeivam',
            hint: 'Optional',
          ),
          const SizedBox(height: 36),
          GradientButton(onPressed: _saveAndNext, text: 'Continue'),
        ],
      ),
    );
  }
}
