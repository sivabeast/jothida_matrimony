import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/astrologer_account_model.dart';
import '../../models/consultation_model.dart';
import '../../providers/astrologer_provider.dart';
import '../../providers/consultation_provider.dart';
import '../../services/firebase/consultation_service.dart';

/// Consultation booking flow: pick a mode (In-App / Direct Visit), then — for a
/// Direct Visit — a date and an available slot, then send the request. Payment
/// is collected later, only after the astrologer accepts.
class ConsultationBookingScreen extends ConsumerStatefulWidget {
  final String astrologerId;
  const ConsultationBookingScreen({super.key, required this.astrologerId});

  @override
  ConsumerState<ConsultationBookingScreen> createState() =>
      _ConsultationBookingScreenState();
}

class _ConsultationBookingScreenState
    extends ConsumerState<ConsultationBookingScreen> {
  ConsultationMode? _mode;
  DateTime? _date;
  int? _slot;
  final _note = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int _fee(AstrologerAccount a) {
    if (a.consultationFee > 0) return a.consultationFee.toInt();
    if (a.services.isNotEmpty) {
      return a.services.map((s) => s.price).reduce((x, y) => x < y ? x : y);
    }
    return 0;
  }

  Future<void> _submit(AstrologerAccount a) async {
    if (_mode == ConsultationMode.directVisit &&
        (_date == null || _slot == null)) {
      _snack('Please select a date and time slot.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(consultationControllerProvider.notifier).book(
            astrologerId: a.id,
            astrologerName: a.fullName,
            mode: _mode!,
            amount: _fee(a),
            note: _note.text,
            visitDate: _date,
            slotStartMinutes: _slot,
          );
      if (!mounted) return;
      _snack('Request sent to ${a.fullName}. You can pay once they accept.');
      context.go('/my-consultations');
    } on ConsultationSlotTakenException {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _slot = null;
      });
      _snack('That slot was just booked. Please choose another.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('Could not send the request. Please try again.');
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(astrologerAccountByIdProvider(widget.astrologerId));
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Book Consultation'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => const Center(child: Text('Could not load astrologer')),
        data: (a) => a == null
            ? const Center(child: Text('Astrologer not found'))
            : _body(a),
      ),
    );
  }

  Widget _body(AstrologerAccount a) {
    final fee = _fee(a);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _astrologerHeader(a, fee),
        const SizedBox(height: 18),
        _label('Consultation Mode'),
        const SizedBox(height: 8),
        _modeOption(
          a,
          ConsultationMode.inApp,
          Icons.phone_android,
          'Book, pay & receive a deep match-analysis report in the app.',
          enabled: a.offersInApp,
        ),
        const SizedBox(height: 10),
        _modeOption(
          a,
          ConsultationMode.directVisit,
          Icons.place_outlined,
          'Meet the astrologer in person at a date & time you choose.',
          enabled: a.offersDirectVisit,
        ),
        if (_mode == ConsultationMode.directVisit) ...[
          const SizedBox(height: 20),
          _label('Select Date'),
          const SizedBox(height: 8),
          _dateStrip(a),
          if (_date != null) ...[
            const SizedBox(height: 18),
            _label('Select Time Slot'),
            const SizedBox(height: 8),
            _slotGrid(a),
          ],
        ],
        const SizedBox(height: 18),
        _label('Note (optional)'),
        const SizedBox(height: 8),
        TextField(
          controller: _note,
          maxLines: 3,
          maxLength: 400,
          decoration: InputDecoration(
            hintText: 'Anything you want the astrologer to know…',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 8),
        _payInfoBanner(),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_mode == null || _submitting) ? null : () => _submit(a),
            icon: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_outlined),
            label: Text(_submitting ? 'Sending…' : 'Send Booking Request'),
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

  Widget _astrologerHeader(AstrologerAccount a, int fee) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              backgroundImage:
                  a.photoUrl.isNotEmpty ? NetworkImage(a.photoUrl) : null,
              child: a.photoUrl.isEmpty
                  ? const Icon(Icons.person, color: AppColors.primary)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.fullName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 3),
                  Text(
                    '${a.slotDurationMinutes}-min slots · '
                    '${formatMinutes(a.availableStartMinutes)}–${formatMinutes(a.availableEndMinutes)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            if (fee > 0)
              Text('₹$fee',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      fontSize: 18)),
          ],
        ),
      );

  Widget _modeOption(
    AstrologerAccount a,
    ConsultationMode mode,
    IconData icon,
    String desc, {
    required bool enabled,
  }) {
    final selected = _mode == mode;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled
            ? () => setState(() {
                  _mode = mode;
                  if (mode == ConsultationMode.inApp) {
                    _date = null;
                    _slot = null;
                  }
                })
            : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.grey.withOpacity(0.3),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: selected ? AppColors.primary : Colors.grey[600]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mode.label,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(
                        enabled
                            ? desc
                            : 'Not offered by this astrologer.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected ? AppColors.primary : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateStrip(AstrologerAccount a) {
    final booked =
        ref.watch(astrologerBookedSlotsProvider(a.id)).valueOrNull ?? const {};
    final today = DateTime.now();
    final days = List.generate(
        30, (i) => DateTime(today.year, today.month, today.day + i));
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final d = days[i];
          final takenCount = booked[dateKeyOf(d)]?.length ?? 0;
          final avail =
              dateAvailability(a, d, activeBookingsOnDate: takenCount);
          final selectable = avail.isSelectable;
          final selected = _date != null && dateKeyOf(_date!) == dateKeyOf(d);
          return _DateCard(
            date: d,
            selectable: selectable,
            selected: selected,
            note: avail == DateAvailability.fullyBooked
                ? 'Fully Booked'
                : selectable
                    ? null
                    : avail.label,
            onTap: selectable
                ? () => setState(() {
                      _date = d;
                      _slot = null;
                    })
                : null,
          );
        },
      ),
    );
  }

  Widget _slotGrid(AstrologerAccount a) {
    final booked =
        ref.watch(astrologerBookedSlotsProvider(a.id)).valueOrNull ?? const {};
    final takenKeys = booked[dateKeyOf(_date!)] ?? <String>{};
    final takenMinutes = takenKeys
        .map(minutesFromSlotKey)
        .whereType<int>()
        .toSet();
    final slots = slotsForDate(a, _date!, bookedStartMinutes: takenMinutes);
    if (slots.isEmpty) {
      return const Text('No slots configured for this astrologer.',
          style: TextStyle(color: Colors.grey));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in slots)
          _SlotChip(
            label: s.label,
            booked: s.booked,
            selected: _slot == s.startMinutes,
            onTap: s.booked
                ? null
                : () => setState(() => _slot = s.startMinutes),
          ),
      ],
    );
  }

  Widget _payInfoBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.gold.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_clock_outlined,
                size: 18, color: AppColors.gold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _mode == ConsultationMode.directVisit
                    ? 'You only pay after the astrologer confirms your visit.'
                    : 'You only pay after the astrologer accepts your request.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[800]),
              ),
            ),
          ],
        ),
      );

  Widget _label(String t) => Text(t,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14));
}

