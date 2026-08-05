import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/astrologer_team_member.dart';
import '../../models/compatibility_report_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/astrology_team_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/firebase/astrologer_service.dart'
    show RequestClaimException;
import '../../widgets/common/data_states.dart';

/// Admin → **Requests** (spec §2).
///
/// This module lists HOROSCOPE REPORT REQUESTS only. Astrology appointment
/// bookings are a separate module (Admin → Appointments) and can never appear
/// here — the list is fed by [allReportRequestsProvider], which filters on
/// [AstrologerRequestModel.isReportRequest].
///
/// Two tabs, matching the Employee portal exactly:
///   • Pending   — every request that is not completed yet. Opening a card
///     shows Groom / Bride / Horoscope details and a Fill Report button.
///   • Completed — submitted reports, opened read-only.
class AdminHoroscopeRequestsScreen extends ConsumerWidget {
  const AdminHoroscopeRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allReportRequestsProvider);

    return async.when(
      loading: () => const LoadingState(message: 'Loading requests…'),
      error: (e, _) {
        debugPrint('[Requests] load failed: $e');
        return ErrorStateView(
          message: 'Connection Error — unable to load requests.',
          onRetry: () => ref.invalidate(allAstrologerRequestsProvider),
        );
      },
      data: (all) {
        final pending = all
            .where((r) => r.status != AstrologerRequestStatus.completed)
            .toList();
        final completed = all
            .where((r) => r.status == AstrologerRequestStatus.completed)
            .toList();

        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Horoscope Report Requests',
                        style: TextStyle(
                            fontSize: 20,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                        'Astrology appointments are managed separately under '
                        'Appointments.',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              Container(
                color: Colors.white,
                child: TabBar(
                  labelColor: AppColors.primary,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: AppColors.primary,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13.5),
                  tabs: [
                    Tab(text: 'Pending (${pending.length})'),
                    Tab(text: 'Completed (${completed.length})'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _RequestList(
                      requests: pending,
                      emptyMessage: 'No pending report requests',
                      onRefresh: () =>
                          ref.invalidate(allAstrologerRequestsProvider),
                    ),
                    _RequestList(
                      requests: completed,
                      emptyMessage: 'No completed reports yet',
                      onRefresh: () =>
                          ref.invalidate(allAstrologerRequestsProvider),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RequestList extends StatelessWidget {
  final List<AstrologerRequestModel> requests;
  final String emptyMessage;
  final VoidCallback onRefresh;

  const _RequestList({
    required this.requests,
    required this.emptyMessage,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: EmptyState(
            icon: Icons.menu_book_outlined, message: emptyMessage),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => onRefresh(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        itemCount: requests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _RequestCard(request: requests[i]),
      ),
    );
  }
}

String _waited(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} day${d.inDays == 1 ? '' : 's'}';
  if (d.inHours >= 1) return '${d.inHours} hr${d.inHours == 1 ? '' : 's'}';
  return '${d.inMinutes} min';
}

/// One request row. Tapping it opens the shared detail page (Groom / Bride /
/// Horoscope details + Fill Report); the inline actions stay for the admin-only
/// assignment workflow.
class _RequestCard extends ConsumerWidget {
  final AstrologerRequestModel request;
  const _RequestCard({required this.request});

  String get _matchName {
    final g = request.groomName ?? '—';
    final b = request.brideName ?? '—';
    return '$g & $b';
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

  static String _fmtDateTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${_fmtDate(d)} · ${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  ({Color color, String text}) get _statusBadge {
    final r = request;
    if (r.status == AstrologerRequestStatus.completed) {
      return (color: AppColors.success, text: 'COMPLETED');
    }
    if (r.status == AstrologerRequestStatus.rejected) {
      return (color: AppColors.error, text: 'REJECTED');
    }
    if (CompatibilityReport.tryFrom(r.compatReport) != null ||
        r.workflowStatus == 'in_progress') {
      return (color: const Color(0xFF2F80ED), text: 'IN PROGRESS');
    }
    if (r.assignedToAdmin) {
      return (color: const Color(0xFF7C5CFC), text: 'ASSIGNED TO ADMIN');
    }
    if (r.isAssigned) {
      return (color: Colors.deepPurple, text: 'ASSIGNED TO EMPLOYEE');
    }
    return (color: AppColors.warning, text: 'PENDING');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final badge = _statusBadge;
    final completed = r.status == AstrologerRequestStatus.completed;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/admin/request/${r.id}', extra: r),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(r.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14.5)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badge.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(badge.text,
                        style: TextStyle(
                            color: badge.color,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _line(Icons.favorite_border, 'Match', _matchName),
              _line(
                  r.assignedToAdmin
                      ? Icons.admin_panel_settings_outlined
                      : Icons.auto_awesome,
                  r.assignedToAdmin ? 'Admin' : 'Employee',
                  r.isAssigned
                      ? (r.astrologerName.isEmpty
                          ? r.astrologerEmail
                          : r.astrologerName)
                      : 'Unassigned'),
              _line(Icons.event_outlined, 'Requested', _fmtDate(r.createdAt)),
              if (!completed)
                _line(Icons.timelapse, 'Waiting',
                    _waited(DateTime.now().difference(r.createdAt)))
              else if (r.completedAt != null)
                _line(Icons.check_circle_outline, 'Completed',
                    _fmtDateTime(r.completedAt!)),
              const SizedBox(height: 10),
              if (completed)
                _elevatedBtn('View Submitted Report', Icons.visibility_outlined,
                    () => context.push('/admin/request/${r.id}', extra: r))
              else ...[
                Row(children: [
                  _outlinedBtn('Assign', Icons.person_add_alt,
                      () => _reassign(context, ref)),
                  const SizedBox(width: 10),
                  _elevatedBtn('Fill Report', Icons.edit_note,
                      () => _fillReport(context, ref)),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _outlinedBtn(String label, IconData icon, VoidCallback onTap) =>
      Expanded(
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 17),
          label: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5)),
          style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6)),
        ),
      );

  Widget _elevatedBtn(String label, IconData icon, VoidCallback onTap) =>
      Expanded(
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 17),
          label: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5)),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6)),
        ),
      );

  Widget _line(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 13, color: Colors.grey[500]),
            const SizedBox(width: 6),
            SizedBox(
                width: 74,
                child: Text(label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
            Expanded(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );

  /// "Fill Report" — claims the request for the signed-in ADMIN (moving it to
  /// In Progress via the guarded transaction) and opens the request detail
  /// page, where the structured compatibility report is filled in. A request
  /// someone else is mid-analysis on is blocked with a dialog instead.
  Future<void> _fillReport(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(matchAnalysisControllerProvider.notifier)
          .claimRequestForAdmin(request, startAnalysis: true);
    } on RequestClaimException catch (e) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Request Locked'),
          content: Text(e.alreadyCompleted
              ? 'This request is already completed.'
              : 'This request is being analyzed by '
                  '${e.holder.isEmpty ? 'another employee' : e.holder}.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not start the report: $e'),
          backgroundColor: AppColors.error));
      return;
    }
    if (!context.mounted) return;
    context.push('/admin/request/${request.id}', extra: request);
  }

  /// Assign / reassign the request to an ACTIVE astrology-team employee.
  Future<void> _reassign(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => Consumer(
        builder: (ctx, sheetRef, _) {
          final members =
              (sheetRef.watch(allAstrologerTeamProvider).valueOrNull ??
                      const <AstrologerTeamMember>[])
                  .where((m) => m.active && m.email != request.astrologerEmail)
                  .toList()
                ..sort((a, b) => a.email.compareTo(b.email));

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    request.isAssigned
                        ? 'Reassign to Employee'
                        : 'Assign to Employee',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('The request is set to New for the chosen employee.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 12),
                if (members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child:
                        Center(child: Text('No active employee available.')),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: members.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final m = members[i];
                        final name =
                            m.displayName.isEmpty ? m.email : m.displayName;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF7C5CFC)
                                .withValues(alpha: 0.12),
                            backgroundImage: m.photoUrl.isNotEmpty
                                ? NetworkImage(m.photoUrl)
                                : null,
                            child: m.photoUrl.isEmpty
                                ? Text(name[0].toUpperCase(),
                                    style: const TextStyle(
                                        color: Color(0xFF7C5CFC),
                                        fontWeight: FontWeight.bold))
                                : null,
                          ),
                          title: Text(name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${m.email} · ${m.statusLabel}',
                              style: const TextStyle(fontSize: 12)),
                          onTap: () async {
                            Navigator.pop(sheetCtx);
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await sheetRef
                                  .read(astrologyTeamServiceProvider)
                                  .assignToAstrologer(request.id, m);
                              messenger.showSnackBar(SnackBar(
                                  content: Text('Assigned to $name.')));
                            } catch (e) {
                              messenger.showSnackBar(SnackBar(
                                  content: Text('Could not assign: $e'),
                                  backgroundColor: AppColors.error));
                            }
                          },
                        );
                      },
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
