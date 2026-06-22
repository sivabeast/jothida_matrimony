import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';

/// Step 10 — About Me (optional free-text introduction).
class StepAboutMe extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepAboutMe({super.key, required this.onNext});

  @override
  ConsumerState<StepAboutMe> createState() => _StepAboutMeState();
}

class _StepAboutMeState extends ConsumerState<StepAboutMe> {
  final _aboutController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _aboutController.text =
        (ref.read(profileCreationProvider).data['about'] as String?) ?? '';
  }

  @override
  void dispose() {
    _aboutController.dispose();
    super.dispose();
  }

  void _saveAndNext() {
    ref
        .read(profileCreationProvider.notifier)
        .updateData({'about': _aboutController.text.trim()});
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('About Me', style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          const Text('Optional — you can always add this later.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          AppTextField(
            controller: _aboutController,
            label: 'About Me',
            hint:
                'Write a few lines about yourself, your family background, '
                'interests, values and expectations.',
            maxLines: 6,
          ),
          const SizedBox(height: 36),
          GradientButton(onPressed: _saveAndNext, text: 'Continue'),
        ],
      ),
    );
  }
}