class _DateCard extends StatelessWidget {
  final DateTime date;
  final bool selectable;
  final bool selected;
  final String? note;
  final VoidCallback? onTap;
  const _DateCard({
    required this.date,
    required this.selectable,
    required this.selected,
    required this.note,
    required this.onTap,
  });

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _mo = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? AppColors.primary
        : (selectable ? Colors.white : Colors.grey.shade100);
    final fg = selected
        ? Colors.white
        : (selectable ? Colors.black87 : Colors.grey);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppColors.primary : Colors.grey.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_wd[date.weekday - 1],
                style: TextStyle(fontSize: 11, color: fg)),
            const SizedBox(height: 2),
            Text('${date.day}',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: fg)),
            Text(_mo[date.month - 1],
                style: TextStyle(fontSize: 10, color: fg)),
            if (note != null)
              Text(note!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 8.5,
                      color: note == 'Fully Booked'
                          ? AppColors.error
                          : Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  final String label;
  final bool booked;
  final bool selected;
  final VoidCallback? onTap;
  const _SlotChip({
    required this.label,
    required this.booked,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : Colors.grey.withOpacity(0.4),
          ),
        ),
        child: Text(
          booked ? '$label · booked' : label,
          style: TextStyle(
              fontSize: 12.5,
              color: fg,
              decoration: booked ? TextDecoration.lineThrough : null),
        ),
      ),
    );
  }
}
