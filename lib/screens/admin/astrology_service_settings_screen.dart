import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/astrology_service_config.dart';
import '../../providers/astrology_config_provider.dart';

/// Admin "Astrology Management" screen — the single source of truth for
/// everything shown on the user-facing Astrology page and appointment booking
/// (`astrology_service/config`): astrologer profile, address, description,
/// services, professional details, working days, holidays, slot window, per-slot
/// enable/disable, booking availability and appointment rules. Writes are
/// admin/internal-only (firestore.rules). No astrology data is hardcoded in the
/// user app — it all flows from here.
class AstrologyServiceSettingsScreen extends ConsumerStatefulWidget {
  const AstrologyServiceSettingsScreen({super.key});

  @override
  ConsumerState<AstrologyServiceSettingsScreen> createState() =>
      _AstrologyServiceSettingsScreenState();
}

class _AstrologyServiceSettingsScreenState
    extends ConsumerState<AstrologyServiceSettingsScreen> {
  final _c = <String, TextEditingController>{};
  bool _seeded = false;
  bool _saving = false;

  // Non-text state.
  bool _bookingEnabled = true;
  final Set<int> _workingWeekdays = {};
  final List<String> _holidayDates = [];
  final Set<int> _disabledSlots = {};

  static const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  TextEditingController _ctrl(String key, [String initial = '']) =>
      _c.putIfAbsent(key, () => TextEditingController(text: initial));

  void _seed(AstrologyServiceConfig cfg) {
    if (_seeded) return;
    _seeded = true;
    _ctrl('serviceIntro', cfg.serviceIntro);
    _ctrl('reportIncludes', cfg.reportIncludes.join('\n'));
    _ctrl('deliveryTime', cfg.deliveryTime);
    _ctrl('serviceCharge', '${cfg.serviceCharge}');
    _ctrl('expertName', cfg.expertName);
    _ctrl('expertPhotoUrl', cfg.expertPhotoUrl);
    _ctrl('expertExperience', cfg.expertExperience);
    _ctrl('expertSpecialization', cfg.expertSpecialization);
    _ctrl('expertIntro', cfg.expertIntro);
    _ctrl('services', cfg.services.join('\n'));
    _ctrl('expertContactPhone', cfg.expertContactPhone);
    _ctrl('officeAddress', cfg.officeAddress);
    _ctrl('officeContactNumber', cfg.officeContactNumber);
    _ctrl('appointmentRules', cfg.appointmentRules);
    _ctrl('slotStartMinutes', '${cfg.slotStartMinutes}');
    _ctrl('slotEndMinutes', '${cfg.slotEndMinutes}');
    _ctrl('lunchStartMinutes', '${cfg.lunchStartMinutes}');
    _ctrl('lunchEndMinutes', '${cfg.lunchEndMinutes}');
    _ctrl('slotDurationMinutes', '${cfg.slotDurationMinutes}');
    _ctrl('maxAdvanceWorkingDays', '${cfg.maxAdvanceWorkingDays}');
    _bookingEnabled = cfg.bookingEnabled;
    _workingWeekdays
      ..clear()
      ..addAll(cfg.workingWeekdays);
    _holidayDates
      ..clear()
      ..addAll(cfg.holidayDates);
    _disabledSlots
      ..clear()
      ..addAll(cfg.disabledSlotMinutes);
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _int(String key, int fallback) =>
      int.tryParse(_ctrl(key).text.trim()) ?? fallback;

  List<ConsultationSlot> _currentSlots(AstrologyServiceConfig cfg) =>
      generateSlots(
        startMinutes: _int('slotStartMinutes', cfg.slotStartMinutes),
        endMinutes: _int('slotEndMinutes', cfg.slotEndMinutes),
        slotDuration: _int('slotDurationMinutes', cfg.slotDurationMinutes),
        lunchStart: _int('lunchStartMinutes', cfg.lunchStartMinutes),
        lunchEnd: _int('lunchEndMinutes', cfg.lunchEndMinutes),
      );

  Future<void> _addHoliday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (picked == null) return;
    final key = dateKeyOf(picked);
    if (!_holidayDates.contains(key)) {
      setState(() => _holidayDates
        ..add(key)
        ..sort());
    }
  }

  Future<void> _save(AstrologyServiceConfig base) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final updated = base.copyWith(
      serviceIntro: _ctrl('serviceIntro').text.trim(),
      reportIncludes: _lines('reportIncludes'),
      deliveryTime: _ctrl('deliveryTime').text.trim(),
      serviceCharge: _int('serviceCharge', base.serviceCharge),
      expertName: _ctrl('expertName').text.trim(),
      expertPhotoUrl: _ctrl('expertPhotoUrl').text.trim(),
      expertExperience: _ctrl('expertExperience').text.trim(),
      expertSpecialization: _ctrl('expertSpecialization').text.trim(),
      expertIntro: _ctrl('expertIntro').text.trim(),
      services: _lines('services'),
      expertContactPhone: _ctrl('expertContactPhone').text.trim(),
      officeAddress: _ctrl('officeAddress').text.trim(),
      officeContactNumber: _ctrl('officeContactNumber').text.trim(),
      appointmentRules: _ctrl('appointmentRules').text.trim(),
      slotStartMinutes: _int('slotStartMinutes', base.slotStartMinutes),
      slotEndMinutes: _int('slotEndMinutes', base.slotEndMinutes),
      lunchStartMinutes: _int('lunchStartMinutes', base.lunchStartMinutes),
      lunchEndMinutes: _int('lunchEndMinutes', base.lunchEndMinutes),
      slotDurationMinutes:
          _int('slotDurationMinutes', base.slotDurationMinutes),
      maxAdvanceWorkingDays:
          _int('maxAdvanceWorkingDays', base.maxAdvanceWorkingDays),
      bookingEnabled: _bookingEnabled,
      workingWeekdays: (_workingWeekdays.toList()..sort()),
      holidayDates: List<String>.from(_holidayDates),
      disabledSlotMinutes: (_disabledSlots.toList()..sort()),
    );
    try {
      await ref.read(astrologyConfigServiceProvider).save(updated);
      messenger.showSnackBar(
          const SnackBar(content: Text('Astrology settings saved.')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> _lines(String key) => _ctrl(key)
      .text
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(astrologyServiceConfigProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Astrology Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => _form(AstrologyServiceConfig.defaults),
        data: (cfg) => _form(cfg),
      ),
    );
  }

  Widget _form(AstrologyServiceConfig cfg) {
    _seed(cfg);
    final slots = _currentSlots(cfg);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Astrologer profile (shown on the user Astrology page) ──────────
        _section('Astrologer Profile'),
        _field('expertName', 'Astrologer name'),
        _field('expertPhotoUrl', 'Profile photo URL'),
        _field('expertExperience', 'Experience (e.g. 15+ years)'),
        _field('expertSpecialization', 'Specialization'),
        _field('expertIntro', 'Description / about', maxLines: 3),
        _field('expertContactPhone', 'Contact phone (blank = office number)'),

        // ── Services Offered ───────────────────────────────────────────────
        _section('Services Offered'),
        _hint('One service per line — shown on the Astrology page.'),
        _field('services', 'Services (one per line)', maxLines: 6),

        // ── Office / address ───────────────────────────────────────────────
        _section('Address / Office'),
        _field('officeAddress', 'Address / location', maxLines: 2),
        _field('officeContactNumber', 'Office contact number'),

        // ── Horoscope report copy (existing service details) ───────────────
        _section('Horoscope Report Service'),
        _field('serviceIntro', 'Service introduction', maxLines: 3),
        _field('reportIncludes', 'What the report includes (one per line)',
            maxLines: 5),
        _field('deliveryTime', 'Estimated delivery time'),
        _field('serviceCharge', 'Report service charge (₹)', number: true),

        // ── Appointment availability ───────────────────────────────────────
        _section('Appointment Availability'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: AppColors.primary,
          title: const Text('Booking available',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(
              _bookingEnabled
                  ? 'Users can book appointments.'
                  : 'Booking is closed for all users.',
              style: const TextStyle(fontSize: 12)),
          value: _bookingEnabled,
          onChanged: (v) => setState(() => _bookingEnabled = v),
        ),

        // ── Working days ───────────────────────────────────────────────────
        _section('Working Days'),
        _hint('Only selected days appear in the booking schedule.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(7, (i) {
            final weekday = i + 1; // Mon = 1 … Sun = 7
            final on = _workingWeekdays.contains(weekday);
            return FilterChip(
              label: Text(_weekdayLabels[i]),
              selected: on,
              selectedColor: AppColors.primary.withOpacity(0.15),
              checkmarkColor: AppColors.primary,
              onSelected: (sel) => setState(() {
                if (sel) {
                  _workingWeekdays.add(weekday);
                } else {
                  _workingWeekdays.remove(weekday);
                }
              }),
            );
          }),
        ),

        // ── Holidays ───────────────────────────────────────────────────────
        _section('Holiday Days'),
        _hint('Specific dates the office is closed (removed from the schedule).'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final h in _holidayDates)
              InputChip(
                label: Text(h),
                onDeleted: () => setState(() => _holidayDates.remove(h)),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18, color: AppColors.primary),
              label: const Text('Add holiday'),
              onPressed: _addHoliday,
            ),
          ],
        ),

        // ── Slot window ────────────────────────────────────────────────────
        _section('Time Slot Window (minutes from midnight)'),
        _hint('600 = 10:00 AM · 780 = 1:00 PM · 840 = 2:00 PM · 1020 = 5:00 PM'),
        _field('slotStartMinutes', 'Day start (minutes)', number: true),
        _field('slotEndMinutes', 'Day end (minutes)', number: true),
        _field('lunchStartMinutes', 'Lunch start (minutes)', number: true),
        _field('lunchEndMinutes', 'Lunch end (minutes)', number: true),
        _field('slotDurationMinutes', 'Slot duration (minutes)', number: true),
        _field('maxAdvanceWorkingDays', 'Bookable working days ahead',
            number: true),

        // ── Enable / disable individual slots ──────────────────────────────
        _section('Available Time Slots'),
        _hint('Tap a slot to enable/disable it. Disabled slots are hidden from '
            'users.'),
        if (slots.isEmpty)
          const Text('No slots — check the window values above.',
              style: TextStyle(color: Colors.grey))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in slots)
                () {
                  final disabled = _disabledSlots.contains(s.startMinutes);
                  return FilterChip(
                    label: Text(s.label),
                    selected: !disabled,
                    selectedColor: AppColors.success.withOpacity(0.15),
                    checkmarkColor: AppColors.success,
                    backgroundColor: Colors.grey.shade200,
                    onSelected: (_) => setState(() {
                      if (disabled) {
                        _disabledSlots.remove(s.startMinutes);
                      } else {
                        _disabledSlots.add(s.startMinutes);
                      }
                    }),
                  );
                }(),
            ],
          ),

        // ── Appointment rules ──────────────────────────────────────────────
        _section('Appointment Rules'),
        _field('appointmentRules', 'Rules / instructions shown to users',
            maxLines: 3),

        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : () => _save(cfg),
            icon: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
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

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.primary)),
      );

  Widget _hint(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      );

  Widget _field(String key, String label,
      {int maxLines = 1, bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _ctrl(key),
        maxLines: maxLines,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters:
            number ? [FilteringTextInputFormatter.digitsOnly] : null,
        onChanged: number ? (_) => setState(() {}) : null,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
