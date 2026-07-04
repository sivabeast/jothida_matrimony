import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_workspace_screen.dart' show weddingByLine;

/// Wedding Checklist: everyone in the workspace (bride, groom, both
/// families) can create items, assign them to another member (who accepts or
/// rejects, optionally with a reason) and mark them Pending / Completed.
/// [scope] narrows the list to 'shared' / 'bride' / 'groom' tasks (null =
/// everything); new tasks are created in the current scope.
class WeddingChecklistTab extends ConsumerStatefulWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  final String? scope;
  const WeddingChecklistTab(
      {super.key, required this.wedding, required this.identity, this.scope});

  @override
  ConsumerState<WeddingChecklistTab> createState() =>
      _WeddingChecklistTabState();
}

class _WeddingChecklistTabState extends ConsumerState<WeddingChecklistTab> {
  /// Common Tamil-wedding tasks offered as one-tap suggestions.
  static const _suggestions = [
    'Engagement Completed',
    'Hall Booking',
    'Photographer Booking',
    'Decoration',
    'Catering',
    'Invitation Printing',
    'Wedding Saree',
    'Groom Dress',
    'Jewellery Purchase',
    'Makeup Artist',
    'Return Gifts',
  ];

  bool _onlyMyTasks = false;

  WeddingModel get wedding => widget.wedding;
  WeddingIdentity get me => widget.identity;

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(weddingChecklistProvider(wedding.id));
    final everything = itemsAsync.valueOrNull ?? const <WeddingChecklistItem>[];
    final all = widget.scope == null
        ? everything
        : everything.where((i) => i.scope == widget.scope).toList();
    final items = _onlyMyTasks
        ? all.where((i) => i.assignedToKey == me.key).toList()
        : all;
    final total = all.length;
    final done = all.where((i) => i.isCompleted).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'wedding_checklist_fab',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_task),
        label: const Text('Add Task'),
        onPressed: () => _showItemSheet(),
      ),
      body: itemsAsync.isLoading && all.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: [
                _progressHeader(total: total, done: done),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('My Tasks'),
                      selected: _onlyMyTasks,
                      selectedColor: AppColors.primary.withOpacity(0.15),
                      checkmarkColor: AppColors.primary,
                      onSelected: (v) => setState(() => _onlyMyTasks = v),
                    ),
                    const Spacer(),
                    Text('${items.length} task${items.length == 1 ? '' : 's'}',
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                if (all.isEmpty) _suggestionsCard(),
                ...items.map(_itemCard),
              ],
            ),
    );
  }

  // ── Progress bar (spec: "Wedding Preparation · 16/20 · 80%") ─────────────

  Widget _progressHeader({required int total, required int done}) {
    final percent = total == 0 ? 0 : ((done / total) * 100).round();
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
          const Text('Wedding Preparation',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('$done / $total Tasks Completed',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
              Text('$percent%',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 10,
              backgroundColor: Colors.grey[200],
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.success),
            ),
          ),
        ],
      ),
    );
  }

  // ── First-run suggestions ─────────────────────────────────────────────────

  Widget _suggestionsCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Start with the common wedding tasks:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions
                .map((s) => ActionChip(
                      label: Text(s, style: const TextStyle(fontSize: 12)),
                      avatar: const Icon(Icons.add,
                          size: 15, color: AppColors.primary),
                      onPressed: () => ref
                          .read(weddingControllerProvider.notifier)
                          .addChecklistItem(wedding.id,
                              title: s,
                              scope: widget.scope ?? 'shared',
                              me: me),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  // ── Item card ─────────────────────────────────────────────────────────────

  Widget _itemCard(WeddingChecklistItem item) {
    final assignedToMe =
        item.isAssigned && item.assignedToKey == me.key;
    final awaitingMyResponse =
        assignedToMe && item.assignmentStatus == 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: awaitingMyResponse
            ? Border.all(color: AppColors.warning.withOpacity(0.6))
            : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pending / Completed toggle — the only two statuses.
              Checkbox(
                value: item.isCompleted,
                activeColor: AppColors.success,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5)),
                visualDensity: VisualDensity.compact,
                onChanged: (v) => ref
                    .read(weddingControllerProvider.notifier)
                    .setChecklistStatus(wedding.id, item.id, v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        decoration: item.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color:
                            item.isCompleted ? Colors.grey[500] : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text('Created by ${weddingByLine(item.createdByName, item.createdAt)}',
                        style:
                            TextStyle(color: Colors.grey[500], fontSize: 11)),
                    if (item.notes.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(item.notes,
                          style: TextStyle(
                              color: Colors.grey[700], fontSize: 12.5)),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _statusChip(item),
                        if (item.isAssigned) _assignmentChip(item),
                      ],
                    ),
                    if (item.assignmentStatus == 'rejected' &&
                        item.rejectionReason.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text('Rejection reason: ${item.rejectionReason}',
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 11.5)),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[500]),
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      _showItemSheet(existing: item);
                    case 'assign':
                      _showAssignSheet(item);
                    case 'delete':
                      _confirmDelete(item);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                      value: 'assign',
                      child: Text(item.isAssigned ? 'Reassign' : 'Assign To')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          // ── Assignment response (assignee only) ──
          if (awaitingMyResponse) ...[
            const Divider(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text('This task was assigned to you.',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      visualDensity: VisualDensity.compact),
                  onPressed: () => _rejectAssignment(item),
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact),
                  onPressed: () => ref
                      .read(weddingControllerProvider.notifier)
                      .respondToAssignment(wedding.id, item.id, accept: true),
                  child: const Text('Accept'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(WeddingChecklistItem item) {
    final color = item.isCompleted ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(item.isCompleted ? 'Completed' : 'Pending',
          style: TextStyle(
              color: color, fontSize: 10.5, fontWeight: FontWeight.bold)),
    );
  }

  Widget _assignmentChip(WeddingChecklistItem item) {
    final (label, color) = switch (item.assignmentStatus) {
      'accepted' => ('${item.assignedToName} ✓', AppColors.success),
      'rejected' => ('${item.assignedToName} ✗', AppColors.error),
      _ => ('${item.assignedToName} · awaiting response', AppColors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Add / edit sheet ──────────────────────────────────────────────────────

  void _showItemSheet({WeddingChecklistItem? existing}) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    WeddingParticipant? assignee;
    final formKey = GlobalKey<FormState>();
    final participants = weddingParticipants(wedding);

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
                Text(existing == null ? 'Add Checklist Task' : 'Edit Task',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: titleCtrl,
                  decoration: _input('Title (e.g. Hall Booking)'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: _input('Notes (optional)'),
                ),
                if (existing == null) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<WeddingParticipant?>(
                    value: assignee,
                    decoration: _input('Assign To (optional)'),
                    items: [
                      const DropdownMenuItem<WeddingParticipant?>(
                          value: null, child: Text('Not assigned')),
                      ...participants
                          .where((p) => p.key != me.key)
                          .map((p) => DropdownMenuItem<WeddingParticipant?>(
                                value: p,
                                child: Text('${p.name} (${p.roleLabel})',
                                    overflow: TextOverflow.ellipsis),
                              )),
                    ],
                    onChanged: (v) => setSheetState(() => assignee = v),
                  ),
                ],
                const SizedBox(height: 18),
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
                      final controller =
                          ref.read(weddingControllerProvider.notifier);
                      if (existing == null) {
                        await controller.addChecklistItem(
                          wedding.id,
                          title: titleCtrl.text.trim(),
                          notes: notesCtrl.text.trim(),
                          scope: widget.scope ?? 'shared',
                          me: me,
                          assignedToKey: assignee?.key ?? '',
                          assignedToName: assignee?.name ?? '',
                        );
                      } else {
                        await controller.updateChecklistItem(
                          wedding.id,
                          existing.id,
                          title: titleCtrl.text.trim(),
                          notes: notesCtrl.text.trim(),
                        );
                      }
                      navigator.pop();
                    },
                    child: Text(existing == null ? 'Add Task' : 'Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Assignment ────────────────────────────────────────────────────────────

  void _showAssignSheet(WeddingChecklistItem item) {
    final participants =
        weddingParticipants(wedding).where((p) => p.key != me.key).toList();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text('Assign "${item.title}" to…',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
            ),
            if (participants.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Text(
                    'No other members yet — invite family members from the '
                    'Overview tab first.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              )
            else
              ...participants.map((p) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      child: Text(
                          p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                          style:
                              const TextStyle(color: AppColors.primary)),
                    ),
                    title: Text(p.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(p.roleLabel,
                        style: const TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(ctx);
                      ref
                          .read(weddingControllerProvider.notifier)
                          .assignChecklistItem(wedding.id, item.id,
                              assignee: p);
                    },
                  )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _rejectAssignment(WeddingChecklistItem item) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject this task?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('"${item.title}" will go back to unassigned.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: _input('Reason (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject Task'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(weddingControllerProvider.notifier).respondToAssignment(
        wedding.id, item.id,
        accept: false, reason: reasonCtrl.text.trim());
  }

  Future<void> _confirmDelete(WeddingChecklistItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('"${item.title}" will be removed for everyone.'),
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
        .deleteChecklistItem(wedding.id, item.id);
  }

  static InputDecoration _input(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}
