import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/astrology_service_config.dart';
import '../../providers/astrology_config_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/network_photo.dart';

/// Uploads an astrology media file (image or PDF) to Cloudinary and returns the
/// secure URL. Reuses the generic attachment uploader (unique id per upload).
Future<String> _uploadAstrologyMedia(WidgetRef ref, File file,
        {required bool isImage}) =>
    ref.read(storageServiceProvider).uploadChatAttachment(
        threadId: 'astrology_media', file: file, isImage: isImage);

/// Admin "Astrology Management" — the single source of truth for the entire
/// user-facing Astrology module. Manages the astrologer profile (with photo
/// upload), services, certificates, awards, news & media, contact details and
/// the full appointment configuration (working days, hours, slot duration,
/// break, holiday/blocked dates). Everything saved here flows LIVE to the user
/// Astrology page via [astrologyServiceConfigProvider]. Nothing is hardcoded.
class AstrologyServiceSettingsScreen extends ConsumerStatefulWidget {
  const AstrologyServiceSettingsScreen({super.key});

  @override
  ConsumerState<AstrologyServiceSettingsScreen> createState() =>
      _AstrologyServiceSettingsScreenState();
}

class _AstrologyServiceSettingsScreenState
    extends ConsumerState<AstrologyServiceSettingsScreen> {
  final _c = <String, TextEditingController>{};
  final _serviceInput = TextEditingController();
  bool _seeded = false;
  bool _saving = false;
  bool _uploadingPhoto = false;

  // Structured state.
  String _photoUrl = '';
  bool _bookingEnabled = true;
  final Set<int> _workingWeekdays = {};
  final List<String> _services = [];
  final List<AstrologyCertificate> _certificates = [];
  final List<AstrologyAward> _awards = [];
  final List<AstrologyNews> _news = [];
  final List<String> _holidayDates = [];
  final Set<int> _disabledSlots = {};
  int _slotStart = 600;
  int _slotEnd = 1020;
  int _lunchStart = 780;
  int _lunchEnd = 840;
  int _slotDuration = 60;
  int _breakDuration = 0;

  static const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _durationOptions = [15, 20, 30, 45, 60];
  static const _breakOptions = [0, 5, 10, 15, 30];

  TextEditingController _ctrl(String key, [String initial = '']) =>
      _c.putIfAbsent(key, () => TextEditingController(text: initial));

  void _seed(AstrologyServiceConfig cfg) {
    if (_seeded) return;
    _seeded = true;
    _ctrl('expertName', cfg.expertName);
    _ctrl('expertExperience', cfg.expertExperience);
    _ctrl('expertSpecialization', cfg.expertSpecialization);
    _ctrl('expertIntro', cfg.expertIntro);
    _ctrl('officeContactNumber', cfg.officeContactNumber);
    _ctrl('whatsappNumber', cfg.whatsappNumber);
    _ctrl('email', cfg.email);
    _ctrl('officeAddress', cfg.officeAddress);
    _ctrl('mapLocation', cfg.mapLocation);
    _ctrl('appointmentRules', cfg.appointmentRules);
    _ctrl('serviceIntro', cfg.serviceIntro);
    _ctrl('reportIncludes', cfg.reportIncludes.join('\n'));
    _ctrl('deliveryTime', cfg.deliveryTime);
    _ctrl('serviceCharge', '${cfg.serviceCharge}');
    _ctrl('maxAdvanceWorkingDays', '${cfg.maxAdvanceWorkingDays}');
    _photoUrl = cfg.expertPhotoUrl;
    _bookingEnabled = cfg.bookingEnabled;
    _workingWeekdays
      ..clear()
      ..addAll(cfg.workingWeekdays);
    _services
      ..clear()
      ..addAll(cfg.services);
    _certificates
      ..clear()
      ..addAll(cfg.certificates);
    _awards
      ..clear()
      ..addAll(cfg.awards);
    _news
      ..clear()
      ..addAll(cfg.news);
    _holidayDates
      ..clear()
      ..addAll(cfg.holidayDates);
    _disabledSlots
      ..clear()
      ..addAll(cfg.disabledSlotMinutes);
    _slotStart = cfg.slotStartMinutes;
    _slotEnd = cfg.slotEndMinutes;
    _lunchStart = cfg.lunchStartMinutes;
    _lunchEnd = cfg.lunchEndMinutes;
    _slotDuration =
        _durationOptions.contains(cfg.slotDurationMinutes) ? cfg.slotDurationMinutes : 60;
    _breakDuration =
        _breakOptions.contains(cfg.breakDurationMinutes) ? cfg.breakDurationMinutes : 0;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _serviceInput.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  int _int(String key, int fallback) =>
      int.tryParse(_ctrl(key).text.trim()) ?? fallback;

  List<ConsultationSlot> _currentSlots() => generateSlotsWithBreak(
        startMinutes: _slotStart,
        endMinutes: _slotEnd,
        slotDuration: _slotDuration,
        breakDuration: _breakDuration,
        lunchStart: _lunchStart,
        lunchEnd: _lunchEnd,
      );

  // ── Uploads ───────────────────────────────────────────────────────────────
  Future<void> _changePhoto() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final url = await _uploadAstrologyMedia(ref, File(picked.path),
          isImage: true);
      if (!mounted) return;
      setState(() => _photoUrl = url);
      _snack('Photo uploaded. Tap "Save All Settings" to apply.');
    } catch (e) {
      debugPrint('[AstrologyManagement] photo upload failed: $e');
      _snack('Photo upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

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

  Future<void> _pickTime(int initialMinutes, ValueChanged<int> onPicked) async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: initialMinutes ~/ 60, minute: initialMinutes % 60),
    );
    if (picked != null) onPicked(picked.hour * 60 + picked.minute);
  }

  // ── Save ────────────────────────────────────────────────────────────────
  Future<void> _save(AstrologyServiceConfig base) async {
    if (_ctrl('expertName').text.trim().isEmpty) {
      _snack('Astrologer name is required.');
      return;
    }
    setState(() => _saving = true);
    final updated = base.copyWith(
      expertName: _ctrl('expertName').text.trim(),
      expertPhotoUrl: _photoUrl,
      expertExperience: _ctrl('expertExperience').text.trim(),
      expertSpecialization: _ctrl('expertSpecialization').text.trim(),
      expertIntro: _ctrl('expertIntro').text.trim(),
      services: List<String>.from(_services),
      certificates: List<AstrologyCertificate>.from(_certificates),
      awards: List<AstrologyAward>.from(_awards),
      news: List<AstrologyNews>.from(_news),
      officeContactNumber: _ctrl('officeContactNumber').text.trim(),
      whatsappNumber: _ctrl('whatsappNumber').text.trim(),
      email: _ctrl('email').text.trim(),
      officeAddress: _ctrl('officeAddress').text.trim(),
      mapLocation: _ctrl('mapLocation').text.trim(),
      appointmentRules: _ctrl('appointmentRules').text.trim(),
      serviceIntro: _ctrl('serviceIntro').text.trim(),
      reportIncludes: _lines('reportIncludes'),
      deliveryTime: _ctrl('deliveryTime').text.trim(),
      serviceCharge: _int('serviceCharge', base.serviceCharge),
      maxAdvanceWorkingDays:
          _int('maxAdvanceWorkingDays', base.maxAdvanceWorkingDays),
      bookingEnabled: _bookingEnabled,
      workingWeekdays: (_workingWeekdays.toList()..sort()),
      holidayDates: List<String>.from(_holidayDates),
      disabledSlotMinutes: (_disabledSlots.toList()..sort()),
      slotStartMinutes: _slotStart,
      slotEndMinutes: _slotEnd,
      lunchStartMinutes: _lunchStart,
      lunchEndMinutes: _lunchEnd,
      slotDurationMinutes: _slotDuration,
      breakDurationMinutes: _breakDuration,
    );
    try {
      await ref.read(astrologyConfigServiceProvider).save(updated);
      if (mounted) _snack('✅ Astrology settings saved.');
    } catch (e, st) {
      debugPrint('[AstrologyManagement] save failed: $e\n$st');
      final msg = e.toString().toLowerCase();
      if (msg.contains('permission-denied') || msg.contains('permission_denied')) {
        _snack('Save blocked by security rules. Deploy Firestore rules '
            '(firebase deploy --only firestore:rules) and try again.');
      } else {
        _snack('Could not save: $e');
      }
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Astrologer profile ─────────────────────────────────────────────
        _card('Astrologer Profile', Icons.person_outline, [
          Center(child: _photoPicker()),
          const SizedBox(height: 14),
          _field('expertName', 'Astrologer name *'),
          _field('expertExperience', 'Experience (e.g. 15+ years)'),
          _field('expertSpecialization', 'Specialization'),
          _field('expertIntro', 'About description', maxLines: 4),
        ]),

        // ── Services ───────────────────────────────────────────────────────
        _card('Services', Icons.auto_awesome_outlined, [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _serviceInput,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addService(),
                  decoration: _inputDecoration('Type a service'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addService,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(64, 52),
                ),
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_services.isEmpty)
            _emptyHint('No services yet. Type one and tap Add.')
          else
            for (int i = 0; i < _services.length; i++) _serviceRow(i),
        ]),

        // ── Certificates ───────────────────────────────────────────────────
        _card('Certificates', Icons.verified_outlined, [
          for (int i = 0; i < _certificates.length; i++) _certificateRow(i),
          if (_certificates.isEmpty)
            _emptyHint('No certificates uploaded yet.'),
          const SizedBox(height: 8),
          _addButton('Add Certificate', _addCertificate),
        ]),

        // ── Awards ─────────────────────────────────────────────────────────
        _card('Awards / Medals', Icons.emoji_events_outlined, [
          for (int i = 0; i < _awards.length; i++) _awardRow(i),
          if (_awards.isEmpty) _emptyHint('No awards added yet.'),
          const SizedBox(height: 8),
          _addButton('Add Award', _addAward),
        ]),

        // ── News & Media ───────────────────────────────────────────────────
        _card('News & Media', Icons.newspaper_outlined, [
          for (int i = 0; i < _news.length; i++) _newsRow(i),
          if (_news.isEmpty) _emptyHint('No news items added yet.'),
          const SizedBox(height: 8),
          _addButton('Add News', _addNews),
        ]),

        // ── Contact details ────────────────────────────────────────────────
        _card('Contact Details', Icons.contact_phone_outlined, [
          _field('officeContactNumber', 'Phone'),
          _field('whatsappNumber', 'WhatsApp'),
          _field('email', 'Email'),
          _field('officeAddress', 'Office address', maxLines: 2),
          _field('mapLocation', 'Location (Google Maps link or area)'),
        ]),

        // ── Appointment settings ───────────────────────────────────────────
        _card('Appointment Settings', Icons.event_available_outlined, [
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
          const SizedBox(height: 8),
          _subLabel('Working Days'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(7, (i) {
              final weekday = i + 1;
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
          const SizedBox(height: 14),
          _subLabel('Working Hours'),
          Row(
            children: [
              Expanded(
                  child: _timeTile('Start', _slotStart,
                      (m) => setState(() => _slotStart = m))),
              const SizedBox(width: 10),
              Expanded(
                  child: _timeTile(
                      'End', _slotEnd, (m) => setState(() => _slotEnd = m))),
            ],
          ),
          const SizedBox(height: 10),
          _subLabel('Break Window (lunch — slots overlapping are skipped)'),
          Row(
            children: [
              Expanded(
                  child: _timeTile('Break start', _lunchStart,
                      (m) => setState(() => _lunchStart = m))),
              const SizedBox(width: 10),
              Expanded(
                  child: _timeTile('Break end', _lunchEnd,
                      (m) => setState(() => _lunchEnd = m))),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _dropdown<int>(
                  label: 'Slot Duration',
                  value: _slotDuration,
                  items: _durationOptions,
                  display: (v) => '$v min',
                  onChanged: (v) => setState(() => _slotDuration = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dropdown<int>(
                  label: 'Break Between Slots',
                  value: _breakDuration,
                  items: _breakOptions,
                  display: (v) => v == 0 ? 'None' : '$v min',
                  onChanged: (v) => setState(() => _breakDuration = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _field('maxAdvanceWorkingDays',
              'Report booking — working days ahead',
              number: true),
          const SizedBox(height: 6),
          _slotPreview(),
        ]),

        // ── Manual block / holiday dates ───────────────────────────────────
        _card('Holiday / Unavailable Dates', Icons.event_busy_outlined, [
          _emptyHint('Marked dates disappear automatically from user booking.'),
          const SizedBox(height: 8),
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
                avatar:
                    const Icon(Icons.add, size: 18, color: AppColors.primary),
                label: const Text('Block a date'),
                onPressed: _addHoliday,
              ),
            ],
          ),
        ]),

        // ── Available time slots (enable/disable individual) ───────────────
        _card('Available Time Slots', Icons.schedule_outlined, [
          _emptyHint('Tap to enable/disable a slot. Disabled slots are hidden '
              'from users.'),
          const SizedBox(height: 8),
          _slotToggles(),
        ]),

        // ── Horoscope report copy (existing service) ───────────────────────
        _card('Horoscope Report Service', Icons.description_outlined, [
          _field('serviceIntro', 'Service introduction', maxLines: 3),
          _field('reportIncludes', 'What the report includes (one per line)',
              maxLines: 5),
          _field('deliveryTime', 'Estimated delivery time'),
          _field('serviceCharge', 'Report service charge (₹)', number: true),
        ]),

        // ── Appointment rules ──────────────────────────────────────────────
        _card('Appointment Rules', Icons.rule_outlined, [
          _field('appointmentRules', 'Rules / instructions shown to users',
              maxLines: 3),
        ]),

        const SizedBox(height: 8),
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
            label: Text(_saving ? 'Saving…' : 'Save All Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
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

  // ── Photo picker ──────────────────────────────────────────────────────────
  Widget _photoPicker() => Column(
        children: [
          Stack(
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
                child: ClipOval(
                  child: NetworkPhoto(
                      url: _photoUrl, width: 110, height: 110),
                ),
              ),
              if (_uploadingPhoto)
                const Positioned.fill(
                  child: CircleAvatar(
                    backgroundColor: Colors.black38,
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _uploadingPhoto ? null : _changePhoto,
            icon: const Icon(Icons.upload_outlined, size: 18),
            label: Text(_photoUrl.isEmpty ? 'Upload Photo' : 'Change Photo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
            ),
          ),
        ],
      );

  // ── Services rows ───────────────────────────────────────────────────────
  void _addService() {
    final t = _serviceInput.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _services.add(t);
      _serviceInput.clear();
    });
  }

  Widget _serviceRow(int i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator, size: 18, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(child: Text(_services[i], style: const TextStyle(fontSize: 13.5))),
            _iconBtn(Icons.arrow_upward, i == 0 ? null : () => _move(_services, i, -1)),
            _iconBtn(Icons.arrow_downward,
                i == _services.length - 1 ? null : () => _move(_services, i, 1)),
            _iconBtn(Icons.edit_outlined, () => _editService(i)),
            _iconBtn(Icons.delete_outline, () => setState(() => _services.removeAt(i)),
                color: AppColors.error),
          ],
        ),
      );

  void _move<T>(List<T> list, int i, int dir) {
    final j = i + dir;
    if (j < 0 || j >= list.length) return;
    setState(() {
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    });
  }

  Future<void> _editService(int i) async {
    final ctrl = TextEditingController(text: _services[i]);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Service'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _services[i] = result);
    }
  }

  // ── Certificates ──────────────────────────────────────────────────────────
  Widget _certificateRow(int i) {
    final c = _certificates[i];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: c.isPdf
          ? const Icon(Icons.picture_as_pdf, color: AppColors.error, size: 34)
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child:
                  NetworkPhoto(url: c.url, width: 44, height: 44),
            ),
      title: Text(c.title, style: const TextStyle(fontSize: 13.5)),
      subtitle: Text(c.isPdf ? 'PDF' : 'Image',
          style: const TextStyle(fontSize: 11)),
      trailing: _iconBtn(Icons.delete_outline,
          () => setState(() => _certificates.removeAt(i)),
          color: AppColors.error),
    );
  }

  Future<void> _addCertificate() async {
    final item = await showModalBottomSheet<AstrologyCertificate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => const _CertificateEditorSheet(),
    );
    if (item != null) setState(() => _certificates.add(item));
  }

  // ── Awards ────────────────────────────────────────────────────────────────
  Widget _awardRow(int i) {
    final a = _awards[i];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: NetworkPhoto(
            url: a.imageUrl,
            width: 44,
            height: 44,
            fallbackIcon: Icons.emoji_events),
      ),
      title: Text(a.title, style: const TextStyle(fontSize: 13.5)),
      subtitle: Text([a.year, a.description].where((s) => s.isNotEmpty).join(' · '),
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _iconBtn(Icons.edit_outlined, () => _addAward(edit: i)),
        _iconBtn(Icons.delete_outline,
            () => setState(() => _awards.removeAt(i)),
            color: AppColors.error),
      ]),
    );
  }

  Future<void> _addAward({int? edit}) async {
    final item = await showModalBottomSheet<AstrologyAward>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _AwardEditorSheet(initial: edit == null ? null : _awards[edit]),
    );
    if (item == null) return;
    setState(() {
      if (edit == null) {
        _awards.add(item);
      } else {
        _awards[edit] = item;
      }
    });
  }

  // ── News ──────────────────────────────────────────────────────────────────
  Widget _newsRow(int i) {
    final n = _news[i];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: NetworkPhoto(
            url: n.imageUrl,
            width: 44,
            height: 44,
            fallbackIcon: Icons.newspaper),
      ),
      title: Text(n.headline,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5)),
      subtitle: Text([n.source, n.date].where((s) => s.isNotEmpty).join(' · '),
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _iconBtn(Icons.edit_outlined, () => _addNews(edit: i)),
        _iconBtn(Icons.delete_outline, () => setState(() => _news.removeAt(i)),
            color: AppColors.error),
      ]),
    );
  }

  Future<void> _addNews({int? edit}) async {
    final item = await showModalBottomSheet<AstrologyNews>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _NewsEditorSheet(initial: edit == null ? null : _news[edit]),
    );
    if (item == null) return;
    setState(() {
      if (edit == null) {
        _news.add(item);
      } else {
        _news[edit] = item;
      }
    });
  }

  // ── Slots ─────────────────────────────────────────────────────────────────
  Widget _slotPreview() {
    final slots = _currentSlots();
    return Text(
      'Generates ${slots.length} slot(s): '
      '${slots.isEmpty ? '—' : slots.take(6).map((s) => s.label).join(', ')}'
      '${slots.length > 6 ? ' …' : ''}',
      style: const TextStyle(
          fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.primary),
    );
  }

  Widget _slotToggles() {
    final slots = _currentSlots();
    if (slots.isEmpty) {
      return _emptyHint('No slots — set working hours and duration above.');
    }
    return Wrap(
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
    );
  }

  // ── Reusable bits ───────────────────────────────────────────────────────
  Widget _card(String title, IconData icon, List<Widget> children) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ]),
            const Divider(height: 18),
            ...children,
          ],
        ),
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
        decoration: _inputDecoration(label),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.scaffoldBg,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _subLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
      );

  Widget _emptyHint(String t) => Text(t,
      style: const TextStyle(fontSize: 12, color: Colors.grey));

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {Color? color}) =>
      IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        color: color ?? Colors.grey[700],
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(),
      );

  Widget _addButton(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.add, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            minimumSize: const Size.fromHeight(46),
          ),
        ),
      );

  Widget _timeTile(String label, int minutes, ValueChanged<int> onPicked) =>
      InkWell(
        onTap: () => _pickTime(minutes, onPicked),
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: _inputDecoration(label),
          child: Text(formatMinutes(minutes),
              style: const TextStyle(fontSize: 14)),
        ),
      );

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) display,
    required ValueChanged<T> onChanged,
  }) =>
      InputDecorator(
        decoration: _inputDecoration(label),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isDense: true,
            isExpanded: true,
            value: value,
            items: [
              for (final it in items)
                DropdownMenuItem(value: it, child: Text(display(it))),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );
}

