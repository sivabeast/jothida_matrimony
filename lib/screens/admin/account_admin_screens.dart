import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/dev_config.dart';
import '../../core/theme/app_colors.dart';
import '../../models/account_deletion_request_model.dart';
import '../../providers/account_provider.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/data_states.dart';

/// True if the viewer may manage account deletions (Super Admin only; demo mode
/// bypasses auth for local testing).
bool _isSuperAdmin(WidgetRef ref) =>
    kBypassAuth ||
    (ref.watch(currentUserProvider).valueOrNull?.isSuperAdmin ?? false);

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

// ─────────────────────────────────────────────────────────────────────────────
// Account Deletion Requests (Super Admin only)
// ─────────────────────────────────────────────────────────────────────────────

class AccountDeletionRequestsScreen extends ConsumerWidget {
  const AccountDeletionRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[Admin] AccountDeletionRequests build — /admin/deletion-requests');

    if (!_isSuperAdmin(ref)) return const _AccessDenied();

    final reqsAsync = ref.watch(deletionRequestsProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Account Deletion Requests'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: reqsAsync.when(
        loading: () => const LoadingState(),
        error: (e, _) {
          debugPrint('[Admin] deletion requests load failed: $e');
          return const ErrorStateView(
              message: 'Unable to load deletion requests. Please try again.');
        },
        data: (reqs) {
          if (reqs.isEmpty) {
            return const _Empty(
              icon: Icons.inbox_outlined,
              message: 'No account deletion requests.',
            );
          }
          final pending = reqs.where((r) => r.status == 'pending').length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (pending > 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Text('🔔', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$pending pending request${pending == 1 ? '' : 's'} awaiting review',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ...reqs.map((r) => _RequestCard(
                    request: r,
                    onApprove: () => _approve(context, ref, r),
                    onReject: () => _reject(context, ref, r),
                  )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _approve(
      BuildContext context, WidgetRef ref, AccountDeletionRequest r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Deletion'),
        content: Text(
            'This permanently deletes ${r.userName}\'s profile, interests and '
            'related data. This cannot be undone. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(accountControllerProvider.notifier).approveDeletion(r);
    messenger.showSnackBar(const SnackBar(
        content: Text('Account data deleted and request approved.')));
  }

  Future<void> _reject(
      BuildContext context, WidgetRef ref, AccountDeletionRequest r) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(accountControllerProvider.notifier).rejectDeletion(r);
    messenger.showSnackBar(const SnackBar(
        content: Text('Request rejected. The account remains active.')));
  }
}

class _RequestCard extends StatelessWidget {
  final AccountDeletionRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  const _RequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final r = request;
    final pending = r.status == 'pending';
    final statusColor = r.status == 'approved'
        ? AppColors.success
        : r.status == 'rejected'
            ? Colors.grey
            : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.userName.isEmpty ? '(no name)' : r.userName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        fontFamily: 'Poppins')),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(r.status.toUpperCase(),
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _row(Icons.email_outlined, r.email),
          _row(Icons.badge_outlined, 'User ID: ${r.userId}'),
          _row(Icons.event_outlined, 'Requested: ${_fmtDate(r.requestDate)}'),
          if (pending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[800],
                        side: BorderSide(color: Colors.grey[400]!)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Expanded(
                child: Text(text,
                    style: TextStyle(color: Colors.grey[700], fontSize: 12.5))),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Married Users + marriage statistics
// ─────────────────────────────────────────────────────────────────────────────

class MarriedUsersScreen extends ConsumerWidget {
  const MarriedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[Admin] MarriedUsers build — /admin/married');
    final marriedAsync = ref.watch(marriedProfilesProvider);
    final stats = ref.watch(adminStatsProvider).valueOrNull ?? const {};
    final totalMarried = stats['marriedUsers'] ?? 0;
    final totalProfiles = (stats['totalProfiles'] ?? 0) as int;
    final successRate = (totalProfiles > 0 && totalMarried is int)
        ? ((totalMarried / totalProfiles) * 100).toStringAsFixed(1)
        : '0.0';

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Married Users'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                  child: _statTile('Total Married', '$totalMarried',
                      Icons.celebration, AppColors.gold)),
              const SizedBox(width: 12),
              Expanded(
                  child: _statTile('Success Rate', '$successRate%',
                      Icons.favorite, AppColors.primary)),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Recently Married',
              style: TextStyle(
                  fontSize: 15,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          const SizedBox(height: 10),
          marriedAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: LoadingState(),
            ),
            error: (e, _) {
              debugPrint('[Admin] married users load failed: $e');
              return const Padding(
                padding: EdgeInsets.all(24),
                child: ErrorStateView(
                    message: 'Unable to load married users. Please try again.'),
              );
            },
            data: (list) {
              if (list.isEmpty) {
                return const _Empty(
                  icon: Icons.favorite_border,
                  message: 'No married users yet.',
                );
              }
              return Column(
                children: list
                    .map((p) => Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0x22D4AF37),
                              child: Text('🎉', style: TextStyle(fontSize: 18)),
                            ),
                            title: Text(p.name),
                            subtitle: Text(
                                '${p.age} yrs • ${p.city.isEmpty ? '—' : p.city}'),
                            trailing: const Icon(Icons.verified,
                                color: AppColors.gold, size: 18),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared
// ─────────────────────────────────────────────────────────────────────────────

class _AccessDenied extends StatelessWidget {
  const _AccessDenied();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Restricted'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: const _Empty(
        icon: Icons.lock_outline,
        message: 'Only a Super Admin can access this page.',
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String message;
  const _Empty({required this.icon, required this.message});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.primary.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
