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

/// Direct Astrologer Visit booking flow (spec §3, Service 2): the user picks a
/// date and an available slot, then sends the appointment request. There is NO
/// online payment — the user pays the astrologer directly (cash / UPI / card) at
/// the in-person visit. (The In-App consultation service has been removed; the
/// only two services are Online Match Analysis and Direct Visit.)
class ConsultationBookingScreen extends ConsumerStatefulWidget {
  final String astrologerId;
  const ConsultationBookingScreen({super.key, required this.astrologerId});

  @override
  ConsumerState<ConsultationBookingScreen> createState() =>
      _ConsultationBookingScreenState();
}

class _ConsultationBookingScreenState
    extends ConsumerState<ConsultationBookingScreen> {
  // Direct Visit is the only consultation mode now.
  static const ConsultationMode _mode = ConsultationMode.directVisit;
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
    if (_date == null || _slot == null) {
      _snack('Please select a date and time slot.');
      return;
    }
    setState(() => _submitting = true);
    try {
      // Direct Visit is unpaid in the app — the user pays in person at the visit.
      await ref.read(consultationControllerProvider.notifier).book(
            astrologerId: a.id,
            astrologerName: a.fullName,
            mode: _mode,
            amount: _fee(a),
            note: _note.text,
            visitDate: _date,
            slotStartMinutes: _slot,
          );
      if (!mounted) return;
      _snack('Appointment request sent to ${a.fullName}. Pay in person at the '
          'visit.');
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
        title: const Text('Book Direct Visit'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => const Center(child: Text('Could not load astrologer')),
        data: (a) => a == null
            ? const Center(child: Text('Astrologer not found'))
            // SPEC §10: if the astrologer is unavailable, block new bookings.
            : (!a.isAvailableNow || !a.offersDirectVisit)
                ? _unavailable(a)
                : _body(a),
      ),
    );
  }

  Widget _unavailable(AstrologerAccount a) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_busy,
                  size: 64, color: AppColors.primary.withOpacity(0.4)),
              const SizedBox(height: 16),
              const Text('Currently Unavailable',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                '${a.fullName} is not accepting direct-visit bookings right now. '
                'Please check back later or choose another astrologer.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary)),
              ),
            ],
          ),
        ),
      );

  Widget _body(AstrologerAccount a) {
    final fee = _fee(a);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _astrologerHeader(a, fee),
        const SizedBox(height: 18),
        _label('Select Date'),
        const SizedBox(height: 8),
        _dateStrip(a),
        if (_date != null) ...[
          const SizedBox(height: 18),
          _label('Select Time Slot'),
          const SizedBox(height: 8),
          _slotGrid(a),
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
            onPressed: _submitting ? null : () => _submit(a),
            icon: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_outlined),
            label: Text(_submitting ? 'Processing…' : 'Send Booking Request'),
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
            const Icon(Icons.money_off_outlined,
                size: 18, color: AppColors.gold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No online payment. You pay the astrologer directly (cash / UPI / '
                'card) at the in-person visit.',
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