// ── Certificate editor sheet ──────────────────────────────────────────────────

class _CertificateEditorSheet extends ConsumerStatefulWidget {
  const _CertificateEditorSheet();

  @override
  ConsumerState<_CertificateEditorSheet> createState() =>
      _CertificateEditorSheetState();
}

class _CertificateEditorSheetState
    extends ConsumerState<_CertificateEditorSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  String _url = '';
  String _fileType = 'image';
  bool _busy = false;

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    await _upload(File(picked.path), isImage: true);
  }

  Future<void> _pickPdf() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = res?.files.single.path;
    if (path == null) return;
    await _upload(File(path), isImage: false);
  }

  Future<void> _upload(File file, {required bool isImage}) async {
    setState(() => _busy = true);
    try {
      final url = await _uploadAstrologyMedia(ref, file, isImage: isImage);
      setState(() {
        _url = url;
        _fileType = isImage ? 'image' : 'pdf';
      });
    } catch (_) {
      _snack('Upload failed — try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Add Certificate',
      busy: _busy,
      canSave: _url.isNotEmpty,
      onSave: () => Navigator.pop(
        context,
        AstrologyCertificate(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: _title.text.trim().isEmpty ? 'Certificate' : _title.text.trim(),
          description: _desc.text.trim(),
          url: _url,
          fileType: _fileType,
        ),
      ),
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(
              labelText: 'Title (optional)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _desc,
          maxLines: 2,
          decoration: const InputDecoration(
              labelText: 'Description (optional)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        if (_url.isNotEmpty)
          Row(children: [
            Icon(_fileType == 'pdf' ? Icons.picture_as_pdf : Icons.image,
                color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    _fileType == 'pdf' ? 'PDF uploaded' : 'Image uploaded',
                    style: const TextStyle(color: AppColors.success))),
          ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pickImage,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Image'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pickPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF'),
            ),
          ),
        ]),
      ],
    );
  }
}

