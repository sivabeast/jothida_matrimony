import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_account_model.dart';

/// Clean checkbox UI for picking an astrologer's working days.
///
/// Shows an "All Days" master checkbox followed by Monday→Sunday. The control
/// is fully stateless — the parent owns the [selected] set and is notified via
/// [onChanged]. The "All Days" box is *derived*, never stored, which makes the
/// spec's rules fall out automatically:
///   • check "All Days"        → selects Monday…Sunday
///   • uncheck "All Days"      → clears every day
///   • uncheck any single day  → "All Days" un-checks itself (derived)
///   • check the 7th day       → "All Days" checks itself (derived)
class WorkingDaysSelector extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const WorkingDaysSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  bool get _allSelected => kWeekdays.every(selected.contains);

  void _toggleAll(bool? value) =>
      onChanged(value == true ? {...kWeekdays} : <String>{});

  void _toggleDay(String day, bool? value) {
    final next = {...selected};
    if (value == true) {
      next.add(day);
    } else {
      next.remove(day);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            value: _allSelected,
            onChanged: _toggleAll,
            activeColor: AppColors.primary,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: const Text('All Days',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Available every day of the week',
                style: TextStyle(fontSize: 12)),
          ),
          const Divider(height: 1),
          for (final day in kWeekdays)
            CheckboxListTile(
              value: selected.contains(day),
              onChanged: (v) => _toggleDay(day, v),
              activeColor: AppColors.primary,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(day),
            ),
        ],
      ),
    );
  }
}
