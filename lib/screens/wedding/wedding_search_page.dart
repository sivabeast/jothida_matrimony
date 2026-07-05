import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_section_pages.dart';

/// GLOBAL SEARCH — searches the whole workspace (side visibility applied)
/// and ALWAYS ranks finalized / ⭐ selected content first: selected photos
/// and selected vendors, then tasks, vendors, expenses, notes, calendar
/// events, decision history and activity logs.
class WeddingSearchPage extends StatelessWidget {
  const WeddingSearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: 'Search',
      builder: (_, __, wedding, identity) =>
          _SearchBody(wedding: wedding, identity: identity),
    );
  }
}

class _SearchBody extends ConsumerStatefulWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  const _SearchBody({required this.wedding, required this.identity});

  @override
  ConsumerState<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends ConsumerState<_SearchBody> {
  final _queryCtrl = TextEditingController();
  String _query = '';

  WeddingModel get wedding => widget.wedding;
  WeddingIdentity get me => widget.identity;

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  bool _match(String q, List<String?> fields) =>
      fields.any((f) => f != null && f.toLowerCase().contains(q));

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();

    final photos = (ref.watch(weddingGalleryProvider(wedding.id)).valueOrNull ??
            const <WeddingPhoto>[])
        .where((p) => me.visibleScopes.contains(p.scope))
        .toList();
    final tasks = (ref.watch(weddingChecklistProvider(wedding.id)).valueOrNull ??
            const <WeddingChecklistItem>[])
        .where((t) => me.visibleScopes.contains(t.scope))
        .toList();
    final vendors = (ref.watch(weddingVendorsProvider(wedding.id)).valueOrNull ??
            const <WeddingVendor>[])
        .where((v) => me.isCouple || v.visibleToKey(me.key))
        .toList();
    final expenses =
        ref.watch(weddingExpensesProvider(wedding.id)).valueOrNull ??
            const <WeddingExpense>[];
    final notes = (ref.watch(weddingNotesProvider(wedding.id)).valueOrNull ??
            const <WeddingNote>[])
        .where((n) => me.visibleScopes.contains(n.scope))
        .toList();
    final events = ref.watch(weddingEventsProvider(wedding.id)).valueOrNull ??
        const <WeddingEvent>[];
    final decisions =
        ref.watch(weddingDecisionsProvider(wedding.id)).valueOrNull ??
            const <WeddingDecision>[];
    final activity = (ref
                .watch(weddingActivityProvider(wedding.id))
                .valueOrNull ??
            const <WeddingActivity>[])
        .where((a) =>
            a.scope == 'shared' || me.visibleScopes.contains(a.scope))
        .toList();

    // ── Matches (finalized/selected first) ──
    final selectedPhotoHits = q.isEmpty
        ? const <WeddingPhoto>[]
        : photos
            .where((p) =>
                p.isSelected && _match(q, [p.album, p.caption, p.selectedBy]))
            .toList();
    final selectedVendorHits = q.isEmpty
        ? const <WeddingVendor>[]
        : vendors
            .where((v) =>
                v.isSelected && _match(q, [v.name, v.category, v.notes]))
            .toList();
    final taskHits = q.isEmpty
        ? const <WeddingChecklistItem>[]
        : tasks
            .where((t) => _match(q, [
                  t.title,
                  t.description,
                  t.category,
                  t.notes,
                  t.assignedToName,
                ]))
            .toList();
    final photoHits = q.isEmpty
        ? const <WeddingPhoto>[]
        : photos
            .where((p) =>
                !p.isSelected && _match(q, [p.album, p.caption]))
            .toList();
    final vendorHits = q.isEmpty
        ? const <WeddingVendor>[]
        : vendors
            .where((v) =>
                !v.isSelected &&
                _match(q, [v.name, v.category, v.contactPerson, v.notes]))
            .toList();
    final expenseHits = q.isEmpty
        ? const <WeddingExpense>[]
        : expenses
            .where((e) => _match(q, [e.title, e.category, e.paidBy, e.notes]))
            .toList();
    final noteHits = q.isEmpty
        ? const <WeddingNote>[]
        : notes.where((n) => _match(q, [n.title, n.body])).toList();
    final eventHits = q.isEmpty
        ? const <WeddingEvent>[]
        : events
            .where((e) => _match(q, [e.title, e.type, e.location, e.notes]))
            .toList();
    final decisionHits = q.isEmpty
        ? const <WeddingDecision>[]
        : decisions
            .where((d) =>
                _match(q, [d.field, d.oldValue, d.newValue, d.reason]))
            .toList();
    final activityHits = q.isEmpty
        ? const <WeddingActivity>[]
        : activity.where((a) => _match(q, [a.text])).toList();

    final hasResults = selectedPhotoHits.isNotEmpty ||
        selectedVendorHits.isNotEmpty ||
        taskHits.isNotEmpty ||
        photoHits.isNotEmpty ||
        vendorHits.isNotEmpty ||
        expenseHits.isNotEmpty ||
        noteHits.isNotEmpty ||
        eventHits.isNotEmpty ||
        decisionHits.isNotEmpty ||
        activityHits.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _queryCtrl,
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search hall, jewellery, vendor, task…',
              hintStyle: TextStyle(fontSize: 13.5, color: Colors.grey[500]),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _queryCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: q.isEmpty
              ? Center(
                  child: Text(
                      'Search everything: photos, tasks, vendors,\n'
                      'expenses, notes, events, decisions…',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Colors.grey[500], fontSize: 13)),
                )
              : !hasResults
                  ? Center(
                      child: Text('No results for "$_query".',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 13)),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        // ── Finalized / selected content ALWAYS first ──
                        if (selectedPhotoHits.isNotEmpty ||
                            selectedVendorHits.isNotEmpty) ...[
                          _sectionTitle('⭐ Selected / Finalized'),
                          ...selectedVendorHits.map((v) => _tile(
                                emoji: '⭐',
                                title: '${v.name} — Selected Vendor',
                                subtitle:
                                    '${v.category} · selected by ${v.selectedBy}',
                                highlight: true,
                              )),
                          ...selectedPhotoHits.map((p) => _tile(
                                emoji: '⭐',
                                title:
                                    'Selected ${p.album}${p.caption.isNotEmpty ? ' — ${p.caption}' : ''}',
                                subtitle:
                                    'Selected by ${p.selectedBy.isEmpty ? '—' : p.selectedBy}'
                                    '${p.voteResult != null ? ' · ${p.voteResult}' : ''}',
                                highlight: true,
                                onTap: () =>
                                    showImageGallery(context, [p.url]),
                              )),
                        ],
                        if (taskHits.isNotEmpty) ...[
                          _sectionTitle('Tasks'),
                          ...taskHits.map((t) => _tile(
                                emoji: '✅',
                                title: t.title,
                                subtitle: [
                                  t.isCompleted ? 'Completed' : 'Pending',
                                  if (t.assignedToName.isNotEmpty)
                                    'assigned to ${t.assignedToName}'
                                  else
                                    'General Task',
                                  weddingScopeLabelLocal(t.scope),
                                ].join(' · '),
                              )),
                        ],
                        if (photoHits.isNotEmpty) ...[
                          _sectionTitle('Gallery Photos'),
                          ...photoHits.take(15).map((p) => _tile(
                                emoji: '📸',
                                title: p.caption.isNotEmpty
                                    ? p.caption
                                    : p.album,
                                subtitle:
                                    '${p.album} · ${weddingScopeLabelLocal(p.scope)} · by ${p.uploadedByName}',
                                onTap: () =>
                                    showImageGallery(context, [p.url]),
                              )),
                        ],
                        if (vendorHits.isNotEmpty) ...[
                          _sectionTitle('Vendors'),
                          ...vendorHits.map((v) => _tile(
                                emoji: '🏪',
                                title: v.name,
                                subtitle:
                                    '${v.category}${v.mobile.isNotEmpty ? ' · ${v.mobile}' : ''}',
                              )),
                        ],
                        if (expenseHits.isNotEmpty) ...[
                          _sectionTitle('Expenses'),
                          ...expenseHits.map((e) => _tile(
                                emoji: '💸',
                                title: '${e.title} — ₹${e.amount}',
                                subtitle:
                                    '${e.category} · ${e.date.day}/${e.date.month}/${e.date.year}',
                              )),
                        ],
                        if (noteHits.isNotEmpty) ...[
                          _sectionTitle('Discussion Notes'),
                          ...noteHits.map((n) => _tile(
                                emoji: '📝',
                                title: n.title,
                                subtitle:
                                    '${weddingScopeLabelLocal(n.scope)} · by ${n.createdByName}',
                              )),
                        ],
                        if (eventHits.isNotEmpty) ...[
                          _sectionTitle('Calendar Events'),
                          ...eventHits.map((e) => _tile(
                                emoji: '📅',
                                title: e.title,
                                subtitle:
                                    '${e.type} · ${e.dateTime.day}/${e.dateTime.month}/${e.dateTime.year}',
                              )),
                        ],
                        if (decisionHits.isNotEmpty) ...[
                          _sectionTitle('Decision History'),
                          ...decisionHits.map((d) => _tile(
                                emoji: '🔁',
                                title:
                                    '${d.field}: ${d.oldValue.isEmpty ? '—' : d.oldValue} → ${d.newValue}',
                                subtitle: 'By ${d.changedBy}',
                              )),
                        ],
                        if (activityHits.isNotEmpty) ...[
                          _sectionTitle('Activity Logs'),
                          ...activityHits.take(15).map((a) => _tile(
                                emoji: '🕘',
                                title: a.text,
                                subtitle:
                                    '${a.at.day}/${a.at.month}/${a.at.year}',
                              )),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }

  String weddingScopeLabelLocal(String scope) => switch (scope) {
        'bride' => 'Bride',
        'groom' => 'Groom',
        _ => 'Shared',
      };

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
      child: Text(title,
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
              color: AppColors.primary)),
    );
  }

  Widget _tile({
    required String emoji,
    required String title,
    required String subtitle,
    bool highlight = false,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: highlight
            ? Border.all(color: AppColors.gold.withOpacity(0.6), width: 1.4)
            : null,
      ),
      child: ListTile(
        dense: true,
        onTap: onTap,
        leading: Text(emoji, style: const TextStyle(fontSize: 18)),
        title: Text(title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5)),
      ),
    );
  }
}
