import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/announcement_model.dart';
import '../../models/astrologer_team_member.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/announcement_provider.dart';
import '../../providers/astrology_team_provider.dart';

/// Admin "Notification Management" — TWO fully independent systems (per spec):
///
///  • **User Notifications** — match/report/membership/booking/payment updates
///    sent to ALL users or to SELECTED users. Never visible to employees.
///  • **Employee Notifications** — assignments, announcements, priority
///    reports, work reminders, maintenance notes sent to ALL employees or to
///    SELECTED employees. Never visible to normal users.
///
/// "Send to All" writes an audience-scoped broadcast to `announcements`;
/// "Send to Selected" writes per-account documents to `notifications`, so only
/// the chosen accounts ever receive them. Registered at `/admin/notifications`.
class AnnouncementManagementScreen extends ConsumerStatefulWidget {
  const AnnouncementManagementScreen({super.key});

  @override
  ConsumerState<AnnouncementManagementScreen> createState() =>
      _AnnouncementManagementScreenState();
}

class _AnnouncementManagementScreenState
    extends ConsumerState<AnnouncementManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  AnnouncementAudience get _audience => _tabs.index == 0
      ? AnnouncementAudience.users
      : AnnouncementAudience.employees;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Notification Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.gold,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.people_outline, size: 20), text: 'Users'),
            Tab(icon: Icon(Icons.badge_outlined, size: 20), text: 'Employees'),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabs,
        builder: (_, __) => FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          onPressed: () => _openCompose(context, _audience),
          icon: const Icon(Icons.send),
          label: Text(_tabs.index == 0 ? 'Notify Users' : 'Notify Employees'),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _AudienceTab(audience: AnnouncementAudience.users),
          _AudienceTab(audience: AnnouncementAudience.employees),
        ],
      ),
    );
  }

  // ── Compose (new notification) ────────────────────────────────────────────

  /// Type choices offered per audience — employee kinds match the spec's
  /// examples (announcement / high priority / work reminder / maintenance).
  static List<AnnouncementType> _typesFor(AnnouncementAudience a) =>
      a == AnnouncementAudience.users
          ? const [
              AnnouncementType.general,
              AnnouncementType.announcement,
              AnnouncementType.featureUpdate,
              AnnouncementType.offer,
              AnnouncementType.maintenance,
              AnnouncementType.other,
            ]
          : const [
              AnnouncementType.announcement,
              AnnouncementType.highPriority,
              AnnouncementType.workReminder,
              AnnouncementType.maintenance,
              AnnouncementType.general,
              AnnouncementType.other,
            ];

  Future<void> _openCompose(
      BuildContext context, AnnouncementAudience audience) async {
    final titleC = TextEditingController();
    final msgC = TextEditingController();
    final urlC = TextEditingController();
    final labelC = TextEditingController();
    var type = audience == AnnouncementAudience.users
        ? AnnouncementType.general
        : AnnouncementType.announcement;
    var toAll = true;
    var selected = <String, String>{}; // uid → display name
    var sending = false;

    final isUsers = audience == AnnouncementAudience.users;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(isUsers ? Icons.people : Icons.badge,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                        isUsers
                            ? 'New User Notification'
                            : 'New Employee Notification',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                    isUsers
                        ? 'Visible only to users — employees never see it.'
                        : 'Visible only to employees — users never see it.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 16),
                TextField(
                  controller: titleC,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Title *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: msgC,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Message', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AnnouncementType>(
                  value: type,
                  decoration: const InputDecoration(
                      labelText: 'Notification Type',
                      border: OutlineInputBorder()),
                  items: [
                    for (final t in _typesFor(audience))
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (v) => setLocal(() => type = v ?? type),
                ),
                const SizedBox(height: 16),
                Text('Recipients',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700])),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.1),
                    selectedForegroundColor: AppColors.primary,
                  ),
                  segments: [
                    ButtonSegment(
                        value: true,
                        icon: const Icon(Icons.campaign_outlined, size: 18),
                        label:
                            Text(isUsers ? 'All Users' : 'All Employees')),
                    ButtonSegment(
                        value: false,
                        icon: const Icon(Icons.checklist, size: 18),
                        label: Text(
                            isUsers ? 'Selected Users' : 'Selected Employees')),
                  ],
                  selected: {toAll},
                  onSelectionChanged: (s) =>
                      setLocal(() => toAll = s.first),
                ),
                if (!toAll) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await _pickRecipients(
                          ctx, audience, Map.of(selected));
                      if (picked != null) setLocal(() => selected = picked);
                    },
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: Text(selected.isEmpty
                        ? 'Choose recipients'
                        : '${selected.length} selected — tap to change'),
                  ),
                  if (selected.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final name in selected.values.take(6))
                            Chip(
                              label: Text(name,
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          if (selected.length > 6)
                            Chip(
                              label: Text('+${selected.length - 6} more',
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                        ],
                      ),
                    ),
                ],
                if (toAll) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlC,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Action Link (optional)',
                      hintText: 'https://…  or an internal page like /subscription',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: labelC,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Action Button Label (optional)',
                      hintText: type.defaultActionLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: sending
                        ? null
                        : () async {
                            final title = titleC.text.trim();
                            if (title.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                      content: Text('Title is required')));
                              return;
                            }
                            if (!toAll && selected.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Choose at least one recipient')));
                              return;
                            }
                            setLocal(() => sending = true);
                            // Captured before the awaits so the confirmation
                            // snackbar never touches a stale BuildContext.
                            final messenger = ScaffoldMessenger.of(context);
                            final ctrl = ref.read(
                                announcementControllerProvider.notifier);
                            if (toAll) {
                              await ctrl.create(
                                title: title,
                                message: msgC.text.trim(),
                                audience: audience.key,
                                type: type.key,
                                actionUrl: urlC.text.trim(),
                                actionLabel: labelC.text.trim(),
                              );
                            } else {
                              await ctrl.sendToSelected(
                                uids: selected.keys.toList(),
                                title: title,
                                body: msgC.text.trim(),
                                type: type.key,
                              );
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            messenger.showSnackBar(
                              SnackBar(
                                  content: Text(toAll
                                      ? 'Notification sent to all '
                                          '${isUsers ? 'users' : 'employees'}.'
                                      : 'Notification sent to '
                                          '${selected.length} '
                                          '${isUsers ? 'user(s)' : 'employee(s)'}.')),
                            );
                          },
                    icon: sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send, size: 18),
                    label: Text(sending ? 'Sending…' : 'Send Notification'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Multi-select recipient picker (with search). Returns uid → display name,
  /// or null when dismissed without confirming.
  Future<Map<String, String>?> _pickRecipients(BuildContext context,
      AnnouncementAudience audience, Map<String, String> initial) async {
    final isUsers = audience == AnnouncementAudience.users;
    var query = '';
    final picked = Map<String, String>.of(initial);

    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          // Candidate list, resolved live from the providers.
          final List<({String uid, String title, String subtitle})> all;
          if (isUsers) {
            final users =
                ref.watch(allUsersProvider).valueOrNull ?? const <UserModel>[];
            all = [
              for (final u in users)
                if (u.role == 'user' && !u.isBlocked)
                  (
                    uid: u.uid,
                    title: (u.displayName ?? '').trim().isEmpty
                        ? (u.email ?? u.uid)
                        : u.displayName!.trim(),
                    subtitle: u.email ?? '',
                  ),
            ];
          } else {
            final team = ref.watch(allAstrologerTeamProvider).valueOrNull ??
                const <AstrologerTeamMember>[];
            all = [
              for (final m in team)
                if (m.active && m.uid.trim().isNotEmpty)
                  (
                    uid: m.uid,
                    title: m.displayName.isEmpty ? m.email : m.displayName,
                    subtitle: m.email,
                  ),
            ];
          }
          final q = query.trim().toLowerCase();
          final visible = q.isEmpty
              ? all
              : [
                  for (final c in all)
                    if (c.title.toLowerCase().contains(q) ||
                        c.subtitle.toLowerCase().contains(q))
                      c
                ];

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                              isUsers
                                  ? 'Select Users'
                                  : 'Select Employees',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ),
                        Text('${picked.length} selected',
                            style: TextStyle(
                                fontSize: 12.5, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      onChanged: (v) => setLocal(() => query = v),
                      decoration: InputDecoration(
                        hintText: 'Search by name or email…',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: visible.isEmpty
                        ? Center(
                            child: Text(
                                isUsers
                                    ? 'No users found.'
                                    : 'No employees found.\nOnly employees who '
                                        'have signed in at least once can be '
                                        'selected.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey[600])),
                          )
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (_, i) {
                              final c = visible[i];
                              final checked = picked.containsKey(c.uid);
                              return CheckboxListTile(
                                dense: true,
                                value: checked,
                                activeColor: AppColors.primary,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(c.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: c.subtitle.isEmpty
                                    ? null
                                    : Text(c.subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            const TextStyle(fontSize: 11.5)),
                                onChanged: (v) => setLocal(() {
                                  if (v == true) {
                                    picked[c.uid] = c.title;
                                  } else {
                                    picked.remove(c.uid);
                                  }
                                }),
                              );
                            },
                          ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(ctx, picked),
                              child: Text('Done (${picked.length})'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── One audience's broadcast list ─────────────────────────────────────────────

class _AudienceTab extends ConsumerWidget {
  final AnnouncementAudience audience;
  const _AudienceTab({required this.audience});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allAnnouncementsProvider);
    final isUsers = audience == AnnouncementAudience.users;

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text('Could not load notifications.\n$e')),
      data: (items) {
        final mine =
            [for (final a in items) if (a.audienceEnum == audience) a];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            // Separation reminder.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: AppColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isUsers
                          ? 'Broadcasts below go to USERS only. Direct '
                              '"Selected Users" messages are delivered '
                              'straight to each user\'s notification feed.'
                          : 'Broadcasts below go to EMPLOYEES only. Direct '
                              '"Selected Employees" messages are delivered '
                              'straight to each employee\'s notification feed.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[800]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (mine.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Column(
                  children: [
                    Icon(Icons.campaign_outlined,
                        size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                        isUsers
                            ? 'No user notifications yet'
                            : 'No employee notifications yet',
                        style: const TextStyle(
                            fontSize: 15, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(
                        'Tap "${isUsers ? 'Notify Users' : 'Notify Employees'}" '
                        'to send one.',
                        style: TextStyle(
                            color: Colors.grey[500], fontSize: 12.5)),
                  ],
                ),
              )
            else
              for (final a in mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AnnouncementCard(announcement: a),
                ),
          ],
        );
      },
    );
  }
}

// ── One broadcast card (edit / delete / active toggle) ───────────────────────

class _AnnouncementCard extends ConsumerWidget {
  final AnnouncementModel announcement;
  const _AnnouncementCard({required this.announcement});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = announcement;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign, color: AppColors.gold, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(a.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (a.isActive ? AppColors.success : Colors.grey)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(a.isActive ? 'Active' : 'Hidden',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: a.isActive ? AppColors.success : Colors.grey)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _pill(a.typeEnum.label, AppColors.primary),
              _pill(a.audienceEnum.label,
                  a.isForUsers ? AppColors.info : AppColors.warning),
              if (a.hasAction)
                _pill('${a.effectiveActionLabel} → ${a.actionUrl}',
                    Colors.blue),
            ],
          ),
          if (a.message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(a.message, style: TextStyle(color: Colors.grey[800])),
          ],
          const SizedBox(height: 6),
          Text(_fmtDate(a.createdAt),
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          const Divider(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _openEdit(context, ref, a),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
              TextButton.icon(
                onPressed: () => _confirmDelete(context, ref, a),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete'),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );

  Future<void> _openEdit(
      BuildContext context, WidgetRef ref, AnnouncementModel a) async {
    final titleC = TextEditingController(text: a.title);
    final msgC = TextEditingController(text: a.message);
    final urlC = TextEditingController(text: a.actionUrl);
    final labelC = TextEditingController(text: a.actionLabel);
    var active = a.isActive;
    var type = a.typeEnum;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Notification'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleC,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Title', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: msgC,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Message', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AnnouncementType>(
                  value: type,
                  decoration: const InputDecoration(
                      labelText: 'Notification Type',
                      border: OutlineInputBorder()),
                  items: [
                    for (final t in AnnouncementType.values)
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (v) =>
                      setLocal(() => type = v ?? AnnouncementType.general),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlC,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Action Link (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: labelC,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Action Button Label (optional)',
                    hintText: type.defaultActionLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  activeColor: AppColors.primary,
                  title: const Text('Active'),
                  subtitle: Text(a.isForUsers
                      ? 'Visible to users'
                      : 'Visible to employees'),
                  onChanged: (v) => setLocal(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final title = titleC.text.trim();
    if (title.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Title is required')));
      }
      return;
    }
    await ref.read(announcementControllerProvider.notifier).update(a.id,
        title: title,
        message: msgC.text.trim(),
        isActive: active,
        type: type.key,
        actionUrl: urlC.text.trim(),
        actionLabel: labelC.text.trim());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification updated')));
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, AnnouncementModel a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Notification'),
        content: Text('Delete "${a.title}"? This cannot be undone.'),
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
    if (ok != true) return;
    await ref.read(announcementControllerProvider.notifier).delete(a.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Notification deleted')));
    }
  }

  static String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
