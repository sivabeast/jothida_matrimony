import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/astrology_service_config.dart';
import '../../providers/astrology_config_provider.dart';

/// Admin screen to edit the internal Horoscope Compatibility Report service
/// (`astrology_service/config`): expert profile, office details, service charge,
/// page copy and the appointment slot window. Writes are admin/internal-only
/// (firestore.rules).
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
    _ctrl('expertContactPhone', cfg.expertContactPhone);
    _ctrl('officeAddress', cfg.officeAddress);
    _ctrl('officeContactNumber', cfg.officeContactNumber);
    _ctrl('slotStartMinutes', '${cfg.slotStartMinutes}');
    _ctrl('slotEndMinutes', '${cfg.slotEndMinutes}');
    _ctrl('lunchStartMinutes', '${cfg.lunchStartMinutes}');
    _ctrl('lunchEndMinutes', '${cfg.lunchEndMinutes}');
    _ctrl('slotDurationMinutes', '${cfg.slotDurationMinutes}');
    _ctrl('maxAdvanceWorkingDays', '${cfg.maxAdvanceWorkingDays}');
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

  Future<void> _save(AstrologyServiceConfig base) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final updated = base.copyWith(
      serviceIntro: _ctrl('serviceIntro').text.trim(),
      reportIncludes: _ctrl('reportIncludes')
          .text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      deliveryTime: _ctrl('deliveryTime').text.trim(),
      serviceCharge: _int('serviceCharge', base.serviceCharge),
      expertName: _ctrl('expertName').text.trim(),
      expertPhotoUrl: _ctrl('expertPhotoUrl').text.trim(),
      expertExperience: _ctrl('expertExperience').text.trim(),
      expertSpecialization: _ctrl('expertSpecialization').text.trim(),
      expertIntro: _ctrl('expertIntro').text.trim(),
      expertContactPhone: _ctrl('expertContactPhone').text.trim(),
      officeAddress: _ctrl('officeAddress').text.trim(),
      officeContactNumber: _ctrl('officeContactNumber').text.trim(),
      slotStartMinutes: _int('slotStartMinutes', base.slotStartMinutes),
      slotEndMinutes: _int('slotEndMinutes', base.slotEndMinutes),
      lunchStartMinutes: _int('lunchStartMinutes', base.lunchStartMinutes),
      lunchEndMinutes: _int('lunchEndMinutes', base.lunchEndMinutes),
      slotDurationMinutes:
          _int('slotDurationMinutes', base.slotDurationMinutes),
      maxAdvanceWorkingDays:
          _int('maxAdvanceWorkingDays', base.maxAdvanceWorkingDays),
    );
    try {
      await ref.read(astrologyConfigServiceProvider).save(updated);
      messenger.showSnackBar(
          const SnackBar(content: Text('Astrology service settings saved.')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(astrologyServiceConfigProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Astrology Service'),
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
    final previewSlots = generateSlots(
      startMinutes: _int('slotStartMinutes', cfg.slotStartMinutes),
      endMinutes: _int('slotEndMinutes', cfg.slotEndMinutes),
      slotDuration: _int('slotDurationMinutes', cfg.slotDurationMinutes),
      lunchStart: _int('lunchStartMinutes', cfg.lunchStartMinutes),
      lunchEnd: _int('lunchEndMinutes', cfg.lunchEndMinutes),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section('Service Page'),
        _field('serviceIntro', 'Service introduction', maxLines: 3),
        _field('reportIncludes', 'What the report includes (one per line)',
            maxLines: 5),
        _field('deliveryTime', 'Estimated delivery time'),
        _field('serviceCharge', 'Service charge (₹)', number: true),
        _section('Astrology Expert'),
        _field('expertName', 'Expert name'),
        _field('expertPhotoUrl', 'Expert photo URL'),
        _field('expertExperience', 'Experience (e.g. 15+ years)'),
        _field('expertSpecialization', 'Specialization'),
        _field('expertIntro', 'Short introduction', maxLines: 3),
        _field('expertContactPhone',
            'Contact Expert phone (blank = office number)'),
        _section('Office (Appointment Confirmation)'),
        _field('officeAddress', 'Office address', maxLines: 2),
        _field('officeContactNumber', 'Office contact number'),
        _section('Appointment Slots (minutes from midnight)'),
        const Text(
          'Appointments are Mon–Fri only. 600 = 10:00 AM, 780 = 1:00 PM, '
          '840 = 2:00 PM, 1020 = 5:00 PM.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        _field('slotStartMinutes', 'Day start (minutes)', number: true),
        _field('slotEndMinutes', 'Day end (minutes)', number: true),
        _field('lunchStartMinutes', 'Lunch start (minutes)', number: true),
        _field('lunchEndMinutes', 'Lunch end (minutes)', number: true),
        _field('slotDurationMinutes', 'Slot duration (minutes)', number: true),
        _field('maxAdvanceWorkingDays', 'Bookable working days ahead',
            number: true),
        const SizedBox(height: 8),
        Text(
          'Preview: ${previewSlots.isEmpty ? 'no slots' : previewSlots.map((s) => s.label).join(', ')}',
          style: const TextStyle(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: AppColors.primary),
        ),
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
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.primary)),
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
