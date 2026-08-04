import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/astrologer_team_member.dart';
import '../../providers/admin_provider.dart';
import '../../providers/astrology_team_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/firebase/astrologer_service.dart'
    show RequestClaimException;
import '../../widgets/common/data_states.dart';
import '../report/compatibility_report_screen.dart';

/// Admin → Horoscope Requests (bottom-nav). Manages the astrologer
/// match-analysis / consultation request queue: summary counts, status
/// filters, a "Need Attention" section for long-pending requests, and per-row
/// admin actions (Send Reminder, Reassign Astrologer, plus the spec §11 admin
/// self-analysis: Assign to Me / Analyze as Admin).
class AdminHoroscopeRequestsScreen extends ConsumerStatefulWidget {
  const AdminHoroscopeRequestsScreen({super.key});

  @override
  ConsumerState<AdminHoroscopeRequestsScreen> createState() =>
      _AdminHoroscopeRequestsScreenState();
}

/// The FIVE display states an admin distinguishes (spec §11). `rejected`
/// requests keep their red badge but bucket by assignment for the filters.
enum _ReqState { pending, assignedEmployee, assignedAdmin, inProgress, completed }

_ReqState _stateOf(AstrologerRequestModel r) {
  if (r.status == AstrologerRequestStatus.completed) return _ReqState.completed;
  if (r.workflowStatus == 'in_progress') return _ReqState.inProgress;
  if (r.assignedToAdmin) return _ReqState.assignedAdmin;
  if (r.isAssigned) return _ReqState.assignedEmployee;
  return _ReqState.pending;
}

enum _ReqFilter {
  all,
  // Truly unassigned requests — never reached an employee (auto-assignment
  // found no one / was rejected) and not claimed by the admin. These are
  // invisible on every employee's Pending Reports page until someone takes
  // them, so they get their own filter rather than being buried in "All".
  pending,
  assignedEmployee,
  assignedAdmin,
  inProgress,
  completed,
  reassigned,
}

extension on _ReqFilter {
  String get label => switch (this) {
        _ReqFilter.all => 'All',
        _ReqFilter.pending => 'Pending',
        _ReqFilter.assignedEmployee => 'Assigned to Employee',
        _ReqFilter.assignedAdmin => 'Assigned to Admin',
        _ReqFilter.inProgress => 'In Progress',
        _ReqFilter.completed => 'Completed',
        _ReqFilter.reassigned => 'Reassigned',
      };
}

