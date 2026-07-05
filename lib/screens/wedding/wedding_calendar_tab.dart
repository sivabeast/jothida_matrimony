import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';

/// CALENDAR — the wedding planning calendar (engagement, hall visits,
/// jewellery / dress purchases, invitation printing, reception, the wedding
/// itself) with Calendar and Agenda views and per-event reminders
/// (1 hour / 1 day / 3 days / 1 week before) surfaced as in-app reminders.
class WeddingCalendarTab extends ConsumerStatefulWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  const WeddingCalendarTab(
      {super.key, required this.wedding, required this.identity});

  @override
  ConsumerState<WeddingCalendarTab> createState() =>
      _WeddingCalendarTabState();
}

class _WeddingCalendarTabState extends ConsumerState<WeddingCalendarTab> {
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  bool _agendaView = false;
  late DateTime _visibleMonth;
  DateTime? _selectedDay;

  WeddingModel get wedding => widget.wedding;
  WeddingIdentity get me => widget.identity;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(weddingEventsProvider(wedding.id));
    final events = eventsAsync.valueOrNull ?? const <WeddingEvent>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'wedding_calendar_fab',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.event_outlined),
        label: const Text('Add Event'),
        onPressed: () => _showEventSheet(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          _viewSwitcher(),
          const SizedBox(height: 12),
          if (_agendaView)
            ..._agenda(events)
          else ...[
            _monthHeader(),
            const SizedBox(height: 10),
            _monthGrid(events),
            const SizedBox(height: 14),
            ..._dayEvents(events),
          ],
        ],
      ),
    );
  }

  // ── Calendar / Agenda switcher ────────────────────────────────────────────

  Widget _viewSwitcher() {
    Widget chip(bool agenda, String label, IconData icon) {
      final active = _agendaView == agenda;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _agendaView = agenda),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: active ? AppColors.primary : Colors.grey.shade300),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 16,
                    color: active ? Colors.white : Colors.grey[600]),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : Colors.grey[700])),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(false, 'Calendar', Icons.calendar_month_outlined),
        const SizedBox(width: 10),
        chip(true, 'Agenda', Icons.view_agenda_outlined),
      ],
    );
  }

  // ── Month view ────────────────────────────────────────────────────────────

  Widget _monthHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous Month',
            onPressed: () => setState(() => _visibleMonth =
                DateTime(_visibleMonth.year, _visibleMonth.month - 1)),
            icon: const Icon(Icons.chevron_left, color: Colors.white),
          ),
          Expanded(
            child: Text(
              '${_monthNames[_visibleMonth.month - 1]} ${_visibleMonth.year}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Next Month',
            onPressed: () => setState(() => _visibleMonth =
                DateTime(_visibleMonth.year, _visibleMonth.month + 1)),
            icon: const Icon(Icons.chevron_right, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _monthGrid(List<WeddingEvent> events) {
    final daysInMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final leadingBlanks = _visibleMonth.weekday % 7;
    final today = DateTime.now();

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        Builder(builder: (_) {
          final date =
              DateTime(_visibleMonth.year, _visibleMonth.month, day);
          final dayEvents =
              events.where((e) => sameDay(e.dateTime, date)).toList();
          final isToday = sameDay(date, today);
          final isSelected =
              _selectedDay != null && sameDay(date, _selectedDay!);
          final isWeddingDay = wedding.weddingDate != null &&
              sameDay(date, wedding.weddingDate!);
          return InkWell(
            onTap: () => setState(() => _selectedDay = date),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : isWeddingDay
                        ? AppColors.gold.withOpacity(0.25)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isToday && !isSelected
                    ? Border.all(color: AppColors.primary.withOpacity(0.5))
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$day',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: dayEvents.isNotEmpty || isToday
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : isWeddingDay
                                ? AppColors.goldDark
                                : Colors.grey[700],
                      )),
                  if (dayEvents.isNotEmpty || isWeddingDay) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isWeddingDay)
                          const Text('💍', style: TextStyle(fontSize: 7)),
                        for (var i = 0;
                            i < (dayEvents.length > 3 ? 3 : dayEvents.length);
                            i++)
                          Container(
                            width: 5,
                            height: 5,
                            margin:
                                const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: _weekdays
                .map((w) => Expanded(
                      child: Center(
                        child: Text(w,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[500])),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: cells,
          ),
        ],
      ),
    );
  }

  List<Widget> _dayEvents(List<WeddingEvent> events) {
    final day = _selectedDay;
    if (day == null) return const [];
    final dayEvents = events
        .where((e) =>
            e.dateTime.year == day.year &&
            e.dateTime.month == day.month &&
            e.dateTime.day == day.day)
        .toList();
    return [
      Text(
        'Events on ${day.day}/${day.month}/${day.year}',
        style: const TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 14),
      ),
      const SizedBox(height: 8),
      if (dayEvents.isEmpty)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text('No events on this day — tap "Add Event" to plan one.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12.5)),
        )
      else
        ...dayEvents.map(_eventCard),
    ];
  }

  // ── Agenda view ───────────────────────────────────────────────────────────

  List<Widget> _agenda(List<WeddingEvent> events) {
    final now = DateTime.now();
    final upcoming =
        events.where((e) => !e.dateTime.isBefore(now)).toList();
    final past = events.where((e) => e.dateTime.isBefore(now)).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    return [
      if (events.isEmpty)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(Icons.event_note_outlined,
                  size: 46, color: Colors.grey[350]),
              const SizedBox(height: 10),
              Text(
                'No events yet — plan hall visits, purchases, the engagement '
                'and the wedding here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
              ),
            ],
          ),
        ),
      if (upcoming.isNotEmpty) ...[
        const Text('Upcoming',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        const SizedBox(height: 8),
        ...upcoming.map(_eventCard),
      ],
      if (past.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('Past',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.grey[500])),
        const SizedBox(height: 8),
        ...past.map(_eventCard),
      ],
    ];
  }

  // ── Event card ────────────────────────────────────────────────────────────

  Widget _eventCard(WeddingEvent event) {
    final dt = event.dateTime;
    final h12 = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final time =
        '$h12:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
    final reminderDue = event.reminderDue(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: reminderDue
            ? Border.all(color: AppColors.warning.withOpacity(0.6))
            : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text('${dt.day}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
                Text(_monthNames[dt.month - 1].substring(0, 3),
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.primary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                    '${event.type} · $time'
                    '${event.location.isNotEmpty ? ' · ${event.location}' : ''}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                if (event.notes.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(event.notes,
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 11.5)),
                ],
                if (event.reminders.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    children: [
                      for (final r in event.reminders)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (reminderDue
                                    ? AppColors.warning
                                    : Colors.blueGrey)
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('🔔 ${WeddingEvent.reminderLabel(r)}',
                              style: TextStyle(
                                  fontSize: 9.5,
                                  color: reminderDue
                                      ? AppColors.warning
                                      : Colors.blueGrey)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (me.isSuperAdmin)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[500]),
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _showEventSheet(existing: event);
                  case 'delete':
                    _confirmDelete(event);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(WeddingEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text('"${event.title}" will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(weddingControllerProvider.notifier)
        .deleteEvent(wedding.id, event.id);
  }

  // ── Add / edit event ──────────────────────────────────────────────────────

  void _showEventSheet({WeddingEvent? existing}) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final locationCtrl =
        TextEditingController(text: existing?.location ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String type = existing?.type ?? WeddingEvent.types.first;
    DateTime date = existing?.dateTime ??
        _selectedDay ??
        DateTime.now().add(const Duration(days: 1));
    TimeOfDay time = existing != null
        ? TimeOfDay.fromDateTime(existing.dateTime)
        : const TimeOfDay(hour: 10, minute: 0);
    final reminders = Set<String>.of(existing?.reminders ?? const []);
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(existing == null ? 'Add Event' : 'Edit Event',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: titleCtrl,
                    decoration: _input('Event Title'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter the event title'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: _input('Event Type'),
                    items: WeddingEvent.types
                        .map((t) =>
                            DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setSheetState(() => type = v ?? type),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: date,
                              firstDate: DateTime(now.year - 1),
                              lastDate: DateTime(now.year + 3),
                            );
                            if (picked != null) {
                              setSheetState(() => date = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: _input('Date'),
                            child: Text(
                                '${date.day}/${date.month}/${date.year}',
                                style: const TextStyle(fontSize: 13.5)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showTimePicker(
                                context: ctx, initialTime: time);
                            if (picked != null) {
                              setSheetState(() => time = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: _input('Time'),
                            child: Text(time.format(ctx),
                                style: const TextStyle(fontSize: 13.5)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: locationCtrl,
                      decoration: _input('Location (optional)')),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: _input('Notes (optional)')),
                  const SizedBox(height: 14),
                  const Text('Reminders',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in WeddingEvent.reminderOptions.keys)
                        FilterChip(
                          label: Text(WeddingEvent.reminderLabel(r),
                              style: const TextStyle(fontSize: 11.5)),
                          selected: reminders.contains(r),
                          selectedColor:
                              AppColors.primary.withOpacity(0.15),
                          checkmarkColor: AppColors.primary,
                          onSelected: (v) => setSheetState(() =>
                              v ? reminders.add(r) : reminders.remove(r)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final navigator = Navigator.of(ctx);
                        await ref
                            .read(weddingControllerProvider.notifier)
                            .saveEvent(
                              wedding.id,
                              eventId: existing?.id,
                              title: titleCtrl.text.trim(),
                              type: type,
                              dateTime: DateTime(date.year, date.month,
                                  date.day, time.hour, time.minute),
                              location: locationCtrl.text.trim(),
                              notes: notesCtrl.text.trim(),
                              reminders: reminders.toList(),
                              me: me,
                            );
                        navigator.pop();
                      },
                      child: Text(
                          existing == null ? 'Add Event' : 'Save Event'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static InputDecoration _input(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}
