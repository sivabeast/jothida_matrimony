import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_section_pages.dart';

String _dateTimeLabel(DateTime at) {
  final h12 = at.hour > 12 ? at.hour - 12 : (at.hour == 0 ? 12 : at.hour);
  return '${at.day}/${at.month}/${at.year} · '
      '$h12:${at.minute.toString().padLeft(2, '0')} '
      '${at.hour >= 12 ? 'PM' : 'AM'}';
}

String _activityEmoji(String type) => switch (type) {
      'gallery' => '📸',
      'task' => '✅',
      'vendor' => '🏪',
      'expense' => '💸',
      'approval' => '🗳️',
      'calendar' => '📅',
      'note' => '📝',
      'shared' => '🔁',
      'selection' => '⭐',
      _ => '📌',
    };

/// ACTIVITY LOG — everything that happened in the workspace, chronologically
/// (side-private activity is hidden from the opposite side).
class WeddingActivityLogPage extends StatelessWidget {
  const WeddingActivityLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: 'Activity Log',
      builder: (context, ref, wedding, identity) {
        final activity = (ref
                    .watch(weddingActivityProvider(wedding.id))
                    .valueOrNull ??
                const <WeddingActivity>[])
            .where((a) =>
                a.scope == 'shared' ||
                identity.visibleScopes.contains(a.scope))
            .toList();
        if (activity.isEmpty) {
          return Center(
            child: Text('No activity yet.',
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: activity.length,
          itemBuilder: (_, i) {
            final a = activity[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_activityEmoji(a.type),
                      style: const TextStyle(fontSize: 17)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.text,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(_dateTimeLabel(a.at),
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 10.5)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// DECISION HISTORY — every finalized change ("ABC Mahal → XYZ Mahal") with
/// who changed it, when, and why.
class WeddingDecisionHistoryPage extends StatelessWidget {
  const WeddingDecisionHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: 'Decision History',
      builder: (context, ref, wedding, identity) {
        final decisions =
            ref.watch(weddingDecisionsProvider(wedding.id)).valueOrNull ??
                const <WeddingDecision>[];
        if (decisions.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No decisions recorded yet. Selecting a ⭐ gallery item or a '
                'final vendor automatically records the change here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: decisions.length,
          itemBuilder: (_, i) {
            final d = decisions[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04), blurRadius: 8),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.field,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: AppColors.primary)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            d.oldValue.isEmpty ? '—' : d.oldValue,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey[600],
                                decoration: TextDecoration.lineThrough),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward,
                            size: 17, color: AppColors.primary),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    AppColors.success.withOpacity(0.3)),
                          ),
                          child: Text(
                            d.newValue,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.success),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Changed by ${d.changedBy} · ${_dateTimeLabel(d.changedAt)}'
                    '${d.reason.isNotEmpty ? '\nReason: ${d.reason}' : ''}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// NOTIFICATIONS — the workspace's notification feed (uploads, tasks,
/// approvals, moves to Shared, selections, vendor & decision changes),
/// newest first, respecting side visibility.
class WeddingNotificationsPage extends StatelessWidget {
  const WeddingNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: 'Notifications',
      builder: (context, ref, wedding, identity) {
        final events =
            ref.watch(weddingEventsProvider(wedding.id)).valueOrNull ??
                const <WeddingEvent>[];
        final now = DateTime.now();
        final dueReminders =
            events.where((e) => e.reminderDue(now)).toList();
        final feed = (ref
                    .watch(weddingActivityProvider(wedding.id))
                    .valueOrNull ??
                const <WeddingActivity>[])
            .where((a) =>
                a.scope == 'shared' ||
                identity.visibleScopes.contains(a.scope))
            .toList();

        if (dueReminders.isEmpty && feed.isEmpty) {
          return Center(
            child: Text('No notifications yet.',
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Calendar reminders currently due ──
            if (dueReminders.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('🔔 Reminders',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
              ...dueReminders.map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.warning.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Text('🔔', style: TextStyle(fontSize: 17)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${e.title} (${e.type})',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              Text(_dateTimeLabel(e.dateTime),
                                  style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 10),
            ],
            if (feed.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Updates',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
            ...feed.map((a) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_activityEmoji(a.type),
                          style: const TextStyle(fontSize: 17)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.text,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(_dateTimeLabel(a.at),
                                style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 10.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        );
      },
    );
  }
}
