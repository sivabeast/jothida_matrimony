import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/data/wedding_planning_template.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_planning_page.dart';
import 'wedding_workspace_screen.dart' show weddingByLine;

/// TASKS — the workspace to-do system with strict side visibility (my side +
/// Shared only) and role-based control:
///   • Task Name is the only mandatory field;
///   • no assignee → General Task (anyone with permission completes it);
///   • assigned task → only the assignee (or a Super Admin) completes it;
///   • the creator is the OWNER (edit / delete / reassign / reopen);
///   • the Bride & Groom (Super Admins) override everything.
class WeddingTasksTab extends ConsumerStatefulWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  const WeddingTasksTab(
      {super.key, required this.wedding, required this.identity});

  @override
  ConsumerState<WeddingTasksTab> createState() => _WeddingTasksTabState();
}

class _WeddingTasksTabState extends ConsumerState<WeddingTasksTab> {
  late String _scope = widget.identity.side; // my side first; Shared next
  bool _onlyMyTasks = false;
  String _category = 'All'; // 'All' | 'General' | <category name>
  String _statusFilter = 'All'; // 'All' | 'Pending' | 'In Progress' | 'Completed'

  WeddingModel get wedding => widget.wedding;
  WeddingIdentity get me => widget.identity;

  /// Derived status: an accepted-but-unfinished assignment is "In Progress".
  String _statusOf(WeddingChecklistItem t) {
    if (t.isCompleted) return 'Completed';
    if (t.assignmentStatus == 'accepted') return 'In Progress';
    return 'Pending';
  }

  // ── Role-based access control ─────────────────────────────────────────────

  bool _isOwner(WeddingChecklistItem t) => t.createdByKey == me.key;

  bool _canComplete(WeddingChecklistItem t) {
    if (me.isSuperAdmin) return true;
    if (t.isGeneral) return me.can(WeddingPermissions.completeTask);
    return t.assignedToKey == me.key;
  }

  bool _canReopen(WeddingChecklistItem t) =>
      me.isSuperAdmin ||
      _isOwner(t) ||
      (t.assignedToKey == me.key && me.can(WeddingPermissions.reopenTask));

  bool _canEdit(WeddingChecklistItem t) =>
      me.isSuperAdmin || _isOwner(t) || me.can(WeddingPermissions.editTask);

  bool _canDelete(WeddingChecklistItem t) =>
      me.isSuperAdmin || _isOwner(t) || me.can(WeddingPermissions.deleteTask);

  bool _canAssign(WeddingChecklistItem t) =>
      me.isSuperAdmin ||
      _isOwner(t) ||
      me.can(t.isAssigned
          ? WeddingPermissions.reassignTask
          : WeddingPermissions.assignTask);

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(weddingChecklistProvider(wedding.id));
    final everything =
        itemsAsync.valueOrNull ?? const <WeddingChecklistItem>[];
    // STRICT side visibility: only my side + shared ever reach the UI.
    final all = everything
        .where((i) => i.scope == _scope && me.visibleScopes.contains(i.scope))
        .toList();
    // Categories present in this scope, in template order + any extras.
    final presentCategories = <String>{
      for (final t in all) if (t.category.isNotEmpty) t.category,
    };
    final orderedCategories = [
      ...kWeddingPlanCategoryNames.where(presentCategories.contains),
      ...presentCategories.where((c) => !kWeddingPlanCategoryNames.contains(c)),
    ];

    Iterable<WeddingChecklistItem> filtered = all;
    if (_onlyMyTasks) {
      filtered = filtered.where((i) => i.assignedToKey == me.key);
    }
    if (_category == 'General') {
      filtered = filtered.where((i) => i.isGeneral);
    } else if (_category != 'All') {
      filtered = filtered.where((i) => i.category == _category);
    }
    if (_statusFilter != 'All') {
      filtered = filtered.where((i) => _statusOf(i) == _statusFilter);
    }
    final items = filtered.toList();

    // General tasks always surface separately when viewing everything.
    final generalItems = (_category == 'All' && _statusFilter == 'All')
        ? items.where((i) => i.isGeneral).toList()
        : const <WeddingChecklistItem>[];
    final mainItems = (_category == 'All' && _statusFilter == 'All')
        ? items.where((i) => !i.isGeneral).toList()
        : items;

    final total = all.length;
    final done = all.where((i) => i.isCompleted).length;

