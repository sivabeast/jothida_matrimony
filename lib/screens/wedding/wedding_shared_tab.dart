import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_chat_page.dart';
import 'wedding_gallery_page.dart';
import 'wedding_section_pages.dart';

/// SHARED — the workspace's default page: wedding countdown, then the shared
/// modules (checklist, documents, gallery, family chat, guest list) and the
/// shared information card (couple + family members).
class WeddingSharedTab extends ConsumerWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  const WeddingSharedTab(
      {super.key, required this.wedding, required this.identity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checklist =
        ref.watch(weddingChecklistProvider(wedding.id)).valueOrNull ??
            const <WeddingChecklistItem>[];
    final shared = checklist.where((c) => c.scope == 'shared').toList();
    final done = shared.where((c) => c.isCompleted).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _countdownCard(),
        const SizedBox(height: 14),
        _sectionCard(
          context,
          emoji: '✅',
          title: 'Shared Checklist',
          subtitle: shared.isEmpty
              ? 'Plan the wedding tasks together'
              : '$done of ${shared.length} tasks completed',
          page: const WeddingChecklistPage(scope: 'shared'),
          trailing: shared.isEmpty
              ? null
              : SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    value: shared.isEmpty ? 0 : done / shared.length,
                    strokeWidth: 5,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.success),
                  ),
                ),
        ),
        _sectionCard(
          context,
          emoji: '📄',
          title: 'Shared Documents',
          subtitle: 'Invitation, hall booking, catering & more',
          page: const WeddingDocumentsPage(scope: 'shared'),
        ),
        _sectionCard(
          context,
          emoji: '📸',
          title: 'Shared Gallery',
          subtitle: 'Hall, dress, decoration & jewellery photos',
          page: const WeddingGalleryPage(scope: 'shared'),
        ),
        _sectionCard(
          context,
          emoji: '💬',
          title: 'Family Chat',
          subtitle: 'One group chat for both families',
          page: const WeddingChatPage(),
        ),
        _sectionCard(
          context,
          emoji: '🎉',
          title: 'Guest List',
          subtitle: 'Bride side & groom side guests',
          page: const WeddingGuestsPage(),
        ),
        const SizedBox(height: 4),
        _sharedInfoCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Wedding countdown ─────────────────────────────────────────────────────

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
                  child: _statBox('Wedding Date',
                      '${date.day}/${date.month}/${date.year}'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statBox(
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

  Widget _statBox(String label, String value) {
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

  // ── Module cards ──────────────────────────────────────────────────────────

  Widget _sectionCard(
    BuildContext context, {
    required String emoji,
    required String title,
    required String subtitle,
    required Widget page,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => page)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 11.5)),
                    ],
                  ),
                ),
                trailing ?? Icon(Icons.chevron_right, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared information ────────────────────────────────────────────────────

  Widget _sharedInfoCard() {
    final groom = wedding.coupleIds
        .where((u) => wedding.sideOf(u) == 'groom')
        .map(wedding.nameOf)
        .join();
    final bride = wedding.coupleIds
        .where((u) => wedding.sideOf(u) == 'bride')
        .map(wedding.nameOf)
        .join();
    final brideFamily =
        wedding.members.where((m) => m.side == 'bride').length;
    final groomFamily =
        wedding.members.where((m) => m.side == 'groom').length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Shared Information',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          const SizedBox(height: 10),
          _infoRow('🤵 Groom', groom),
          _infoRow('👰 Bride', bride),
          _infoRow('👥 Bride-side family',
              brideFamily == 0 ? 'None invited yet' : '$brideFamily member${brideFamily == 1 ? '' : 's'}'),
          _infoRow('👥 Groom-side family',
              groomFamily == 0 ? 'None invited yet' : '$groomFamily member${groomFamily == 1 ? '' : 's'}'),
          _infoRow(
              '📌 Status',
              wedding.isCompleted
                  ? 'Completed'
                  : wedding.isPostponed
                      ? 'Postponed'
                      : 'Marriage Fixed'),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
          ),
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
