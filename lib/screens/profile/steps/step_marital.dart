import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/searchable_field.dart';

/// Step 4 — Marital Information. Marital Status is required; when Divorced /
/// Widow / Widower is chosen, the number of children + their living status are
/// revealed.
class StepMarital extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepMarital({super.key, required this.onNext});

  @override
  ConsumerState<StepMarital> createState() => _StepMaritalState();
}

class _StepMaritalState extends ConsumerState<StepMarital> {
  final _childrenController = TextEditingController();
  String? _maritalStatus;
  String? _childrenLivingStatus;

  bool get _showChildren =>
      _maritalStatus != null &&
      AppConstants.maritalStatusesWithChildren.contains(_maritalStatus);

  @override
  void initState() {
    super.initState();
    final data = ref.read(profileCreationProvider).data;
    _maritalStatus = data['maritalStatus'] as String?;
    _childrenLivingStatus = data['childrenLivingStatus'] as String?;
    final count = data['childrenCount'];
    if (count is int && count > 0) _childrenController.text = '$count';
  }

  @override
  void dispose() {
    _childrenController.dispose();
    super.dispose();
  }

  void _saveAndNext() {
    if (_maritalStatus == null || _maritalStatus!.isEmpty) {
      _snack('Please select your marital status');
      return;
    }
    ref.read(profileCreationProvider.notifier).updateData({
      'maritalStatus': _maritalStatus,
      'childrenCount':
          _showChildren ? (int.tryParse(_childrenController.text) ?? 0) : 0,
      'childrenLivingStatus': _showChildren ? _childrenLivingStatus : null,
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
          Text('Marital Information', style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          const Text('Your current marital status.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          SearchableField(
            label: 'Marital Status',
            isRequired: true,
            items: AppConstants.maritalStatusOptions,
            selectedItem: _maritalStatus,
            prefixIcon: Icons.favorite_border,
            onChanged: (v) => setState(() => _maritalStatus = v),
          ),
          if (_showChildren) ...[
            const SizedBox(height: 16),
            AppTextField(
              controller: _childrenController,
              label: 'Number of Children',
              hint: '0',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: 'Children Living Status',
              items: AppConstants.childrenLivingStatusList,
              selectedItem: _childrenLivingStatus,
              prefixIcon: Icons.home_outlined,
              onChanged: (v) => setState(() => _childrenLivingStatus = v),
            ),
          ],
          const SizedBox(height: 36),
          GradientButton(onPressed: _saveAndNext, text: 'Continue'),
        ],
      ),
    );
  }
}
