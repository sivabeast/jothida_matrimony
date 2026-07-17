import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/astrology_service_config.dart';
import '../../models/profile_model.dart';
import '../../providers/astrology_config_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/profile_provider.dart';
import '../../services/firebase/astrologer_service.dart';

/// Book Your Appointment: pick a working day, pick a SESSION (Morning /
/// Afternoon — each capacity-limited), pay the service charge, then land on the
/// confirmation screen. A session that has reached its capacity is greyed out.
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
  String? _session;
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
    if (_date == null || _session == null) {
      _snack(context.l10n.pleaseSelectDateSession);
      return;
    }
    setState(() => _busy = true);
    // TESTING MODE — simulate a successful payment then create the booking.
    final paymentId = 'demo_${DateTime.now().millisecondsSinceEpoch}';
    await _createBooking(cfg, me, other, paymentId);
  }

  Future<void> _createBooking(AstrologyServiceConfig cfg, ProfileModel me,
      ProfileModel other, String paymentId) async {
    final pair = _pair(me, other);
    try {
      final id = await ref
          .read(matchAnalysisControllerProvider.notifier)
          .bookAppointment(
            groom: pair.groom,
            bride: pair.bride,
            date: _date!,
            slotMinutes: AppointmentSession.startMinutes(_session!),
            amount: cfg.serviceCharge,
            paymentId: paymentId,
            config: cfg,
          );
      if (!mounted) return;
      context.pushReplacement('/appointment-confirmation/$id', extra: {
        'date': _date!,
        'session': _session!,
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
        _session = null;
      });
      _snack(context.l10n.sessionJustFilled);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(context.l10n.bookingFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(astrologyServiceConfigProvider);
    final me = ref.watch(myProfileProvider).valueOrNull;
    final other =
        ref.watch(profileByUserIdProvider(widget.otherUserId)).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(context.l10n.bookYourAppointment),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            context.l10n.completeOwnProfileFirst,
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
        _label(context.l10n.selectDate),
        const SizedBox(height: 8),
        _dateStrip(dates),
        if (_date != null) ...[
          const SizedBox(height: 18),
          _label(context.l10n.selectSession),
          const SizedBox(height: 8),
          _sessionCards(cfg),
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
                ? context.l10n.processing
                : context.l10n.payAndConfirm(cfg.serviceCharge)),
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
                context.l10n.inPersonVisitNote,
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
                _session = null;
              }),
            );
          },
        ),
      );

  Widget _sessionCards(AstrologyServiceConfig cfg) {
    final counts =
        ref.watch(internalSessionCountsProvider).valueOrNull ?? const {};
    final dayCounts = counts[dateKeyOf(_date!)] ?? const <String, int>{};
    final now = DateTime.now();
    final isToday = dateKeyOf(_date!) == dateKeyOf(now);
    final nowMinutes = now.hour * 60 + now.minute;

    Widget card(String session, String window, int capacity, int endMinutes) {
      final l10n = context.l10n;
      final booked = dayCounts[session] ?? 0;
      final full = booked >= capacity;
      final past = isToday && nowMinutes >= endMinutes;
      final disabled = full || past || capacity <= 0;
      final remaining = (capacity - booked).clamp(0, capacity);
      final isMorning = session == AppointmentSession.morning;
      return _SessionCard(
        title: isMorning ? l10n.morning : l10n.evening,
        isMorning: isMorning,
        window: window,
        remaining: remaining,
        remainingLabel: l10n.leftLabel,
        disabled: disabled,
        disabledLabel: past
            ? l10n.closedLabel
            : (full ? l10n.sessionFull : l10n.unavailable),
        selected: _session == session,
        onTap: disabled ? null : () => setState(() => _session = session),
      );
    }

    return Column(
      children: [
        card(AppointmentSession.morning, '9:00 AM – 1:00 PM',
            cfg.morningCapacity, AppointmentSession.morningEnd),
        const SizedBox(height: 10),
        card(AppointmentSession.afternoon, '2:00 PM – 5:00 PM',
            cfg.afternoonCapacity, AppointmentSession.afternoonEnd),
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
            Expanded(
                child: Text(context.l10n.serviceCharge,
                    style: const TextStyle(
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

/// A selectable Morning / Evening session card showing remaining capacity.
class _SessionCard extends StatelessWidget {
  final String title;
  final bool isMorning;
  final String window;
  final int remaining;
  final String remainingLabel;
  final bool disabled;
  final String disabledLabel;
  final bool selected;
  final VoidCallback? onTap;
  const _SessionCard({
    required this.title,
    required this.isMorning,
    required this.window,
    required this.remaining,
    required this.remainingLabel,
    required this.disabled,
    required this.disabledLabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? AppColors.primary
        : (disabled
            ? Colors.grey.withOpacity(0.3)
            : Colors.grey.withOpacity(0.4));
    final bg = selected
        ? AppColors.primary.withOpacity(0.08)
        : (disabled ? Colors.grey.shade100 : Colors.white);
    final titleColor = disabled ? Colors.grey : Colors.black87;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: selected ? 1.6 : 1),
        ),
        child: Row(
          children: [
            Icon(isMorning ? Icons.wb_twilight : Icons.wb_sunny_outlined,
                color: disabled ? Colors.grey : AppColors.primary,
                size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: titleColor)),
                  const SizedBox(height: 2),
                  Text(window,
                      style:
                          TextStyle(fontSize: 12.5, color: Colors.grey[600])),
                ],
              ),
            ),
            if (disabled)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(disabledLabel,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600)),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$remaining',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
                  Text(remainingLabel,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            if (selected) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle, color: AppColors.primary),
            ],
          ],
        ),
      ),
    );
  }
}
