import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';

/// Shared form building blocks for the astrologer profile-section edit screens,
/// so each section is thin and visually consistent. Editing happens directly on
/// these screens — there is no onboarding/registration redirect.

/// A labeled text field with the standard astrologer styling.
class ProfileTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final bool number;
  final bool requiredField;
  final IconData? icon;

  const ProfileTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.number = false,
    this.requiredField = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: number
              ? TextInputType.number
              : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
          inputFormatters:
              number ? [FilteringTextInputFormatter.digitsOnly] : null,
          validator: requiredField
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: icon != null ? Icon(icon, size: 20) : null,
            filled: true,
            fillColor: Colors.white,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
}

/// Multi-select chips (specializations, languages, consultation methods).
class ProfileMultiSelect extends StatelessWidget {
  final String label;
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const ProfileMultiSelect({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final o in options)
                  FilterChip(
                    label: Text(o, style: const TextStyle(fontSize: 12.5)),
                    selected: selected.contains(o),
                    selectedColor: AppColors.primary.withOpacity(0.15),
                    checkmarkColor: AppColors.primary,
                    onSelected: (sel) {
                      final next = {...selected};
                      sel ? next.add(o) : next.remove(o);
                      onChanged(next);
                    },
                  ),
              ],
            ),
          ],
        ),
      );
}

/// Single-select choice chips (gender, online/offline mode).
class ProfileSingleSelect extends StatelessWidget {
  final String label;
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;

  const ProfileSingleSelect({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final o in options)
                  ChoiceChip(
                    label: Text(o, style: const TextStyle(fontSize: 12.5)),
                    selected: value == o,
                    selectedColor: AppColors.primary.withOpacity(0.15),
                    onSelected: (_) => onChanged(o),
                  ),
              ],
            ),
          ],
        ),
      );
}

/// Full-width primary save button with a loading state.
class ProfileSaveButton extends StatelessWidget {
  final bool saving;
  final VoidCallback? onPressed;
  final String label;

  const ProfileSaveButton({
    super.key,
    required this.saving,
    required this.onPressed,
    this.label = 'Save Changes',
  });

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: saving ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: saving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(label),
      );
}

/// Maroon section app bar shared by every astrologer profile-section screen.
PreferredSizeWidget astrologerSectionAppBar(String title) => AppBar(
      title: Text(title),
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    );
