import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A **(−) n (+)** stepper for small counts (§2).
///
/// Used instead of a number keyboard wherever the realistic range is a handful
/// of values — "how many children?" being the case that motivated it. A text
/// field there invites typos, an empty state and a keyboard covering half the
/// form; two large tap targets do not.
///
/// The buttons are 44×44 so they clear the minimum touch target on a phone,
/// and each disables itself at its end of the range rather than silently
/// refusing the tap.
class NumberStepperField extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  final int min;
  final int max;

  /// Helper line under the control.
  final String? helperText;

  final IconData? prefixIcon;
  final bool enabled;

  const NumberStepperField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 20,
    this.helperText,
    this.prefixIcon,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final canGoDown = enabled && value > min;
    final canGoUp = enabled && value < max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
            filled: true,
            fillColor: enabled ? Colors.grey[50] : Colors.grey[200],
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepButton(
                icon: Icons.remove,
                // Tooltips read out the resulting value, which is more useful
                // to a screen reader than a bare "decrease".
                tooltip: '${value - 1}',
                onPressed: canGoDown ? () => onChanged(value - 1) : null,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              _StepButton(
                icon: Icons.add,
                tooltip: '${value + 1}',
                onPressed: canGoUp ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(helperText!,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ),
        ],
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _StepButton({required this.icon, required this.tooltip, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    return Semantics(
      button: true,
      enabled: on,
      child: Material(
        color: on ? AppColors.primary.withValues(alpha: 0.08) : Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon,
                size: 22, color: on ? AppColors.primary : Colors.grey[400]),
          ),
        ),
      ),
    );
  }
}
