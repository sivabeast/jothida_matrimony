import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/religion_caste_fields.dart';
import '../../../widgets/common/searchable_field.dart';

/// Community step — Religion (req), Caste (req), Sub Caste (opt),
/// Mother Tongue (req), Gothram and Kuladeivam (opt). Mirrors the website
/// "Community" step.
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
  String? _motherTongue;
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
    _motherTongue = data['motherTongue'] as String?;
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
    if (_motherTongue == null || _motherTongue!.isEmpty) {
      _snack('Please select your mother tongue');
      return;
    }
    ref.read(profileCreationProvider.notifier).updateData({
      'religion': _religion,
      'religionId': _religionId,
      'caste': _caste,
      'casteId': _casteId,
      'subCaste': _subCaste ?? '',
      'subCasteId': _subCasteId,
      'motherTongue': _motherTongue,
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
          SearchableField(
            label: 'Mother Tongue',
            isRequired: true,
            items: AppConstants.motherTongueList,
            selectedItem: _motherTongue,
            prefixIcon: Icons.translate,
            onChanged: (v) => setState(() => _motherTongue = v),
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
