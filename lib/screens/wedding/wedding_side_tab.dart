import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_gallery_page.dart';
import 'wedding_section_pages.dart';

/// BRIDE SIDE / GROOM SIDE — one side's own space: side checklist & tasks,
/// side documents, side contacts and side gallery.
class WeddingSideTab extends ConsumerWidget {
  final String side; // 'bride' | 'groom'
  final WeddingModel wedding;
  final WeddingIdentity identity;

  const WeddingSideTab(
      {super.key,
      required this.side,
      required this.wedding,
      required this.identity});

  bool get isBride => side == 'bride';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checklist =
        ref.watch(weddingChecklistProvider(wedding.id)).valueOrNull ??
            const <WeddingChecklistItem>[];
    final sideTasks = checklist.where((c) => c.scope == side).toList();
    final done = sideTasks.where((c) => c.isCompleted).length;

    final name = wedding.coupleIds
        .where((u) => wedding.sideOf(u) == side)
        .map(wedding.nameOf)
        .join();
    final familyCount = wedding.members.where((m) => m.side == side).length;
    final color = isBride ? AppColors.primary : Colors.blue[700]!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Side header ──
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Text(isBride ? '👰' : '🤵',
                  style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isBride ? 'Bride Side' : 'Groom Side',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: color)),
                    const SizedBox(height: 2),
                    Text(
                      '$name · '
                      '${familyCount == 0 ? 'no family members yet' : '$familyCount family member${familyCount == 1 ? '' : 's'}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: Colors.grey[700], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        _card(
          context,
          emoji: '✅',
          title: '${isBride ? 'Bride' : 'Groom'} Checklist & Tasks',
          subtitle: sideTasks.isEmpty
              ? 'Side-specific wedding tasks'
              : '$done of ${sideTasks.length} tasks completed',
          color: color,
          page: WeddingChecklistPage(scope: side),
        ),
        _card(
          context,
          emoji: '📄',
          title: '${isBride ? 'Bride' : 'Groom'} Documents',
          subtitle: 'This side\'s receipts, bookings & papers',
          color: color,
          page: WeddingDocumentsPage(scope: side),
        ),
        _card(
          context,
          emoji: '📇',
          title: '${isBride ? 'Bride' : 'Groom'} Contacts',
          subtitle: 'This side\'s family contact book',
          color: color,
          page: WeddingContactsPage(sideFilter: side),
        ),
        _card(
          context,
          emoji: '📸',
          title: '${isBride ? 'Bride' : 'Groom'} Gallery',
          subtitle: 'This side\'s photos & references',
          color: color,
          page: WeddingGalleryPage(scope: side),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _card(
    BuildContext context, {
    required String emoji,
    required String title,
    required String subtitle,
    required Color color,
    required Widget page,
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
                      color: color.withOpacity(0.08), shape: BoxShape.circle),
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
                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
