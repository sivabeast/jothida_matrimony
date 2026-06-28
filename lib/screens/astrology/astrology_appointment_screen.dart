import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/astrology_service_config.dart';
import '../../providers/astrology_config_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../services/firebase/astrologer_service.dart';

/// Standalone "Book Your Appointment" flow opened from the Astrology page.
///
/// Steps: 1) Select a date from a ROLLING ONE-WEEK schedule (next 7 calendar
/// days, weekends + admin holidays removed); 2) Select an available time slot
/// (booked, disabled and past slots are greyed out — double-booking is also
/// prevented at the backend via a deterministic slot-lock document); 3) Confirm.
/// Every value (working days, holidays, slot window, disabled slots, booking
/// availability) comes from the admin-managed config.
class AstrologyAppointmentScreen extends ConsumerStatefulWidget {
  const AstrologyAppointmentScreen({super.key});

  @override
  ConsumerState<AstrologyAppointmentScreen> createState() =>
      _AstrologyAppointmentScreenState();
}

class _AstrologyAppointmentScreenState
    extends ConsumerState<AstrologyAppointmentScreen> {
  DateTime? _date;
  int? _slot;
  bool _busy = false;

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _confirm(AstrologyServiceConfig cfg) async {
    if (_date == null || _slot == null) {
      _snack('Please select a date and time slot.');
      return;
    }
    setState(() => _busy = true);
    try {
      final id =
          await ref.read(matchAnalysisControllerProvider.notifier).bookServiceAppointment(
                date: _date!,
                slotMinutes: _slot!,
                config: cfg,
              );
      if (!mounted) return;
      context.pushReplacement('/appointment-confirmation/$id', extra: {
        'date': _date!,
        'slot': _slot!,
        'address': cfg.officeAddress,
        'contact': cfg.officeContactNumber,
        'internalUid': cfg.internalUid,
        'expertName': cfg.expertName,
        'expertPhoto': cfg.expertPhotoUrl,
      });
    } on AppointmentSlotTakenException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _slot = null;
      });
      _snack('That slot was just booked. Please choose another.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Could not complete your booking. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(astrologyServiceConfigProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Book Your Appointment'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: cfgAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => _content(AstrologyServiceConfig.defaults),
        data: (cfg) => _content(cfg),
      ),
    );
  }

  Widget _content(AstrologyServiceConfig cfg) {
    if (!cfg.bookingEnabled) return _closed();

    final dates = rollingWeekWorkingDays(
      workingWeekdays: cfg.workingWeekdays,
      holidayDates: cfg.holidayDates,
    );
    if (dates.isEmpty) return _closed(message: 'No working days available this week.');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _banner(cfg),
        const SizedBox(height: 16),
        _stepLabel(1, 'Select Date'),
        const SizedBox(height: 8),
        _dateStrip(dates),
        if (_date != null) ...[
          const SizedBox(height: 18),
          _stepLabel(2, 'Select Time Slot'),
          const SizedBox(height: 8),
          _slotGrid(cfg),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed:
                (_busy || _date == null || _slot == null) ? null : () => _confirm(cfg),
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_outline, size: 20),
            label: Text(_busy ? 'Confirming…' : 'Confirm Appointment',
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              minimumSize: const Size.fromHeight(54),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _closed({String? message}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_busy_outlined,
                  size: 64, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                message ??
                    'Appointment booking is currently closed. Please check '
                        'back later.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14.5, height: 1.5),
              ),
            ],
          ),
        ),
      );

  Widget _banner(AstrologyServiceConfig cfg) {
    final rules = cfg.appointmentRules.trim();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gold.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.gold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              rules.isEmpty
                  ? 'This is an in-person office visit. Choose your preferred '
                      'date and time below.'
                  : rules,
              style: TextStyle(fontSize: 12.5, color: Colors.grey[800], height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepLabel(int n, String t) => Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration:
                const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            child: Text('$n',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Text(t,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
        ],
      );

  Widget _dateStrip(List<DateTime> dates) => SizedBox(
        height: 90,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: dates.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final d = dates[i];
            final selected =
                _date != null && dateKeyOf(_date!) == dateKeyOf(d);
            return _DateCard(
              date: d,
              selected: selected,
              onTap: () => setState(() {
                _date = d;
                _slot = null;
              }),
            );
          },
        ),
      );

  Widget _slotGrid(AstrologyServiceConfig cfg) {
    final booked =
        ref.watch(internalBookedSlotsProvider).valueOrNull ?? const {};
    final takenKeys = booked[dateKeyOf(_date!)] ?? <String>{};
    final takenMinutes =
        takenKeys.map(minutesFromSlotKey).whereType<int>().toSet();
    final disabled = cfg.disabledSlotMinutes.toSet();
    final now = DateTime.now();
    final isToday = dateKeyOf(_date!) == dateKeyOf(now);
    final nowMinutes = now.hour * 60 + now.minute;

    final slots = generateSlots(
      startMinutes: cfg.slotStartMinutes,
      endMinutes: cfg.slotEndMinutes,
      slotDuration: cfg.slotDurationMinutes,
      lunchStart: cfg.lunchStartMinutes,
      lunchEnd: cfg.lunchEndMinutes,
    ).where((s) => !disabled.contains(s.startMinutes)).toList();

    if (slots.isEmpty) {
      return const Text('No slots available for this date.',
          style: TextStyle(color: Colors.grey));
    }

    final available = <Widget>[];
    for (final s in slots) {
      final past = isToday && s.startMinutes <= nowMinutes;
      final taken = takenMinutes.contains(s.startMinutes) || past;
      available.add(_SlotChip(
        label: s.label,
        booked: taken,
        pastLabel: past ? 'Passed' : 'Booked',
        selected: _slot == s.startMinutes,
        onTap: taken ? null : () => setState(() => _slot = s.startMinutes),
      ));
    }
    return Wrap(spacing: 8, runSpacing: 8, children: available);
  }
}

class _DateCard extends StatelessWidget {
  final DateTime date;
  final bool selected;
  final VoidCallback onTap;
  const _DateCard(
      {required this.date, required this.selected, required this.onTap});

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _mo = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : Colors.black87;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 74,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected
                  ? AppColors.primary
                  : Colors.grey.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_wd[date.weekday - 1],
                style: TextStyle(fontSize: 11, color: fg)),
            const SizedBox(height: 2),
            Text('${date.day}',
                style: TextStyle(
                    fontSize: 19, fontWeight: FontWeight.bold, color: fg)),
            Text(_mo[date.month - 1],
                style: TextStyle(fontSize: 10, color: fg)),
          ],
        ),
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  final String label;
  final bool booked;
  final String pastLabel;
  final bool selected;
  final VoidCallback? onTap;
  const _SlotChip({
    required this.label,
    required this.booked,
    required this.pastLabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? AppColors.primary
        : (booked ? Colors.grey.shade200 : Colors.white);
    final fg = selected
        ? Colors.white
        : (booked ? Colors.grey : Colors.black87);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected
                  ? AppColors.primary
                  : Colors.grey.withOpacity(0.4)),
        ),
        child: Text(
          booked ? '$label · $pastLabel' : label,
          style: TextStyle(
              fontSize: 12.5,
              color: fg,
              decoration: booked ? TextDecoration.lineThrough : null),
        ),
      ),
    );
  }
}
