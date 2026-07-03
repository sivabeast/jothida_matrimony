import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/astrology_service_config.dart';
import '../../providers/astrology_config_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../services/firebase/astrologer_service.dart';
import '../../services/razorpay/razorpay_service.dart';

/// Standalone "Book Your Appointment" flow opened from the Astrology page.
///
/// Steps: 1) Select a CONSULTATION CATEGORY (admin-managed dropdown — never
/// hardcoded); 2) Select a date from a ROLLING ONE-WEEK schedule (working days
/// only, admin holidays removed); 3) Select a SESSION — Morning (9 AM–1 PM) or
/// Evening (2 PM–5 PM); no exact time slots — the assigned employee contacts
/// the user personally with the exact timing. Each session has a booking
/// capacity (max 5 by default); once full it is greyed out. 4) Pay — a
/// successful payment CONFIRMS the booking automatically (no admin approval
/// step). Everything comes from the admin-managed config.
class AstrologyAppointmentScreen extends ConsumerStatefulWidget {
  const AstrologyAppointmentScreen({super.key});

  @override
  ConsumerState<AstrologyAppointmentScreen> createState() =>
      _AstrologyAppointmentScreenState();
}

class _AstrologyAppointmentScreenState
    extends ConsumerState<AstrologyAppointmentScreen> {
  static const int _fee = AppConstants.appointmentBookingFee; // ₹50

  DateTime? _date;
  String? _session;
  String? _category;
  bool _busy = false;

  final RazorpayService _razorpay = RazorpayService();
  AstrologyServiceConfig? _pendingCfg;

  @override
  void initState() {
    super.initState();
    _razorpay.init(onSuccess: _onPaymentSuccess, onFailure: _onPaymentFailure);
  }

  @override
  void dispose() {
    _razorpay.dispose();
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Step 3 — collect the ₹50 booking charge via Razorpay; the session is only
  /// reserved once payment succeeds (handled in [_onPaymentSuccess]).
  Future<void> _confirm(AstrologyServiceConfig cfg) async {
    if (_category == null || _category!.trim().isEmpty) {
      _snack('Please select a consultation category.');
      return;
    }
    if (_date == null || _session == null) {
      _snack('Please select a date and session.');
      return;
    }
    setState(() => _busy = true);
    _pendingCfg = cfg;
    final user = ref.read(currentUserProvider).valueOrNull;
    _razorpay.openCheckout(
      amountPaise: _fee * 100,
      description: 'Office Visit Appointment Booking',
      notes: {'type': 'astrology_appointment'},
      userPhone: user?.phone ?? '',
      userEmail: user?.email ?? '',
      userName: user?.displayName ?? '',
    );
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    final cfg = _pendingCfg;
    if (cfg == null || _date == null || _session == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      final id = await ref
          .read(matchAnalysisControllerProvider.notifier)
          .bookServiceAppointment(
            date: _date!,
            session: _session!,
            config: cfg,
            category: _category ?? '',
            amount: _fee,
            paymentId: response.paymentId ?? 'razorpay',
          );
      if (!mounted) return;
      context.pushReplacement('/appointment-confirmation/$id', extra: {
        'date': _date!,
        'session': _session!,
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
        _session = null;
      });
      _snack('That session just filled up (you were not charged for it). '
          'Please choose another.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Payment succeeded but the booking could not be saved. Please '
          'contact support.');
    }
  }

  void _onPaymentFailure(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _busy = false);
    _snack('Payment failed or cancelled. You have not been charged.');
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
    if (dates.isEmpty) {
      return _closed(message: 'No working days available this week.');
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _banner(cfg),
        const SizedBox(height: 16),
        _stepLabel(1, 'Select Consultation Category'),
        const SizedBox(height: 8),
        _categoryDropdown(cfg),
        const SizedBox(height: 18),
        _stepLabel(2, 'Select Date'),
        const SizedBox(height: 8),
        _dateStrip(dates),
        if (_date != null) ...[
          const SizedBox(height: 18),
          _stepLabel(3, 'Select Session — Morning or Evening'),
          const SizedBox(height: 4),
          Text(
            'No fixed time slots — after your booking is confirmed, our '
            'employee will contact you personally with the exact timing.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          _sessionCards(cfg),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_busy ||
                    _category == null ||
                    _date == null ||
                    _session == null)
                ? null
                : () => _confirm(cfg),
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_outline, size: 20),
            label: Text(
                _busy ? 'Processing…' : 'Pay ₹$_fee & Confirm Appointment',
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
                      'date and session below.'
                  : rules,
              style:
                  TextStyle(fontSize: 12.5, color: Colors.grey[800], height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// Admin-managed consultation categories (Appointment Settings) — the user
  /// must pick one before paying.
  Widget _categoryDropdown(AstrologyServiceConfig cfg) {
    final categories = cfg.enabledCategories;
    if (categories.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Text(
          'No consultation categories are available right now. Please try '
          'again later.',
          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
        ),
      );
    }
    // If a previously-selected category was disabled meanwhile, clear it.
    final names = categories.map((c) => c.name).toList();
    final value = names.contains(_category) ? _category : null;
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      hint: const Text('Choose your consultation reason'),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        prefixIcon:
            const Icon(Icons.category_outlined, color: AppColors.primary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: [
        for (final c in categories)
          DropdownMenuItem(value: c.name, child: Text(c.name)),
      ],
      onChanged: (v) => setState(() => _category = v),
    );
  }

  Widget _stepLabel(int n, String t) => Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
            child: Text('$n',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Text(t,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
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
      final booked = dayCounts[session] ?? 0;
      final full = booked >= capacity;
      final past = isToday && nowMinutes >= endMinutes;
      final disabled = full || past || capacity <= 0;
      final remaining = (capacity - booked).clamp(0, capacity);
      return _SessionCard(
        title: AppointmentSession.shortLabel(session),
        window: window,
        remaining: remaining,
        disabled: disabled,
        disabledLabel: past ? 'Closed' : (full ? 'Session Full' : 'Unavailable'),
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

/// A selectable Morning / Afternoon session card showing remaining capacity.
class _SessionCard extends StatelessWidget {
  final String title;
  final String window;
  final int remaining;
  final bool disabled;
  final String disabledLabel;
  final bool selected;
  final VoidCallback? onTap;
  const _SessionCard({
    required this.title,
    required this.window,
    required this.remaining,
    required this.disabled,
    required this.disabledLabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? AppColors.primary
        : (disabled ? Colors.grey.withOpacity(0.3) : Colors.grey.withOpacity(0.4));
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
            Icon(
                title == 'Morning'
                    ? Icons.wb_twilight
                    : Icons.wb_sunny_outlined,
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
                  Text('left',
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