class _AdminHoroscopeRequestsScreenState
    extends ConsumerState<AdminHoroscopeRequestsScreen> {
  _ReqFilter _filter = _ReqFilter.all;

  bool _matches(AstrologerRequestModel r) => switch (_filter) {
        _ReqFilter.all => true,
        _ReqFilter.pending => _stateOf(r) == _ReqState.pending,
        _ReqFilter.assignedEmployee =>
          _stateOf(r) == _ReqState.assignedEmployee,
        _ReqFilter.assignedAdmin => _stateOf(r) == _ReqState.assignedAdmin,
        _ReqFilter.inProgress => _stateOf(r) == _ReqState.inProgress,
        _ReqFilter.completed => _stateOf(r) == _ReqState.completed,
        _ReqFilter.reassigned => r.reassigned,
      };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allAstrologerRequestsProvider);

    return async.when(
      loading: () => const LoadingState(message: 'Loading requests…'),
      error: (e, _) {
        debugPrint('[HoroscopeRequests] load failed: $e');
        return ErrorStateView(
          message: 'Connection Error — unable to load requests.',
          onRetry: () => ref.invalidate(allAstrologerRequestsProvider),
        );
      },
      data: (all) {
        final now = DateTime.now();
        final total = all.length;
        var pending = 0;
        var assignedEmployee = 0;
        var assignedAdmin = 0;
        var inProgress = 0;
        var completed = 0;
        for (final r in all) {
          switch (_stateOf(r)) {
            case _ReqState.pending:
              pending++;
            case _ReqState.assignedEmployee:
              assignedEmployee++;
            case _ReqState.assignedAdmin:
              assignedAdmin++;
            case _ReqState.inProgress:
              inProgress++;
            case _ReqState.completed:
              completed++;
          }
        }

        // Need-attention: pending > 24h, grouped by astrologer.
        final stale = all
            .where((r) =>
                r.status == AstrologerRequestStatus.pending &&
                now.difference(r.createdAt).inHours >= 24)
            .toList();
        final grouped = <String, ({int count, Duration maxWait})>{};
        for (final r in stale) {
          final key = r.astrologerName.isEmpty ? 'Unassigned' : r.astrologerName;
          final wait = now.difference(r.createdAt);
          final cur = grouped[key];
          grouped[key] = (
            count: (cur?.count ?? 0) + 1,
            maxWait: (cur == null || wait > cur.maxWait) ? wait : cur.maxWait,
          );
        }

        final shown = all.where(_matches).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            const Text('Horoscope Requests',
                style: TextStyle(
                    fontSize: 22,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),

            // Summary cards (2×3) — one per display state + total.
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.5,
              children: [
                _SummaryTile('Total Requests', total, Icons.list_alt,
                    AppColors.primary),
                _SummaryTile('Pending (Unassigned)', pending,
                    Icons.hourglass_top, AppColors.warning),
                _SummaryTile('Assigned to Employee', assignedEmployee,
                    Icons.group_outlined, Colors.deepPurple),
                _SummaryTile('Assigned to Admin', assignedAdmin,
                    Icons.admin_panel_settings_outlined,
                    const Color(0xFF7C5CFC)),
                _SummaryTile('In Progress', inProgress, Icons.sync,
                    const Color(0xFF2F80ED)),
                _SummaryTile('Completed', completed, Icons.check_circle,
                    AppColors.success),
              ],
            ),
            const SizedBox(height: 16),

            // Filters.
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final f in _ReqFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f.label),
                        selected: _filter == f,
                        showCheckmark: false,
                        selectedColor: AppColors.primary.withValues(alpha: 0.14),
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: _filter == f
                              ? AppColors.primary
                              : Colors.black87,
                          fontWeight: _filter == f
                              ? FontWeight.w600
                              : FontWeight.normal,
                          fontSize: 12.5,
                        ),
                        side: BorderSide(
                            color: _filter == f
                                ? AppColors.primary
                                : Colors.grey[300]!),
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Need attention.
            if (grouped.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.error, size: 18),
                  const SizedBox(width: 6),
                  Text('Need Attention',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[850])),
                ],
              ),
              const SizedBox(height: 8),
              for (final e in grouped.entries)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.priority_high,
                          color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${e.key} — ${e.value.count} request${e.value.count == 1 ? '' : 's'} '
                          'pending for ${_waited(e.value.maxWait)}',
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
            ],

            // Request list.
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: EmptyState(
                    icon: Icons.menu_book_outlined,
                    message: 'No requests in this filter'),
              )
            else
              for (final r in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RequestCard(request: r),
                ),
          ],
        );
      },
    );
  }
}

