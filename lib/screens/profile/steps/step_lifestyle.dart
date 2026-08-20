import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/searchable_field.dart';

/// Lifestyle step — Eating / Smoking / Drinking habits, Hobbies, Interests and
/// Languages Known.
///
/// EVERY field here is OPTIONAL: there is no validation, so leaving the whole
/// step blank never blocks profile creation. The step is also in the wizard's
/// skippable set, so the member can move straight past it. The same fields stay
/// editable afterwards from My Profile → Lifestyle (`/edit/lifestyle`).
class StepLifestyle extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepLifestyle({super.key, required this.onNext});

  @override
  ConsumerState<StepLifestyle> createState() => _StepLifestyleState();
}

class _StepLifestyleState extends ConsumerState<StepLifestyle> {
  String? _eating;
  String? _smoking;
  String? _drinking;
  final _hobbies = TextEditingController();
  final _interests = TextEditingController();
  final _languages = TextEditingController();

  static String? _n(Object? v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  @override
  void initState() {
    super.initState();
    // The wizard stores lifestyle as one nested map (the same shape the profile
    // document uses), so an edit/draft resume prefills every field.
    final raw = ref.read(profileCreationProvider).data['lifestyle'];
    if (raw is Map) {
      _eating = _n(raw['eatingHabit']);
      _smoking = _n(raw['smokingHabit']);
      _drinking = _n(raw['drinkingHabit']);
      _hobbies.text = (raw['hobbies'] ?? '').toString();
      _interests.text = (raw['interests'] ?? '').toString();
      final langs = raw['languagesKnown'];
      if (langs is List) _languages.text = langs.join(', ');
    }
  }

  @override
  void dispose() {
    _hobbies.dispose();
    _interests.dispose();
    _languages.dispose();
    super.dispose();
  }

  /// No validation — every lifestyle field is optional, so Continue always
  /// proceeds whether or not anything was filled in.
  void _saveAndNext() {
    final langs = _languages.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    ref.read(profileCreationProvider.notifier).updateData({
      'lifestyle': {
        'eatingHabit': _eating ?? '',
        'smokingHabit': _smoking ?? '',
        'drinkingHabit': _drinking ?? '',
        'hobbies': _hobbies.text.trim(),
        'interests': _interests.text.trim(),
        'languagesKnown': langs,
      },
    });
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.lifestyleDetails, style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          Text(l10n.lifestyleStepSubtitle,
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          SearchableField(
            label: l10n.eatingHabit,
            items: AppConstants.eatingHabitList,
            selectedItem: _eating,
            prefixIcon: Icons.restaurant_outlined,
            onChanged: (v) => setState(() => _eating = v),
          ),
          const SizedBox(height: 16),
          SearchableField(
            label: l10n.smokingHabit,
            items: AppConstants.smokingHabitList,
            selectedItem: _smoking,
            prefixIcon: Icons.smoke_free,
            onChanged: (v) => setState(() => _smoking = v),
          ),
          const SizedBox(height: 16),
          SearchableField(
            label: l10n.drinkingHabit,
            items: AppConstants.drinkingHabitList,
            selectedItem: _drinking,
            prefixIcon: Icons.no_drinks_outlined,
            onChanged: (v) => setState(() => _drinking = v),
          ),
          const SizedBox(height: 16),
          AppTextField(
              controller: _hobbies,
              label: l10n.hobbies,
              hint: l10n.hobbiesHint),
          const SizedBox(height: 16),
          AppTextField(
              controller: _interests,
              label: l10n.interests,
              hint: l10n.interestsHint),
          const SizedBox(height: 16),
          AppTextField(
              controller: _languages,
              label: l10n.languagesKnown,
              hint: l10n.languagesKnownHint),
          const SizedBox(height: 36),
          GradientButton(onPressed: _saveAndNext, text: l10n.continueLabel),
        ],
      ),
    );
  }
}