// ── Award editor sheet ────────────────────────────────────────────────────────

class _AwardEditorSheet extends ConsumerStatefulWidget {
  final AstrologyAward? initial;
  const _AwardEditorSheet({this.initial});

  @override
  ConsumerState<_AwardEditorSheet> createState() => _AwardEditorSheetState();
}

class _AwardEditorSheetState extends ConsumerState<_AwardEditorSheet> {
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _desc =
      TextEditingController(text: widget.initial?.description ?? '');
  late final _year = TextEditingController(text: widget.initial?.year ?? '');
  late String _img = widget.initial?.imageUrl ?? '';
  bool _busy = false;

  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final url =
          await _uploadAstrologyMedia(ref, File(picked.path), isImage: true);
      setState(() => _img = url);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Upload failed.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _year.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: widget.initial == null ? 'Add Award' : 'Edit Award',
      busy: _busy,
      canSave: _title.text.trim().isNotEmpty,
      onSave: () => Navigator.pop(
        context,
        AstrologyAward(
          id: widget.initial?.id ??
              DateTime.now().millisecondsSinceEpoch.toString(),
          title: _title.text.trim(),
          description: _desc.text.trim(),
          year: _year.text.trim(),
          imageUrl: _img,
        ),
      ),
      children: [
        _imagePickRow(_img, _busy, _pickImage),
        const SizedBox(height: 12),
        TextField(
            controller: _title,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Title *', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(
            controller: _desc,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Description', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(
            controller: _year,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Year (optional)', border: OutlineInputBorder())),
      ],
    );
  }
}

