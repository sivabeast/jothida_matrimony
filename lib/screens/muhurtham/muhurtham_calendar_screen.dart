import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/muhurtham_dates.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/muhurtham_model.dart';
import '../../widgets/common/coming_soon.dart';

/// Marriage Muhurtham Calendar — a month-wise calendar that highlights ONLY
/// the general auspicious marriage dates (good days). Inauspicious days are
/// never shown or marked. Tapping a highlighted date shows its full details
/// (suitable-for, panchang, description) BELOW the calendar on this same page.
///
/// LAUNCH LOCK: not part of the initial release — non-admin users get the
/// shared Coming Soon page instead of the calendar. Admins keep full access.
class MuhurthamCalendarScreen extends ConsumerStatefulWidget {
  const MuhurthamCalendarScreen({super.key});

  @override
  ConsumerState<MuhurthamCalendarScreen> createState() =>
      _MuhurthamCalendarScreenState();
}

class _MuhurthamCalendarScreenState
    extends ConsumerState<MuhurthamCalendarScreen> {
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  late DateTime _visibleMonth; // always day 1 of the shown month
  MuhurthamDate? _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    // Pre-select the first upcoming muhurtham of the current month, so the
    // details panel is never empty when the month has good dates.
    _selected = _datesInMonth(_visibleMonth)
        .where((m) => !m.date.isBefore(DateTime(now.year, now.month, now.day)))
        .firstOrNull ??
        _datesInMonth(_visibleMonth).firstOrNull;
  }

  List<MuhurthamDate> _datesInMonth(DateTime month) => kMuhurthamDates
      .where((m) => m.date.year == month.year && m.date.month == month.month)
      .toList();

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth =
          DateTime(_visibleMonth.year, _visibleMonth.month + delta);
      _selected = _datesInMonth(_visibleMonth).firstOrNull;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(upcomingFeaturesUnlockedProvider)) {
      return ComingSoonPage(
          featureName: context.l10n.featureMuhurthamCalendar);
    }

    final goodDates = _datesInMonth(_visibleMonth);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Marriage Muhurtham Calendar'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMonthHeader(),
          const SizedBox(height: 12),
          _buildCalendarCard(goodDates),
          const SizedBox(height: 10),
          _buildLegend(goodDates.length),
          const SizedBox(height: 16),
          if (_selected != null)
            _MuhurthamDetails(entry: _selected!)
          else
            _noSelectionHint(goodDates.isEmpty),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Month header with Previous / Next ────────────────────────────────────

  Widget _buildMonthHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous Month',
            onPressed: () => _changeMonth(-1),
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          ),
          Expanded(
            child: Text(
              '${_monthNames[_visibleMonth.month - 1]} ${_visibleMonth.year}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Next Month',
            onPressed: () => _changeMonth(1),
            icon:
                const Icon(Icons.chevron_right, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }

  // ── Month grid ────────────────────────────────────────────────────────────

  Widget _buildCalendarCard(List<MuhurthamDate> goodDates) {
    final firstDay = _visibleMonth;
    final daysInMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    // DateTime.weekday: Mon=1..Sun=7 → grid column with Sunday first.
    final leadingBlanks = firstDay.weekday % 7;
    final today = DateTime.now();

    final cells = <Widget>[];
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
      final entry = kMuhurthamByDay[MuhurthamDate.keyFor(date)];
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      cells.add(_DayCell(
        day: day,
        entry: entry,
        isToday: isToday,
        isSelected: _selected != null && _selected!.key == entry?.key,
        onTap: entry == null
            ? null
            : () => setState(() => _selected = entry),
      ));
    }

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

  Widget _buildLegend(int count) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.success,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            count == 0
                ? 'No auspicious marriage dates this month'
                : 'Auspicious marriage dates ($count this month) — tap a '
                    'highlighted date for details',
            style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
          ),
        ),
      ],
    );
  }

  Widget _noSelectionHint(bool emptyMonth) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.event_available_outlined,
              size: 44, color: Colors.grey[350]),
          const SizedBox(height: 10),
          Text(
            emptyMonth
                ? 'This month has no general marriage muhurtham dates.\nUse '
                    'Next Month to find the upcoming auspicious dates.'
                : 'Tap a highlighted date on the calendar to see its details.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

// ── Day cell ──────────────────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  final int day;
  final MuhurthamDate? entry;
  final bool isToday;
  final bool isSelected;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.entry,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final good = entry != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.success
              : good
                  ? AppColors.success.withOpacity(0.16)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: AppColors.success, width: 2)
              : good
                  ? Border.all(color: AppColors.success.withOpacity(0.5))
                  : isToday
                      ? Border.all(color: AppColors.primary.withOpacity(0.5))
                      : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    good || isToday ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : good
                        ? AppColors.success
                        : isToday
                            ? AppColors.primary
                            : Colors.grey[700],
              ),
            ),
            if (good) ...[
              const SizedBox(height: 2),
              Icon(Icons.favorite,
                  size: 8,
                  color: isSelected ? Colors.white : AppColors.success),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Details panel (below the calendar, updates with the selection) ───────────

class _MuhurthamDetails extends StatelessWidget {
  final MuhurthamDate entry;
  const _MuhurthamDetails({required this.entry});

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final d = entry.date;
    final dateLabel =
        '${_weekdayNames[d.weekday - 1]}, ${d.day} ${_monthNames[d.month - 1]} ${d.year}';

    return Container(
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
          // ── Date ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.event_available,
                    color: AppColors.success, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Auspicious Date',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.success)),
                    const SizedBox(height: 2),
                    Text(dateLabel,
                        style: const TextStyle(
                            fontSize: 15,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Suitable For ──
          _sectionTitle('Suitable For'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entry.suitableFor
                .map((s) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.25)),
                      ),
                      child: Text(
                        s == 'Marriage' ? '💍 $s' : '🤝 $s',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),

          // ── Panchang Details ──
          _sectionTitle('Panchang Details'),
          const SizedBox(height: 8),
          _panchangRow('Tithi', entry.tithi),
          _panchangRow('Nakshatra', entry.nakshatra),
          _panchangRow('Yoga', entry.yoga),
          _panchangRow('Karana', entry.karana),
          const SizedBox(height: 16),

          // ── Description ──
          _sectionTitle('Description'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gold.withOpacity(0.3)),
            ),
            child: Text(
              entry.description,
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(title,
      style: const TextStyle(
          fontSize: 13.5,
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          color: AppColors.primary));

  Widget _panchangRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500)),
          ),
          const Text(':  ',
              style: TextStyle(fontSize: 12.5, color: Colors.grey)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