String _waited(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} day${d.inDays == 1 ? '' : 's'}';
  if (d.inHours >= 1) return '${d.inHours} hr${d.inHours == 1 ? '' : 's'}';
  return '${d.inMinutes} min';
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  const _SummaryTile(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, height: 1.1)),
                Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends ConsumerWidget {
  final AstrologerRequestModel request;
  const _RequestCard({required this.request});

  String get _matchName {
    if (request.isMatchAnalysis) {
      final g = request.groomName ?? '—';
      final b = request.brideName ?? '—';
      return '$g & $b';
    }
    return request.type.label;
  }

  ({Color color, String text}) get _statusBadge {
    if (request.status == AstrologerRequestStatus.rejected) {
      return (color: AppColors.error, text: 'REJECTED');
    }
    return switch (_stateOf(request)) {
      _ReqState.pending => (color: AppColors.warning, text: 'PENDING'),
      _ReqState.assignedEmployee => (
          color: Colors.deepPurple,
          text: 'ASSIGNED TO EMPLOYEE'
        ),
      _ReqState.assignedAdmin => (
          color: const Color(0xFF7C5CFC),
          text: 'ASSIGNED TO ADMIN'
        ),
      _ReqState.inProgress => (
          color: const Color(0xFF2F80ED),
          text: 'IN PROGRESS'
        ),
      _ReqState.completed => (
          color: AppColors.success,
          text: 'COMPLETED'
        ),
    };
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

  /// "Completed by Admin (email) on 02-08-2026 · 05:12 PM" — shown on
  /// completed cards once the submit stamp exists (legacy docs show nothing).
  String get _completedByText {
    final who = request.completedByRole == 'admin' ? 'Admin' : 'Employee';
    final email = request.completedByEmail.isNotEmpty
        ? ' (${request.completedByEmail})'
        : '';
    final when = request.completedAt != null
        ? ' on ${_fmtDateTime(request.completedAt!)}'
        : '';
    return 'Completed by $who$email$when';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badge = _statusBadge;
    final state = _stateOf(request);
    final myUid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid ?? '';
    final waiting = _waited(DateTime.now().difference(request.createdAt));
    final actions = _actionRows(context, ref, state, myUid);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(request.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14.5)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              if (request.reassigned) ...[
                const SizedBox(width: 6),
                const Icon(Icons.swap_horiz, size: 16, color: Colors.deepPurple),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _line(Icons.favorite_border, 'Match', _matchName),
          if (request.isAssigned) ...[
            _line(
                request.assignedToAdmin
                    ? Icons.admin_panel_settings_outlined
                    : Icons.auto_awesome,
                request.assignedToAdmin ? 'Admin' : 'Astrologer',
                request.astrologerName),
            _line(Icons.alternate_email, 'Gmail', request.astrologerEmail),
            if (request.assignedAt != null)
              _line(Icons.schedule, 'Assigned',
                  _fmtDateTime(request.assignedAt!)),
          ] else
            _line(Icons.auto_awesome, 'Astrologer', 'Unassigned'),
          _line(Icons.info_outline, 'Status', badge.text),
          _line(Icons.event_outlined, 'Requested', _fmtDate(request.createdAt)),
          _line(Icons.timelapse, 'Waiting', waiting),
          if (state == _ReqState.completed &&
              (request.completedBy.isNotEmpty ||
                  request.completedByEmail.isNotEmpty)) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_completedByText,
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w500)),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...actions,
          ],
        ],
      ),
    );
  }

  /// Per-state action rows (spec §11):
  ///  • Pending      → Auto Assign / Assign  +  Assign to Me / Analyze as Admin
  ///  • Employee     → Reminder / Reassign   +  Assign to Me / Analyze as Admin
  ///  • Admin        → Reassign / Analyze
  ///  • In Progress  → (mine) Reassign / Analyze — (someone else) Reminder /
  ///    Reassign; the claim transaction + dialog block a takeover mid-analysis.
  ///  • Completed    → no actions.
  List<Widget> _actionRows(
      BuildContext context, WidgetRef ref, _ReqState state, String myUid) {
    switch (state) {
      case _ReqState.completed:
        return const [];
      case _ReqState.pending:
        return [
          Row(children: [
            _outlinedBtn('Auto Assign', Icons.autorenew,
                () => _autoAssign(context, ref)),
            const SizedBox(width: 10),
            _elevatedBtn(
                'Assign', Icons.person_add_alt, () => _reassign(context, ref)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _outlinedBtn('Assign to Me', Icons.how_to_reg_outlined,
                () => _assignToMe(context, ref)),
            const SizedBox(width: 10),
            _elevatedBtn('Analyze as Admin', Icons.edit_note,
                () => _analyzeAsAdmin(context, ref)),
          ]),
        ];
      case _ReqState.assignedEmployee:
        return [
          Row(children: [
            _outlinedBtn('Reminder', Icons.notifications_active_outlined,
                () => _sendReminder(context, ref)),
            const SizedBox(width: 10),
            _elevatedBtn(
                'Reassign', Icons.swap_horiz, () => _reassign(context, ref)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _outlinedBtn('Assign to Me', Icons.how_to_reg_outlined,
                () => _assignToMe(context, ref)),
            const SizedBox(width: 10),
            _elevatedBtn('Analyze as Admin', Icons.edit_note,
                () => _analyzeAsAdmin(context, ref)),
          ]),
        ];
      case _ReqState.assignedAdmin:
        return [
          Row(children: [
            _outlinedBtn(
                'Reassign', Icons.swap_horiz, () => _reassign(context, ref)),
            const SizedBox(width: 10),
            _elevatedBtn(
                'Analyze', Icons.edit_note, () => _analyzeAsAdmin(context, ref)),
          ]),
        ];
      case _ReqState.inProgress:
        if (request.astrologerId.isNotEmpty && request.astrologerId == myUid) {
          // The signed-in ADMIN is the one analyzing — continue the report.
          return [
            Row(children: [
              _outlinedBtn(
                  'Reassign', Icons.swap_horiz, () => _reassign(context, ref)),
              const SizedBox(width: 10),
              _elevatedBtn('Analyze', Icons.edit_note,
                  () => _analyzeAsAdmin(context, ref)),
            ]),
          ];
        }
        return [
          Row(children: [
            _outlinedBtn('Reminder', Icons.notifications_active_outlined,
                () => _sendReminder(context, ref)),
            const SizedBox(width: 10),
            _elevatedBtn(
                'Reassign', Icons.swap_horiz, () => _reassign(context, ref)),
          ]),
        ];
    }
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

  String _fmtDateTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${_fmtDate(d)} · ${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

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

  /// "Assign to Me" — claims the request for the signed-in ADMIN via the
  /// guarded transaction; a lost race / already-in-progress request surfaces a
  /// friendly SnackBar naming whoever holds it.
  Future<void> _assignToMe(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(matchAnalysisControllerProvider.notifier)
          .claimRequestForAdmin(request);
      messenger.showSnackBar(const SnackBar(
          content: Text('Request assigned to you (Admin).')));
    } on RequestClaimException catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('$e'), backgroundColor: AppColors.error));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not assign: $e'),
          backgroundColor: AppColors.error));
    }
  }

  /// "Analyze (as Admin)" — claims the request if needed, moves it to
  /// In Progress (same guarded transaction) and opens the EXISTING structured
  /// compat-report form the employee portal uses. If someone else is
  /// mid-analysis the takeover is blocked with a dialog instead.
  Future<void> _analyzeAsAdmin(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
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
                  '${e.holder.isEmpty ? 'another astrologer' : e.holder}.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK')),
          ],
        ),
      );
      return;
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not start analysis: $e'),
          backgroundColor: AppColors.error));
      return;
    }
    // Open the SAME analysis form the employee portal uses
    // (astrologer_request_detail_page._compatReportCard) — employee mode makes
    // it the editable structured A4 report with Save Draft + Submit.
    navigator.push(MaterialPageRoute(
      builder: (_) => CompatibilityReportScreen(
        requestId: request.id,
        request: request,
        employee: true,
      ),
    ));
  }

  Future<void> _sendReminder(BuildContext context, WidgetRef ref) async {
    if (request.astrologerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No astrologer assigned to remind.')));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(adminActionsProvider.notifier)
        .sendRequestReminder(request.astrologerId);
    final st = ref.read(adminActionsProvider);
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not send reminder.'
          : 'Reminder sent to ${request.astrologerName}.'),
      backgroundColor: st.hasError ? AppColors.error : null,
    ));
  }

  /// Round-robin auto-assign (spec) — distributes evenly across active +
  /// available astrologers using the stored last-assigned rotation.
  Future<void> _autoAssign(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final chosen = await ref
          .read(astrologyTeamServiceProvider)
          .assignRequest(request.id);
      messenger.showSnackBar(SnackBar(
        content: Text(chosen == null
            ? 'No active astrologer available.'
            : 'Auto-assigned to ${chosen.displayName.isEmpty ? chosen.email : chosen.displayName}.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not auto-assign: $e'),
          backgroundColor: AppColors.error));
    }
  }

  Future<void> _reassign(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => Consumer(
        builder: (ctx, sheetRef, _) {
          // Reassign targets the ACTIVE astrology team (excluding the current
          // assignee), so it always matches the real astrologer roster.
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
                        ? 'Reassign to Astrologer'
                        : 'Assign to Astrologer',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('The request is set to New for the chosen astrologer.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 12),
                if (members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                        child: Text('No active astrologer available.')),
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
                        final name = m.displayName.isEmpty
                            ? m.email
                            : m.displayName;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor:
                                const Color(0xFF7C5CFC).withValues(alpha: 0.12),
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
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text('${m.email} · ${m.statusLabel}',
                              style: const TextStyle(fontSize: 12)),
                          onTap: () async {
                            Navigator.pop(sheetCtx);
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await ref
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
