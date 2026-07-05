import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';

/// DASHBOARD — the workspace's central control center: countdown, next
/// event, today's schedule, pending tasks, budget vs expense, pending
/// approvals, recent uploads, today's reminders, the ⭐ selected highlights
/// and recent activities — everything at a glance, side-visibility applied.
class WeddingDashboardTab extends ConsumerWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  const WeddingDashboardTab(
      {super.key, required this.wedding, required this.identity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = identity;
    final now = DateTime.now();

    final tasks = (ref.watch(weddingChecklistProvider(wedding.id)).valueOrNull ??
            const <WeddingChecklistItem>[])
        .where((t) => me.visibleScopes.contains(t.scope))
        .toList();
    final photos = (ref.watch(weddingGalleryProvider(wedding.id)).valueOrNull ??
            const <WeddingPhoto>[])
        .where((p) => me.visibleScopes.contains(p.scope))
        .toList();
    final events = ref.watch(weddingEventsProvider(wedding.id)).valueOrNull ??
        const <WeddingEvent>[];
    final expenses =
        ref.watch(weddingExpensesProvider(wedding.id)).valueOrNull ??
            const <WeddingExpense>[];
    final activity = (ref
                .watch(weddingActivityProvider(wedding.id))
                .valueOrNull ??
            const <WeddingActivity>[])
        .where((a) => a.scope == 'shared' || me.visibleScopes.contains(a.scope))
        .toList();
    final schedule =
        ref.watch(weddingScheduleProvider(wedding.id)).valueOrNull ??
            const <WeddingScheduleItem>[];

    final pendingTasks = tasks.where((t) => !t.isCompleted).length;
    final pendingApprovals =
        photos.where((p) => p.voteOf(me.key) == null).length;
    final spent = expenses.fold<num>(0, (sum, e) => sum + e.amount);
    final nextEvent = events
        .where((e) => !e.dateTime.isBefore(now))
        .toList()
        .firstOrNull;
    final todaysEvents = events
        .where((e) =>
            e.dateTime.year == now.year &&
            e.dateTime.month == now.month &&
            e.dateTime.day == now.day)
        .toList();
    final dueReminders =
        events.where((e) => e.reminderDue(now)).toList();
    final recentUploads = photos.take(10).toList();
    final selectedPhotos = photos.where((p) => p.isSelected).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _countdownCard(),
        const SizedBox(height: 12),

        // ── Stat highlight cards ──
        Row(
          children: [
            Expanded(
              child: _statCard('✅', 'Pending Tasks', '$pendingTasks',
                  pendingTasks == 0 ? AppColors.success : AppColors.warning),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                  '🗳️',
                  'Pending Approvals',
                  '$pendingApprovals',
                  pendingApprovals == 0
                      ? AppColors.success
                      : AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _budgetCard(spent),
        const SizedBox(height: 12),

        // ── Next event + today ──
        if (nextEvent != null) _nextEventCard(nextEvent),
        if (todaysEvents.isNotEmpty)
          _listCard(
            title: "📅 Today's Schedule",
            children: todaysEvents
                .map((e) => _lineItem(
                    _time(e.dateTime),
                    '${e.title}${e.location.isNotEmpty ? ' · ${e.location}' : ''}'))
                .toList(),
          ),
        if (dueReminders.isNotEmpty)
          _listCard(
            title: "🔔 Today's Reminders",
            children: dueReminders
                .map((e) => _lineItem(
                    '${e.dateTime.day}/${e.dateTime.month}',
                    '${e.title} (${e.type})'))
                .toList(),
          ),

        // ── ⭐ Selected highlights ──
        if (selectedPhotos.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 4, 2, 8),
            child: Text('⭐ Selected Highlights',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ),
          SizedBox(
            height: 130,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: selectedPhotos
                  .map((p) => _selectedHighlight(context, p))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Recent uploads ──
        if (recentUploads.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 4, 2, 8),
            child: Text('📸 Recent Gallery Uploads',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ),
          SizedBox(
            height: 84,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: recentUploads
                  .map((p) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () =>
                              showImageGallery(context, [p.url]),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              p.url,
                              width: 84,
                              height: 84,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 84,
                                color: Colors.grey[200],
                                child: const Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.grey,
                                    size: 20),
                              ),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Wedding Day Schedule ──
        _weddingDaySchedule(context, ref, schedule),
        const SizedBox(height: 12),

        // ── Recent activities ──
        _listCard(
          title: '🕘 Recent Activities',
          children: activity.isEmpty
              ? [
                  Text('No activity yet.',
                      style:
                          TextStyle(color: Colors.grey[500], fontSize: 12))
                ]
              : activity
                  .take(6)
                  .map((a) => _lineItem(
                      '${a.at.day}/${a.at.month}', a.text))
                  .toList(),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _time(DateTime dt) {
    final h12 = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    return '$h12:${dt.minute.toString().padLeft(2, '0')} '
        '${dt.hour >= 12 ? 'PM' : 'AM'}';
  }

  // ── Cards ─────────────────────────────────────────────────────────────────

  Widget _countdownCard() {
    final date = wedding.weddingDate;
    final remaining = wedding.daysRemaining;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            wedding.isPostponed
                ? '⏳ Wedding Postponed'
                : wedding.isCompleted
                    ? '🎉 Happily Married'
                    : '💍 Wedding Countdown',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (date == null)
            Text(
              wedding.isPostponed
                  ? 'The new wedding date has not been decided yet.'
                  : 'The wedding date has not been set yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.9), fontSize: 12.5),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _whiteStat('Wedding Date',
                      '${date.day}/${date.month}/${date.year}'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _whiteStat(
                    'Remaining Days',
                    remaining == null
                        ? '—'
                        : remaining > 0
                            ? '$remaining'
                            : remaining == 0
                                ? 'Today! 🎊'
                                : 'Done 🎉',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _whiteStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.85), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _statCard(String emoji, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  color: color)),
          Text(label,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _budgetCard(num spent) {
    final budget = wedding.totalBudget;
    final remaining = budget - spent;
    final ratio = budget <= 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💰 Budget vs Expense',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5)),
          const SizedBox(height: 10),
          if (budget <= 0)
            Text('No budget set yet — set it in the Expense Tracker.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12))
          else ...[
            Row(
              children: [
                Expanded(
                    child: Text('Spent ₹$spent of ₹$budget',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600))),
                Text(
                  remaining >= 0
                      ? '₹$remaining left'
                      : '₹${-remaining} over!',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: remaining >= 0
                          ? AppColors.success
                          : AppColors.error),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 9,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                    ratio < 0.85 ? AppColors.success : AppColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _nextEventCard(WeddingEvent event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Text('📌', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Next Event',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                Text(event.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                Text(
                    '${event.dateTime.day}/${event.dateTime.month}/${event.dateTime.year} '
                    '· ${_time(event.dateTime)}'
                    '${event.location.isNotEmpty ? ' · ${event.location}' : ''}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listCard({required String title, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _lineItem(String lead, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(lead,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
          ),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[800])),
          ),
        ],
      ),
    );
  }

  Widget _selectedHighlight(BuildContext context, WeddingPhoto photo) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () => showImageGallery(context, [photo.url]),
        child: Container(
          width: 150,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gold.withOpacity(0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(11)),
                child: Image.network(
                  photo.url,
                  width: 150,
                  height: 88,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 88,
                    color: Colors.grey[200],
                    child: const Icon(Icons.broken_image_outlined,
                        color: Colors.grey, size: 20),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
                child: Text('⭐ ${photo.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.goldDark)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Wedding Day Schedule (couple-managed) ─────────────────────────────────

  Widget _weddingDaySchedule(BuildContext context, WidgetRef ref,
      List<WeddingScheduleItem> schedule) {
    final isWeddingToday = wedding.daysRemaining == 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isWeddingToday
            ? Border.all(color: AppColors.gold, width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    isWeddingToday
                        ? "💒 Today's Wedding Schedule"
                        : '💒 Wedding Day Schedule',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5)),
              ),
              if (identity.isSuperAdmin)
                TextButton.icon(
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                  onPressed: () => _showScheduleSheet(context, ref),
                ),
            ],
          ),
          if (schedule.isEmpty)
            Text(
              identity.isSuperAdmin
                  ? 'Plan the wedding-day timeline — makeup, muhurtham, '
                      'photography, meals, reception…'
                  : 'The wedding-day timeline has not been planned yet.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            )
          else
            ...schedule.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(s.timeLabel,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.event,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            if (s.location.isNotEmpty ||
                                s.person.isNotEmpty ||
                                s.notes.isNotEmpty)
                              Text(
                                [
                                  if (s.location.isNotEmpty) s.location,
                                  if (s.person.isNotEmpty) s.person,
                                  if (s.notes.isNotEmpty) s.notes,
                                ].join(' · '),
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[600]),
                              ),
                          ],
                        ),
                      ),
                      if (identity.isSuperAdmin)
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.more_horiz,
                              size: 17, color: Colors.grey[500]),
                          onSelected: (v) {
                            if (v == 'edit') {
                              _showScheduleSheet(context, ref, existing: s);
                            } else {
                              ref
                                  .read(weddingControllerProvider.notifier)
                                  .deleteScheduleItem(wedding.id, s.id);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Delete')),
                          ],
                        ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  void _showScheduleSheet(BuildContext context, WidgetRef ref,
      {WeddingScheduleItem? existing}) {
    final eventCtrl = TextEditingController(text: existing?.event ?? '');
    final locationCtrl =
        TextEditingController(text: existing?.location ?? '');
    final personCtrl = TextEditingController(text: existing?.person ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    TimeOfDay time = existing != null
        ? TimeOfDay(
            hour: existing.minutes ~/ 60, minute: existing.minutes % 60)
        : const TimeOfDay(hour: 6, minute: 0);
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    existing == null
                        ? 'Add Schedule Item'
                        : 'Edit Schedule Item',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 16),
                Row(
                  children: [
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
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: eventCtrl,
                        decoration: _input('Event (e.g. Muhurtham)'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter the event'
                            : null,
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
                    controller: personCtrl,
                    decoration: _input('Responsible Person (optional)')),
                const SizedBox(height: 12),
                TextFormField(
                    controller: notesCtrl,
                    decoration: _input('Notes (optional)')),
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
                          .saveScheduleItem(
                            wedding.id,
                            itemId: existing?.id,
                            minutes: time.hour * 60 + time.minute,
                            event: eventCtrl.text.trim(),
                            location: locationCtrl.text.trim(),
                            person: personCtrl.text.trim(),
                            notes: notesCtrl.text.trim(),
                          );
                      navigator.pop();
                    },
                    child: Text(existing == null ? 'Add' : 'Save'),
                  ),
                ),
              ],
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
