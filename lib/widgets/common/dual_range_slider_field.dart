import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A modern dual-handle range field: one slider, two handles (minimum on the
/// left, maximum on the right) with a live readout of the selected range.
///
/// It replaces every wheel / scroll picker and every "Minimum X + Maximum X"
/// pair of dropdowns in Profile Creation (spec §9–§11). Values are plain
/// integers, so the same widget drives both:
///
///  * **Age**    — [min] 18 … [max] 60, the value IS the age.
///  * **Height** — [min] 0 … [max] items.length-1, the value is an INDEX into
///    the height list; [formatValue] turns it back into `5'6"`.
class DualRangeSliderField extends StatelessWidget {
  final String label;

  /// Inclusive bounds of the track.
  final int min;
  final int max;

  final int startValue;
  final int endValue;

  /// Emits (start, end) — always `start <= end`.
  final void Function(int start, int end) onChanged;

  /// Renders one endpoint for display (e.g. `21` → `21`, index → `5'6"`).
  final String Function(int value) formatValue;

  /// The combined readout shown above the track, e.g. `21 – 35 Years`.
  final String Function(int start, int end) formatRange;

  /// Captions under the two handles ("Minimum Age" / "Maximum Age").
  final String startCaption;
  final String endCaption;

  const DualRangeSliderField({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.startValue,
    required this.endValue,
    required this.onChanged,
    required this.formatRange,
    required this.startCaption,
    required this.endCaption,
    String Function(int value)? formatValue,
  }) : formatValue = formatValue ?? _defaultFormat;

  static String _defaultFormat(int v) => '$v';

  int get _lo => startValue.clamp(min, max);
  int get _hi => endValue.clamp(min, max) < _lo ? _lo : endValue.clamp(min, max);

  @override
  Widget build(BuildContext context) {
    // A single-value track would make RangeSlider throw; guard defensively.
    final safeMax = max > min ? max : min + 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54)),
              ),
              // Live value — updates as either handle moves.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  formatRange(_lo, _hi),
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.primary.withValues(alpha: 0.15),
              thumbColor: Colors.white,
              overlayColor: AppColors.primary.withValues(alpha: 0.12),
              rangeThumbShape: const RoundRangeSliderThumbShape(
                  enabledThumbRadius: 11, elevation: 2),
              rangeValueIndicatorShape:
                  const PaddleRangeSliderValueIndicatorShape(),
              valueIndicatorColor: AppColors.primary,
              valueIndicatorTextStyle:
                  const TextStyle(color: Colors.white, fontSize: 12),
            ),
            child: RangeSlider(
              min: min.toDouble(),
              max: safeMax.toDouble(),
              divisions: safeMax - min,
              values: RangeValues(_lo.toDouble(), _hi.toDouble()),
              labels: RangeLabels(formatValue(_lo), formatValue(_hi)),
              onChanged: (v) => onChanged(v.start.round(), v.end.round()),
            ),
          ),
          // Handle captions, so it is obvious which end is which.
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: _caption(startCaption, formatValue(_lo))),
                const SizedBox(width: 12),
                Flexible(
                  child: _caption(endCaption, formatValue(_hi),
                      alignEnd: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _caption(String caption, String value, {bool alignEnd = false}) =>
      Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: alignEnd ? TextAlign.end : TextAlign.start,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87)),
        ],
      );
}