// ── News editor sheet ─────────────────────────────────────────────────────────

class _NewsEditorSheet extends ConsumerStatefulWidget {
  final AstrologyNews? initial;
  const _NewsEditorSheet({this.initial});

  @override
  ConsumerState<_NewsEditorSheet> createState() => _NewsEditorSheetState();
}

class _NewsEditorSheetState extends ConsumerState<_NewsEditorSheet> {
  late final _headline =
      TextEditingController(text: widget.initial?.headline ?? '');
  late final _desc =
      TextEditingController(text: widget.initial?.description ?? '');
  late final _date = TextEditingController(text: widget.initial?.date ?? '');
  late final _source =
      TextEditingController(text: widget.initial?.source ?? '');
  late String _img = widget.initial?.imageUrl ?? '';
  bool _busy = false;

  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final url =
          await _uploadAstrologyMedia(ref, File(picked.path), isImage: true);
      setState(() => _img = url);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Upload failed.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _headline.dispose();
    _desc.dispose();
    _date.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: widget.initial == null ? 'Add News' : 'Edit News',
      busy: _busy,
      canSave: _headline.text.trim().isNotEmpty,
      onSave: () => Navigator.pop(
        context,
        AstrologyNews(
          id: widget.initial?.id ??
              DateTime.now().millisecondsSinceEpoch.toString(),
          headline: _headline.text.trim(),
          description: _desc.text.trim(),
          date: _date.text.trim(),
          source: _source.text.trim(),
          imageUrl: _img,
        ),
      ),
      children: [
        _imagePickRow(_img, _busy, _pickImage),
        const SizedBox(height: 12),
        TextField(
            controller: _headline,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Headline *', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(
            controller: _desc,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Description', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
                controller: _date,
                decoration: const InputDecoration(
                    labelText: 'Date', border: OutlineInputBorder())),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
                controller: _source,
                decoration: const InputDecoration(
                    labelText: 'Source', border: OutlineInputBorder())),
          ),
        ]),
      ],
    );
  }
}

// ── Shared sheet scaffold + image-pick row ────────────────────────────────────

Widget _imagePickRow(String url, bool busy, VoidCallback onPick) => Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: NetworkPhoto(
              url: url, width: 64, height: 64, fallbackIcon: Icons.image),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : onPick,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_outlined, size: 18),
            label: Text(url.isEmpty ? 'Upload Image' : 'Change Image'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );

class _SheetScaffold extends StatelessWidget {
  final String title;
  final bool busy;
  final bool canSave;
  final VoidCallback onSave;
  final List<Widget> children;
  const _SheetScaffold({
    required this.title,
    required this.busy,
    required this.canSave,
    required this.onSave,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 17,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold)),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (busy || !canSave) ? null : onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                ),
                child: Text(busy ? 'Uploading…' : 'Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
