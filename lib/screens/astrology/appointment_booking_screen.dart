import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/astrology_service_config.dart';
import '../../models/profile_model.dart';
import '../../providers/astrology_config_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/profile_provider.dart';
import '../../services/firebase/astrologer_service.dart';

/// Book Your Appointment (spec §7–§11): pick one of the next 5 working days
/// (Mon–Fri, weekends skipped — never a month ahead), pick an available 1-hour
/// slot (a slot booked by one user is immediately unavailable to others), pay
/// the service charge online (Razorpay), then land on the confirmation screen.
class AppointmentBookingScreen extends ConsumerStatefulWidget {
  /// The accepted-match user id whose horoscope is compared with the user's.
  final String otherUserId;
  const AppointmentBookingScreen({super.key, required this.otherUserId});

  @override
  ConsumerState<AppointmentBookingScreen> createState() =>
      _AppointmentBookingScreenState();
}

class _AppointmentBookingScreenState
    extends ConsumerState<AppointmentBookingScreen> {
  DateTime? _date;
  int? _slot;
  bool _busy = false;

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Splits the user + their accepted match into groom (male) / bride.
  ({ProfileModel groom, ProfileModel bride}) _pair(
      ProfileModel me, ProfileModel other) {
    bool isMale(ProfileModel p) =>
        p.gender.trim().toLowerCase().startsWith('m');
    if (isMale(me) && !isMale(other)) return (groom: me, bride: other);
    if (!isMale(me) && isMale(other)) return (groom: other, bride: me);
    return (groom: me, bride: other);
  }

  Future<void> _startPayment(
      AstrologyServiceConfig cfg, ProfileModel me, ProfileModel other) async {
    if (_date == null || _slot == null) {
      _snack('Please select a date and time slot.');
      return;
    }
    setState(() => _busy = true);

    // ── TESTING MODE ──────────────────────────────────────────────────────
    // The app is in testing mode, so "Pay & Confirm" SIMULATES a successful
    // payment and immediately creates + saves the appointment. To go live,
    // replace this block with the real Razorpay checkout
    // (RazorpayService.openAppointmentCheckout) and call _createBooking(...)
    // from its payment-success callback with the real payment id.
    final paymentId = 'demo_${DateTime.now().millisecondsSinceEpoch}';
    await _createBooking(cfg, me, other, paymentId);
  }

  Future<void> _createBooking(AstrologyServiceConfig cfg, ProfileModel me,
      ProfileModel other, String paymentId) async {
    final pair = _pair(me, other);
    try {
      final id =
          await ref.read(matchAnalysisControllerProvider.notifier).bookAppointment(
                groom: pair.groom,
                bride: pair.bride,
                date: _date!,
                slotMinutes: _slot!,
                amount: cfg.serviceCharge,
                paymentId: paymentId,
                config: cfg,
              );
      if (!mounted) return;
      context.pushReplacement('/appointment-confirmation/$id', extra: {
        'date': _date!,
        'slot': _slot!,
        'address': cfg.officeAddress,
        'contact': cfg.officeContactNumber,
        'groom': pair.groom.fullName,
        'bride': pair.bride.fullName,
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
    final me = ref.watch(myProfileProvider).valueOrNull;
    final other = ref.watch(profileByUserIdProvider(widget.otherUserId)).valueOrNull;

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
        error: (_, __) =>
            _content(AstrologyServiceConfig.defaults, me, other),
        data: (cfg) => _content(cfg, me, other),
      ),
    );
  }

  Widget _content(
      AstrologyServiceConfig cfg, ProfileModel? me, ProfileModel? other) {
    if (me == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Complete your own profile before booking an appointment.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final dates = nextWorkingDays(cfg.maxAdvanceWorkingDays,
        workingWeekdays: cfg.workingWeekdays);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _visitBanner(),
        const SizedBox(height: 16),
        _label('Select Date'),
        const SizedBox(height: 8),
        _dateStrip(dates),
        if (_date != null) ...[
          const SizedBox(height: 18),
          _label('Select Time Slot'),
          const SizedBox(height: 8),
          _slotGrid(cfg),
        ],
        const SizedBox(height: 22),
        _chargeRow(cfg),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_busy || other == null)
                ? null
                : () => _startPayment(cfg, me, other),
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.lock_outline, size: 18),
            label: Text(_busy
                ? 'Processing…'
                : 'Pay ₹${cfg.serviceCharge} & Confirm'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              minimumSize: const Size.fromHeight(52),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _visitBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.gold.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on_outlined,
                size: 18, color: AppColors.gold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This is an in-person office visit. Choose your preferred date '
                'and time below.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[800]),
              ),
            ),
          ],
        ),
      );

  Widget _dateStrip(List<DateTime> dates) => SizedBox(
        height: 88,
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
    final now = DateTime.now();
    final isToday = dateKeyOf(_date!) == dateKeyOf(now);
    final nowMinutes = now.hour * 60 + now.minute;

    final slots = generateSlots(
      startMinutes: cfg.slotStartMinutes,
      endMinutes: cfg.slotEndMinutes,
      slotDuration: cfg.slotDurationMinutes,
      lunchStart: cfg.lunchStartMinutes,
      lunchEnd: cfg.lunchEndMinutes,
    );
    if (slots.isEmpty) {
      return const Text('No slots available for this date.',
          style: TextStyle(color: Colors.grey));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in slots)
          () {
            final past = isToday && s.startMinutes <= nowMinutes;
            final taken = takenMinutes.contains(s.startMinutes) || past;
            return _SlotChip(
              label: s.label,
              booked: taken,
              pastLabel: past ? 'Passed' : 'Already Booked',
              selected: _slot == s.startMinutes,
              onTap: taken
                  ? null
                  : () => setState(() => _slot = s.startMinutes),
            );
          }(),
      ],
    );
  }

  Widget _chargeRow(AstrologyServiceConfig cfg) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.payments_outlined,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            const Expanded(
                child: Text('Service Charge',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600))),
            Text('₹${cfg.serviceCharge}',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
          ],
        ),
      );

  Widget _label(String t) => Text(t,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14));
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
        width: 72,
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
