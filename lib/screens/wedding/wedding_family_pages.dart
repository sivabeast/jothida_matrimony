import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_section_pages.dart';

/// FAMILY MEMBERS — invite family by Gmail (they log in as Family Users and
/// join THEIR side's workspace), see invite status, remove members. Managed
/// by the couple or family members holding the invite/manage permissions.
class WeddingFamilyMembersPage extends StatelessWidget {
  const WeddingFamilyMembersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: 'Family Members',
      builder: (context, ref, wedding, identity) =>
          _FamilyMembersBody(wedding: wedding, identity: identity),
    );
  }
}

class _FamilyMembersBody extends ConsumerWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  const _FamilyMembersBody({required this.wedding, required this.identity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canInvite = identity.can(WeddingPermissions.inviteFamilyMembers);
    final canManage = identity.can(WeddingPermissions.manageFamilyMembers);
    final brideSide = wedding.members.where((m) => m.side == 'bride').toList();
    final groomSide = wedding.members.where((m) => m.side == 'groom').toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canInvite
          ? FloatingActionButton.extended(
              heroTag: 'wedding_family_fab',
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Invite'),
              onPressed: () => _showInviteSheet(context, ref),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Text(
              'Invited family members log in with their Gmail as Family '
              'Users. Bride-side members see the Bride + Shared workspaces; '
              'groom-side members see Groom + Shared — never the other side.',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
          ),
          const SizedBox(height: 14),
          _sideSection(context, ref, '👰 Bride Side', brideSide, canManage),
          const SizedBox(height: 16),
          _sideSection(context, ref, '🤵 Groom Side', groomSide, canManage),
        ],
      ),
    );
  }

  Widget _sideSection(BuildContext context, WidgetRef ref, String title,
      List<WeddingMember> members, bool canManage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                fontSize: 14.5)),
        const SizedBox(height: 8),
        if (members.isEmpty)
          Text('No family members invited.',
              style: TextStyle(color: Colors.grey[500], fontSize: 12.5))
        else
          ...members.map((m) => _memberTile(context, ref, m, canManage)),
      ],
    );
  }

  Widget _memberTile(BuildContext context, WidgetRef ref, WeddingMember m,
      bool canManage) {
    final joined = m.status == 'joined';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor:
                (m.side == 'groom' ? Colors.blue : AppColors.primary)
                    .withOpacity(0.12),
            child: Text(
              m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
              style: TextStyle(
                  color: m.side == 'groom' ? Colors.blue : AppColors.primary,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5)),
                Text('${m.relationship} · ${m.email}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: Colors.grey[600], fontSize: 11.5)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (joined ? AppColors.success : AppColors.warning)
                  .withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(joined ? 'Joined' : 'Invited',
                style: TextStyle(
                    color: joined ? AppColors.success : AppColors.warning,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold)),
          ),
          if (canManage)
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18, color: Colors.grey),
              onPressed: () => _confirmRemove(context, ref, m),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, WeddingMember m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove family member?'),
        content: Text('${m.name} (${m.email}) will lose access to this '
            'Wedding Workspace.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(weddingControllerProvider.notifier)
        .removeMember(wedding.id, m.email);
  }

  void _showInviteSheet(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String relationship = 'Father';
    // Family members invite into THEIR side; the couple can pick.
    String side = identity.side;
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
                const Text('Invite Family Member',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  'They log in with this Gmail as a Family User and join '
                  'their side\'s workspace directly.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameCtrl,
                  decoration: _input('Name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: relationship,
                  decoration: _input('Relationship'),
                  items: const [
                    'Father', 'Mother', 'Brother', 'Sister', 'Uncle', 'Others'
                  ]
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) =>
                      setSheetState(() => relationship = v ?? 'Others'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _input('Gmail'),
                  validator: (v) {
                    final email = (v ?? '').trim().toLowerCase();
                    if (email.isEmpty || !email.contains('@')) {
                      return 'Enter a valid Gmail address';
                    }
                    return null;
                  },
                ),
                if (identity.isSuperAdmin) ...[
                  const SizedBox(height: 12),
                  SideToggleInline(
                      side: side,
                      onChanged: (v) => setSheetState(() => side = v)),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Send Invitation'),
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(ctx);
                      final ok = await ref
                          .read(weddingControllerProvider.notifier)
                          .inviteMember(
                            wedding.id,
                            WeddingMember(
                              name: nameCtrl.text.trim(),
                              relationship: relationship,
                              email: emailCtrl.text.trim().toLowerCase(),
                              side: side,
                              invitedBy: identity.key,
                            ),
                          );
                      navigator.pop();
                      messenger.showSnackBar(SnackBar(
                          content: Text(ok
                              ? 'Invitation sent — ${emailCtrl.text.trim()} '
                                  'can now log in as a Family Member.'
                              : 'Could not send the invitation. The Gmail '
                                  'may already be invited.')));
                    },
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

// ── Permissions ───────────────────────────────────────────────────────────────

/// PERMISSIONS — the couple (Super Admins) grants each family member their
/// abilities. "All Permissions" selects everything at once.
class WeddingPermissionsPage extends StatelessWidget {
  const WeddingPermissionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: 'Permissions',
      builder: (context, ref, wedding, identity) {
        if (!identity.isSuperAdmin) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Only the Bride and Groom (Super Admins) manage permissions.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ),
          );
        }
        if (wedding.members.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No family members yet — invite them first from Family '
                'Members.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Tap a family member to configure exactly what they can do. '
              'The Bride and Groom always hold every permission.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            ...wedding.members.map((m) {
              final perms =
                  wedding.memberPermissions[weddingFieldKey(m.email)] ??
                      WeddingPermissions.defaults;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8),
                  ],
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: Text(
                        m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                        style: const TextStyle(color: AppColors.primary)),
                  ),
                  title: Text(m.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                      '${m.sideLabel} · ${m.relationship} · '
                      '${perms.length == WeddingPermissions.all.length ? 'All permissions' : '${perms.length} permission${perms.length == 1 ? '' : 's'}'}',
                      style: const TextStyle(fontSize: 11.5)),
                  trailing:
                      Icon(Icons.chevron_right, color: Colors.grey[400]),
                  onTap: () => _openMemberPermissions(
                      context, ref, wedding, m, perms),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  void _openMemberPermissions(BuildContext context, WidgetRef ref,
      WeddingModel wedding, WeddingMember member, List<String> current) {
    final selected = Set<String>.of(current);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final allSelected =
              selected.length == WeddingPermissions.all.length;
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            maxChildSize: 0.95,
            builder: (ctx, scrollCtrl) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Permissions — ${member.name}',
                                style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            Text(
                                '${member.sideLabel} · ${member.relationship}',
                                style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    children: [
                      // ☑ All Permissions — master toggle.
                      CheckboxListTile(
                        value: allSelected,
                        activeColor: AppColors.primary,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('All Permissions',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
                        subtitle: const Text(
                            'Select everything at once',
                            style: TextStyle(fontSize: 11.5)),
                        onChanged: (v) => setSheetState(() {
                          selected.clear();
                          if (v == true) {
                            selected.addAll(WeddingPermissions.all);
                          }
                        }),
                      ),
                      const Divider(height: 4),
                      ...WeddingPermissions.all.map(
                        (p) => CheckboxListTile(
                          value: selected.contains(p),
                          activeColor: AppColors.primary,
                          controlAffinity:
                              ListTileControlAffinity.leading,
                          dense: true,
                          title: Text(WeddingPermissions.label(p),
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600)),
                          onChanged: (v) => setSheetState(() => v == true
                              ? selected.add(p)
                              : selected.remove(p)),
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: () async {
                          final navigator = Navigator.of(ctx);
                          await ref
                              .read(weddingControllerProvider.notifier)
                              .setMemberPermissions(wedding.id,
                                  member.email, selected.toList());
                          navigator.pop();
                        },
                        child: const Text('Save Permissions'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Profile ───────────────────────────────────────────────────────────────────

/// PROFILE — the signed-in participant's workspace identity: name, role,
/// side and (for family members) the granted permissions.
class WeddingProfilePage extends StatelessWidget {
  const WeddingProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: 'Profile',
      builder: (context, ref, wedding, identity) {
        final user = ref.watch(currentUserProvider).valueOrNull;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: Text(
                      identity.name.isNotEmpty
                          ? identity.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(identity.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                          fontSize: 17)),
                  const SizedBox(height: 2),
                  Text(
                    identity.isSuperAdmin
                        ? '${identity.side == 'groom' ? 'Groom' : 'Bride'} · Super Admin'
                        : '${identity.sideLabel} · Family Member',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('Email', user?.email ?? '—'),
                  _row('Workspace Side',
                      identity.side == 'groom' ? 'Groom' : 'Bride'),
                  _row('Visible Workspaces',
                      '${identity.side == 'groom' ? 'Groom' : 'Bride'} + Shared'),
                  _row(
                      'Role',
                      identity.isSuperAdmin
                          ? 'Super Admin (full access)'
                          : 'Family Member'),
                ],
              ),
            ),
            if (!identity.isSuperAdmin) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('My Permissions',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    if (identity.permissions.isEmpty)
                      Text('No permissions granted yet.',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 12.5))
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: identity.permissions
                            .map((p) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.primary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(WeddingPermissions.label(p),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primary)),
                                ))
                            .toList(),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
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
