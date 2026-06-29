import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/astrologer_team_member.dart';
import '../../providers/astrology_team_provider.dart';
import '../../providers/service_providers.dart';

/// Admin → Astrologer Accounts (spec §6).
///
/// The admin provisions astrologers by Gmail only — no passwords. An account is
/// "Awaiting sign-in" until the astrologer first logs in with Google; the
/// Active switch enables/disables them for login AND auto-assignment instantly.
class AstrologerAccountsScreen extends ConsumerWidget {
  const AstrologerAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allAstrologerTeamProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _addDialog(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add Astrologer'),
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => const Center(
            child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Could not load astrologer accounts.'),
        )),
        data: (members) {
          if (members.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_outlined,
                        size: 56, color: AppColors.primary),
                    SizedBox(height: 12),
                    Text('No astrologer accounts yet.\n'
                        'Tap "Add Astrologer" to register one by Gmail.',
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
            itemCount: members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _MemberCard(member: members[i]),
          );
        },
      ),
    );
  }

  Future<void> _addDialog(BuildContext context, WidgetRef ref) async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Astrologer'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Gmail address',
                  hintText: 'astrologer@gmail.com',
                ),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Enter a Gmail address';
                  if (!s.contains('@') || !s.contains('.')) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Display name (optional)',
                ),
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
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (added == true) {
      try {
        await ref.read(astrologyTeamServiceProvider).addMember(
              email: emailCtrl.text,
              displayName: nameCtrl.text,
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Astrologer registered. They can now sign in '
                  'with Google using that Gmail.')));
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Could not add astrologer. Please try again.')));
        }
      }
    }
  }
}

class _MemberCard extends ConsumerWidget {
  final AstrologerTeamMember member;
  const _MemberCard({required this.member});

  Color get _statusColor {
    if (!member.active) return Colors.red;
    return member.isLinked ? Colors.green : Colors.orange;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(astrologyTeamServiceProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            backgroundImage:
                member.photoUrl.isNotEmpty ? NetworkImage(member.photoUrl) : null,
            child: member.photoUrl.isEmpty
                ? const Icon(Icons.person, color: AppColors.primary)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName.isEmpty ? member.email : member.displayName,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                Text(member.email,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(member.statusLabel,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _statusColor)),
                    ),
                    const SizedBox(width: 8),
                    Text('Pending: ${member.pendingCount}',
                        style:
                            TextStyle(fontSize: 11.5, color: Colors.grey[700])),
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              Switch(
                value: member.active,
                activeColor: AppColors.primary,
                onChanged: (v) => svc.setActive(member.id, v),
              ),
              InkWell(
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Remove astrologer?'),
                      content: Text(
                          'Remove ${member.displayName.isEmpty ? member.email : member.displayName}? '
                          'They will no longer be able to sign in. Existing '
                          'requests are not deleted.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel')),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.error),
                            child: const Text('Remove')),
                      ],
                    ),
                  );
                  if (ok == true) svc.removeMember(member.id);
                },
                child: Text('Remove',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
