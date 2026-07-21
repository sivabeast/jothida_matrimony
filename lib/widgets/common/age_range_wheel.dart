import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Native wheel picker for an age RANGE (From / To) — the mobile twin of the
/// website's `AgeRangeWheelPicker`. Two [CupertinoPicker] wheels over
/// [min]–[max]; keeps To ≥ From automatically. There is NO range slider: the
/// web and the app now share the exact same wheel UX.
class AgeRangeWheel extends StatefulWidget {
  final int minAge;
  final int maxAge;
  final int min;
  final int max;
  final void Function(int minAge, int maxAge) onChanged;

  const AgeRangeWheel({
    super.key,
    required this.minAge,
    required this.maxAge,
    required this.onChanged,
    this.min = 18,
    this.max = 60,
  });

  @override
  State<AgeRangeWheel> createState() => _AgeRangeWheelState();
}

class _AgeRangeWheelState extends State<AgeRangeWheel> {
  late FixedExtentScrollController _fromCtrl;
  late FixedExtentScrollController _toCtrl;

  int _clamp(int v) =>
      v < widget.min ? widget.min : (v > widget.max ? widget.max : v);

  @override
  void initState() {
    super.initState();
    _fromCtrl =
        FixedExtentScrollController(initialItem: _clamp(widget.minAge) - widget.min);
    _toCtrl =
        FixedExtentScrollController(initialItem: _clamp(widget.maxAge) - widget.min);
  }

  @override
  void didUpdateWidget(covariant AgeRangeWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the wheels parked on the controlled value (e.g. when scrolling From
    // above To auto-bumps To). Scheduled post-frame so we never jump mid-build.
    final fromIdx = _clamp(widget.minAge) - widget.min;
    final toIdx = _clamp(widget.maxAge) - widget.min;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_fromCtrl.hasClients && _fromCtrl.selectedItem != fromIdx) {
        _fromCtrl.jumpToItem(fromIdx);
      }
      if (_toCtrl.hasClients && _toCtrl.selectedItem != toIdx) {
        _toCtrl.jumpToItem(toIdx);
      }
    });
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  void _onFrom(int idx) {
    final v = widget.min + idx;
    final hi = widget.maxAge < v ? v : widget.maxAge; // keep To ≥ From
    widget.onChanged(v, hi);
  }

  void _onTo(int idx) {
    final v = widget.min + idx;
    final lo = widget.minAge > v ? v : widget.minAge; // keep From ≤ To
    widget.onChanged(lo, v);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _pill('${_clamp(widget.minAge)}'),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('–', style: TextStyle(color: Colors.grey))),
              _pill('${_clamp(widget.maxAge)}'),
              const SizedBox(width: 6),
              const Text('yrs',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 170,
            child: Row(
              children: [
                Expanded(child: _wheel('FROM', _fromCtrl, _onFrom)),
                Container(width: 1, height: 110, color: Colors.grey.shade200),
                Expanded(child: _wheel('TO', _toCtrl, _onTo)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(t,
            style: const TextStyle(
                color: AppColors.primary, fontWeight: FontWeight.bold)),
      );

  Widget _wheel(
      String label, FixedExtentScrollController ctrl, ValueChanged<int> onSel) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Expanded(
          child: CupertinoPicker(
            scrollController: ctrl,
            itemExtent: 38,
            magnification: 1.1,
            squeeze: 1.1,
            useMagnifier: true,
            selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
              background: AppColors.primary.withOpacity(0.06),
            ),
            onSelectedItemChanged: onSel,
            children: [
              for (int a = widget.min; a <= widget.max; a++)
                Center(
                  child: Text('$a',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
