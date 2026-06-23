import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/slot_generator.dart';
import '../../../providers/astrologer_session_provider.dart';
import '../../../widgets/astrologer/working_days_selector.dart';
import 'astrologer_profile_common.dart';

/// Full consultation-availability configuration: working days, consultation
/// modes, one continuous available window, optional lunch break, slot duration,
/// unavailable dates and a per-day booking cap. (No date range, no buffer time.)
class AstrologerAvailabilityScreen extends ConsumerStatefulWidget {
  const AstrologerAvailabilityScreen({super.key});

  @override
  ConsumerState<AstrologerAvailabilityScreen> createState() =>
      _AstrologerAvailabilityScreenState();
}

class _AstrologerAvailabilityScreenState
    extends ConsumerState<AstrologerAvailabilityScreen> {
  late Set<String> _days;
  late bool _inApp;
  late bool _directVisit;
  late int _start;
  late int _end;
  int? _lunchStart;
  int? _lunchEnd;
  late int _slot;
  late int _maxPerDay;
  late List<String> _unavailable;
  bool _saving = false;

  static const _slotOptions = [15, 30, 45, 60];

  @override
  void initState() {
    super.initState();
    final a = ref.read(myAstrologerAccountProvider);
    _days = {...?a?.workingDays};
    _inApp = a?.offersInApp ?? true;
    _directVisit = a?.offersDirectVisit ?? true;
    _start = a?.availableStartMinutes ?? 8 * 60;
    _end = a?.availableEndMinutes ?? 21 * 60;
    _lunchStart = a?.lunchStartMinutes;
    _lunchEnd = a?.lunchEndMinutes;
    _slot = a?.slotDurationMinutes ?? 30;
    _maxPerDay = a?.maxBookingsPerDay ?? 0;
    _unavailable = [...?a?.unavailableDates];
  }

  bool get _lunchEnabled => _lunchStart != null && _lunchEnd != null;

  List<ConsultationSlot> get _previewSlots => generateSlots(
        startMinutes: _start,
        endMinutes: _end,
        slotDuration: _slot,
        lunchStart: _lunchStart,
        lunchEnd: _lunchEnd,
      );

  Future<void> _pickTime(int initialMinutes, ValueChanged<int> onPicked) async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: initialMinutes ~/ 60, minute: initialMinutes % 60),
    );
    if (picked != null) onPicked(picked.hour * 60 + picked.minute);
  }

  Future<void> _addUnavailableDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    final key = dateKeyOf(picked);
    if (!_unavailable.contains(key)) {
      setState(() => _unavailable = [..._unavailable, key]..sort());
    }
  }

  Future<void> _save() async {
    if (_end <= _start) {
      _snack('End time must be after start time.');
      return;
    }
    if (!_inApp && !_directVisit) {
      _snack('Enable at least one consultation mode.');
      return;
    }
    if (_lunchEnabled && (_lunchEnd! <= _lunchStart!)) {
      _snack('Lunch end must be after lunch start.');
      return;
    }
    final a = ref.read(myAstrologerAccountProvider);
    if (a == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(myAstrologerAccountProvider.notifier).saveAccount(
            a.copyWith(
              workingDays: _days.toList(),
              offersInApp: _inApp,
              offersDirectVisit: _directVisit,
              availableStartMinutes: _start,
              availableEndMinutes: _end,
              lunchStartMinutes: _lunchStart,
              lunchEndMinutes: _lunchEnd,
              clearLunch: !_lunchEnabled,
              slotDurationMinutes: _slot,
              maxBookingsPerDay: _maxPerDay,
              unavailableDates: _unavailable,
            ),
          );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Could not save — please try again.');
      }
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final slots = _previewSlots;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: astrologerSectionAppBar('Availability'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Consultation Modes'),
          _card(Column(children: [
            CheckboxListTile(
              value: _inApp,
              activeColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => _inApp = v ?? false),
              title: const Text('In-App Consultation'),
              subtitle: const Text('Book, pay & receive the report in the app',
                  style: TextStyle(fontSize: 12)),
            ),
            CheckboxListTile(
              value: _directVisit,
              activeColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => _directVisit = v ?? false),
              title: const Text('Direct Visit'),
              subtitle: const Text('Meet the user in person at a booked slot',
                  style: TextStyle(fontSize: 12)),
            ),
          ])),
          const SizedBox(height: 16),
          _sectionTitle('Working Days'),
          WorkingDaysSelector(
            selected: _days,
            onChanged: (d) => setState(() => _days = d),
          ),
          const SizedBox(height: 16),
          _sectionTitle('Available Time'),
          _card(Row(
            children: [
              Expanded(
                child: _timeField('Start Time', _start,
                    (m) => setState(() => _start = m)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _timeField(
                    'End Time', _end, (m) => setState(() => _end = m)),
              ),
            ],
          )),
          const SizedBox(height: 16),
          _sectionTitle('Lunch Break (optional)'),
          _card(Column(children: [
            SwitchListTile(
              value: _lunchEnabled,
              activeColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable lunch break'),
              subtitle: const Text('No slots are generated during this time',
                  style: TextStyle(fontSize: 12)),
              onChanged: (v) => setState(() {
                if (v) {
                  _lunchStart = 13 * 60;
                  _lunchEnd = 14 * 60;
                } else {
                  _lunchStart = null;
                  _lunchEnd = null;
                }
              }),
            ),
            if (_lunchEnabled) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _timeField('Lunch Start', _lunchStart!,
                      (m) => setState(() => _lunchStart = m)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _timeField('Lunch End', _lunchEnd!,
                      (m) => setState(() => _lunchEnd = m)),
                ),
              ]),
            ],
          ])),
          const SizedBox(height: 16),
          _sectionTitle('Slot Duration'),
          Wrap(
            spacing: 10,
            children: [
              for (final d in _slotOptions)
                ChoiceChip(
                  label: Text('$d min'),
                  selected: _slot == d,
                  selectedColor: AppColors.primary.withOpacity(0.15),
                  labelStyle: TextStyle(
                      color: _slot == d ? AppColors.primary : Colors.black87,
                      fontWeight:
                          _slot == d ? FontWeight.w600 : FontWeight.normal),
                  onSelected: (_) => setState(() => _slot = d),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionTitle('Maximum Bookings Per Day'),
          _card(Row(
            children: [
              const Expanded(
                child: Text('0 = no limit',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
              ),
              IconButton(
                onPressed: _maxPerDay > 0
                    ? () => setState(() => _maxPerDay--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                color: AppColors.primary,
              ),
              Text(_maxPerDay == 0 ? '∞' : '$_maxPerDay',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                onPressed: () => setState(() => _maxPerDay++),
                icon: const Icon(Icons.add_circle_outline),
                color: AppColors.primary,
              ),
            ],
          )),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _sectionTitle('Unavailable Dates')),
              TextButton.icon(
                onPressed: _addUnavailableDate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Date'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
            ],
          ),
          _card(
            _unavailable.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No unavailable dates. Users can book any open '
                        'working day.',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey)),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final key in _unavailable)
                        Chip(
                          label: Text(_prettyDate(key),
                              style: const TextStyle(fontSize: 12)),
                          onDeleted: () =>
                              setState(() => _unavailable.remove(key)),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          backgroundColor: AppColors.error.withOpacity(0.08),
                          side: BorderSide.none,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          // Slot preview so the astrologer sees exactly what users will get.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${slots.length} slots / day',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in slots.take(8))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.3)),
                        ),
                        child: Text(s.label,
                            style: const TextStyle(fontSize: 11.5)),
                      ),
                    if (slots.length > 8)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('+${slots.length - 8} more',
                            style: const TextStyle(
                                fontSize: 11.5, color: Colors.grey)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ProfileSaveButton(saving: _saving, onPressed: _save),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(t,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.25)),
        ),
        child: child,
      );

  Widget _timeField(String label, int minutes, ValueChanged<int> onPicked) =>
      InkWell(
        onTap: () => _pickTime(minutes, onPicked),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16),
                  const SizedBox(width: 6),
                  Text(formatMinutes(minutes),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      );

  String _prettyDate(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return key;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final m = int.tryParse(parts[1]) ?? 1;
    return '${parts[2]} ${months[(m - 1).clamp(0, 11)]} ${parts[0]}';
  }
}
