import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/blocked_entry.dart';
import '../../providers/block_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/network_photo.dart';

/// User-facing Blocked Users page (spec §6). Lists everyone the signed-in user
/// has blocked — photo, name, age, location, block date — each with an Unblock
/// action. Unblocking re-enables matches/search/interests/chat for that user
/// immediately (the blocks stream is live).
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final blocksAsync = ref.watch(myBlocksProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.blockedUsers),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: blocksAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) =>
            _EmptyState(icon: Icons.block, text: l10n.noBlockedUsers),
        data: (blocks) {
          if (blocks.isEmpty) {
            return _EmptyState(icon: Icons.block, text: l10n.noBlockedUsers);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: blocks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _BlockedCard(entry: blocks[i]),
          );
        },
      ),
    );
  }
}

class _BlockedCard extends ConsumerWidget {
  final BlockedEntry entry;
  const _BlockedCard({required this.entry});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  String _fmt(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final profile = ref.watch(profileByUserIdProvider(entry.uid)).valueOrNull;
    final name = profile?.name ?? l10n.member;
    final age = profile?.age ?? 0;
    final location = profile == null
        ? ''
        : [profile.city, profile.state]
            .where((s) => s.trim().isNotEmpty)
            .join(', ');
    final photo = profile?.profilePhotoUrl ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 56,
              height: 56,
              child: NetworkPhoto(url: photo, fallbackIconSize: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(age > 0 ? '$name, $age' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        fontFamily: 'Poppins')),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  _meta(Icons.location_on_outlined, location),
                ],
                if (entry.blockedAt != null) ...[
                  const SizedBox(height: 3),
                  _meta(Icons.block,
                      '${l10n.blockedLabel} · ${_fmt(entry.blockedAt!)}'),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmUnblock(context, ref),
                    icon: const Icon(Icons.lock_open, size: 17),
                    label: Text(l10n.unblock),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 13, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
          ),
        ],
      );

  Future<void> _confirmUnblock(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.unblock),
        content: Text(l10n.unblockConfirmMsg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.unblock),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(blockControllerProvider.notifier).unblock(entry.uid);
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