    /// A category is complete when it has ≥1 task and all are done.
    bool categoryComplete(String cat) {
      final catTasks = all.where((t) => t.category == cat).toList();
      return catTasks.isNotEmpty && catTasks.every((t) => t.isCompleted);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: me.can(WeddingPermissions.createTask)
          ? FloatingActionButton.extended(
              heroTag: 'wedding_tasks_fab',
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_task),
              label: const Text('Add Task'),
              onPressed: () => _showTaskSheet(),
            )
          : null,
      body: Column(
        children: [
          _scopeSwitcher(),
          _categoryChips(orderedCategories, categoryComplete),
          _statusChips(),
          Expanded(
            child: itemsAsync.isLoading && everything.isEmpty
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primary))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                    children: [
                      _planBanner(),
                      const SizedBox(height: 10),
                      _progressHeader(total: total, done: done),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          FilterChip(
                            label: const Text('My Tasks'),
                            selected: _onlyMyTasks,
                            selectedColor:
                                AppColors.primary.withOpacity(0.15),
                            checkmarkColor: AppColors.primary,
                            onSelected: (v) =>
                                setState(() => _onlyMyTasks = v),
                          ),
                          const Spacer(),
                          Text(
                              '${items.length} task${items.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (items.isEmpty) _empty(),
                      // General Tasks surfaced first (unassigned).
                      if (generalItems.isNotEmpty) ...[
                        _sectionHeader(
                            'General Tasks', generalItems.length,
                            'Unassigned — anyone with permission can pick these up'),
                        ...generalItems.map(_taskCard),
                        if (mainItems.isNotEmpty) const SizedBox(height: 6),
                      ],
                      ...mainItems.map(_taskCard),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Entry point to the template-driven Planning page.
  Widget _planBanner() {
    return Material(
      color: AppColors.primary.withOpacity(0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const WeddingPlanningPage())),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    shape: BoxShape.circle),
                child: const Icon(Icons.playlist_add_check_circle_outlined,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plan the Wedding',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5)),
                    Text('Pick what you need — tasks are created for you',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, int count, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5)),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$count',
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal)),
              ),
            ],
          ),
          Text(subtitle,
              style: TextStyle(fontSize: 10.5, color: Colors.grey[500])),
        ],
      ),
    );
  }

  // ── Category chips (with ✔ completion indicator) ──────────────────────────

  Widget _categoryChips(
      List<String> categories, bool Function(String) categoryComplete) {
    final chips = <String>['All', 'General', ...categories].map((cat) {
      final selected = _category == cat;
      final complete = cat != 'All' && cat != 'General' && categoryComplete(cat);
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(
            complete ? '✔ $cat' : cat,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : complete
                        ? AppColors.success
                        : Colors.grey[700]),
          ),
          selected: selected,
          selectedColor: AppColors.primary,
          backgroundColor:
              complete ? AppColors.success.withOpacity(0.1) : Colors.white,
          onSelected: (_) => setState(() => _category = cat),
        ),
      );
    }).toList();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: chips,
      ),
    );
  }

  Widget _statusChips() {
    const statuses = ['All', 'Pending', 'In Progress', 'Completed'];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: statuses.map((s) {
          final selected = _statusFilter == s;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(s, style: const TextStyle(fontSize: 11.5)),
              selected: selected,
              selectedColor: AppColors.primary.withOpacity(0.15),
              checkmarkColor: AppColors.primary,
              onSelected: (_) => setState(() => _statusFilter = s),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// My side ↔ Shared. The opposite side's tasks are never reachable.
  Widget _scopeSwitcher() {
    Widget chip(String scope, String label, String emoji) {
      final active = _scope == scope;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _scope = scope),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color:
                      active ? AppColors.primary : Colors.grey.shade300),
            ),
            child: Text('$emoji  $label',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : Colors.grey[700])),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          chip(me.side, me.side == 'groom' ? 'Groom' : 'Bride',
              me.side == 'groom' ? '🤵' : '👰'),
          const SizedBox(width: 10),
          chip('shared', 'Shared', '❤️'),
        ],
      ),
    );
  }

  Widget _empty() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.task_alt, size: 46, color: Colors.grey[350]),
          const SizedBox(height: 10),
          Text(
            _scope == 'shared'
                ? 'No shared tasks yet. Tasks here are visible to both sides.'
                : 'No ${me.side} tasks yet. Tasks here stay private to the '
                    '${me.side} side until moved to Shared.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  // ── Progress ──────────────────────────────────────────────────────────────

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
          Text(
              _scope == 'shared'
                  ? 'Shared Preparation'
                  : '${me.side == 'groom' ? 'Groom' : 'Bride'} Preparation',
              style: const TextStyle(
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

  // ── Task card ─────────────────────────────────────────────────────────────

  Widget _taskCard(WeddingChecklistItem item) {
    final awaitingMyResponse = item.isAssigned &&
        item.assignedToKey == me.key &&
        item.assignmentStatus == 'pending';
    final overdue = item.dueDate != null &&
        !item.isCompleted &&
        item.dueDate!.isBefore(DateTime.now());

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
              Checkbox(
                value: item.isCompleted,
                activeColor: AppColors.success,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5)),
                visualDensity: VisualDensity.compact,
                onChanged: (item.isCompleted
                        ? _canReopen(item)
                        : _canComplete(item))
                    ? (v) => ref
                        .read(weddingControllerProvider.notifier)
                        .setChecklistStatus(
                            wedding.id, item, v ?? false, me)
                    : null,
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
                        color: item.isCompleted
                            ? Colors.grey[500]
                            : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                        'By ${weddingByLine(item.createdByName, item.createdAt)}'
                        '${item.isCompleted && item.completedByName.isNotEmpty ? ' · done by ${item.completedByName}' : ''}',
                        style:
                            TextStyle(color: Colors.grey[500], fontSize: 11)),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(item.description,
                          style: TextStyle(
                              color: Colors.grey[700], fontSize: 12.5)),
                    ],
                    if (item.notes.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text('Note: ${item.notes}',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 11.5)),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _chip(item.isCompleted ? 'Completed' : 'Pending',
                            item.isCompleted
                                ? AppColors.success
                                : AppColors.warning),
                        if (item.priority.isNotEmpty)
                          _chip(item.priority, _priorityColor(item.priority)),
                        if (item.category.isNotEmpty)
                          _chip(item.category, AppColors.primary),
                        if (item.dueDate != null)
                          _chip(
                              'Due ${item.dueDate!.day}/${item.dueDate!.month}/${item.dueDate!.year}',
                              overdue ? AppColors.error : Colors.blueGrey),
                        item.isGeneral
                            ? _chip('General Task', Colors.teal)
                            : _assignmentChip(item),
                      ],
                    ),
                    if (item.assignmentStatus == 'rejected' &&
                        item.rejectionReason.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text('Rejection reason: ${item.rejectionReason}',
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 11.5)),
                    ],
                    if (item.attachments.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final url in item.attachments)
                            ActionChip(
                              avatar: const Icon(Icons.attach_file,
                                  size: 14, color: AppColors.primary),
                              label: const Text('Attachment',
                                  style: TextStyle(fontSize: 11)),
                              onPressed: () =>
                                  openRemoteFile(context, url, pdf: true),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (_canEdit(item) || _canDelete(item) || _canAssign(item))
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      size: 20, color: Colors.grey[500]),
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':
                        _showTaskSheet(existing: item);
                      case 'assign':
                        _showAssignSheet(item);
                      case 'share':
                        _confirmMoveToShared(item);
                      case 'delete':
                        _confirmDelete(item);
                    }
                  },
                  itemBuilder: (_) => [
                    if (_canEdit(item))
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    if (_canAssign(item))
                      PopupMenuItem(
                          value: 'assign',
                          child: Text(
                              item.isAssigned ? 'Reassign' : 'Assign To')),
                    if (item.scope != 'shared' &&
                        (me.isSuperAdmin || _isOwner(item)))
                      const PopupMenuItem(
                          value: 'share', child: Text('Move to Shared')),
                    if (_canDelete(item))
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
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

  Color _priorityColor(String p) => switch (p) {
        'Urgent' => AppColors.error,
        'High' => Colors.deepOrange,
        'Medium' => AppColors.warning,
        _ => Colors.blueGrey,
      };

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
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

  // ── Add / edit sheet — Task Name is the ONLY required field ──────────────

  void _showTaskSheet({WeddingChecklistItem? existing}) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl =
        TextEditingController(text: existing?.description ?? '');
    final categoryCtrl =
        TextEditingController(text: existing?.category ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String priority = existing?.priority ?? '';
    DateTime? dueDate = existing?.dueDate;
    WeddingParticipant? assignee;
    final attachments = List<String>.of(existing?.attachments ?? const []);
    var uploadingAttachment = false;
    final formKey = GlobalKey<FormState>();
    // Only participants of the CURRENT scope's sides can be assigned:
    // shared → everyone; side scope → that side only.
    final participants = weddingParticipants(wedding)
        .where((p) => p.key != me.key)
        .where((p) {
      if (_scope == 'shared') return true;
      for (final uid in wedding.coupleIds) {
        if (p.key == uid) return wedding.sideOf(uid) == _scope;
      }
      for (final m in wedding.members) {
        if (p.key == m.email) return m.side == _scope;
      }
      return false;
    }).toList();

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
                  Text(existing == null ? 'Add Task' : 'Edit Task',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Only the task name is required.',
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 11.5)),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: titleCtrl,
                    decoration: _input('Task Name *'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter the task name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: _input('Description (optional)')),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                            controller: categoryCtrl,
                            decoration:
                                _input('Category (e.g. Hall, Dress)')),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: priority.isEmpty ? null : priority,
                          decoration: _input('Priority'),
                          items: [
                            const DropdownMenuItem<String>(
                                value: '', child: Text('None')),
                            ...WeddingChecklistItem.priorities.map((p) =>
                                DropdownMenuItem(value: p, child: Text(p))),
                          ],
                          onChanged: (v) =>
                              setSheetState(() => priority = v ?? ''),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: dueDate ?? now,
                        firstDate: DateTime(now.year - 1),
                        lastDate: DateTime(now.year + 3),
                        helpText: 'Due Date (optional)',
                      );
                      if (picked != null) {
                        setSheetState(() => dueDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: _input('Due Date (optional)'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              dueDate == null
                                  ? 'Not set'
                                  : '${dueDate!.day}/${dueDate!.month}/${dueDate!.year}',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  color: dueDate == null
                                      ? Colors.grey[500]
                                      : Colors.black87),
                            ),
                          ),
                          if (dueDate != null)
                            GestureDetector(
                              onTap: () =>
                                  setSheetState(() => dueDate = null),
                              child: Icon(Icons.close,
                                  size: 17, color: Colors.grey[500]),
                            ),
                          const SizedBox(width: 6),
                          const Icon(Icons.event,
                              size: 18, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                  if (existing == null) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<WeddingParticipant?>(
                      value: assignee,
                      decoration: _input('Assign To (optional)'),
                      items: [
                        const DropdownMenuItem<WeddingParticipant?>(
                            value: null,
                            child: Text('Not assigned → General Task')),
                        ...participants.map((p) =>
                            DropdownMenuItem<WeddingParticipant?>(
                              value: p,
                              child: Text('${p.name} (${p.roleLabel})',
                                  overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) => setSheetState(() => assignee = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: _input('Notes (optional)')),
                  const SizedBox(height: 12),
                  // ── Attachments (optional) ──
                  Row(
                    children: [
                      Text('Attachments',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700])),
                      const SizedBox(width: 8),
                      if (attachments.isNotEmpty)
                        Text('${attachments.length} added',
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.grey[500])),
                      const Spacer(),
                      TextButton.icon(
                        icon: uploadingAttachment
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.attach_file, size: 16),
                        label: Text(
                            uploadingAttachment ? 'Uploading…' : 'Add'),
                        onPressed: uploadingAttachment
                            ? null
                            : () async {
                                setSheetState(
                                    () => uploadingAttachment = true);
                                final url = await _pickAndUploadAttachment();
                                setSheetState(() {
                                  uploadingAttachment = false;
                                  if (url != null) attachments.add(url);
                                });
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
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
                            description: descCtrl.text.trim(),
                            notes: notesCtrl.text.trim(),
                            category: categoryCtrl.text.trim(),
                            priority: priority,
                            dueDate: dueDate,
                            attachments: attachments,
                            scope: _scope,
                            me: me,
                            assignedToKey: assignee?.key ?? '',
                            assignedToName: assignee?.name ?? '',
                          );
                        } else {
                          await controller.updateChecklistItem(
                            wedding.id,
                            existing.id,
                            {
                              'title': titleCtrl.text.trim(),
                              'description': descCtrl.text.trim(),
                              'notes': notesCtrl.text.trim(),
                              'category': categoryCtrl.text.trim(),
                              'priority': priority,
                              'dueDate': dueDate,
                              'attachments': attachments,
                            },
                          );
                        }
                        navigator.pop();
                      },
                      child:
                          Text(existing == null ? 'Add Task' : 'Save Task'),
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

  Future<String?> _pickAndUploadAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: const Text('Image'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined,
                  color: AppColors.primary),
              title: const Text('PDF / File'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return null;

    File? file;
    var isImage = choice == 'image';
    if (isImage) {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (x != null) file = File(x.path);
    } else {
      final res = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx']);
      final path = res?.files.single.path;
      if (path != null) file = File(path);
    }
    if (file == null) return null;
    return ref
        .read(weddingControllerProvider.notifier)
        .uploadTaskAttachment(wedding.id, file, isImage: isImage);
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
                    'menu → Family Members first.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              )
            else
              ...participants.map((p) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      child: Text(
                          p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                          style: const TextStyle(color: AppColors.primary)),
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

  Future<void> _confirmMoveToShared(WeddingChecklistItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to Shared?'),
        content: Text('"${item.title}" will become visible to BOTH sides.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Move to Shared'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(weddingControllerProvider.notifier)
        .moveTaskToShared(wedding.id, item, me);
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
