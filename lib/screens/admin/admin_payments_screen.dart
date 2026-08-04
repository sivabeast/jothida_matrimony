import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/common/data_states.dart';
import 'admin_export.dart' show inr;

/// Time-range filter for the transactions list. "This Week" starts on Monday,
/// matching the analytics pass in FirestoreService.getDashboardAnalytics.
enum _PayFilter { all, today, week, month }

extension on _PayFilter {
  String get label => switch (this) {
        _PayFilter.all => 'All',
        _PayFilter.today => 'Today',
        _PayFilter.week => 'This Week',
        _PayFilter.month => 'This Month',
      };
}

/// Admin → Payments → Transactions: every `astrologer_requests` booking with
/// `paid == true`, newest payment first. Live via
/// [paidAstrologerRequestsProvider], with name search + time-range filters and
/// a revenue summary header that reflects the current selection.
class AdminPaymentsScreen extends ConsumerStatefulWidget {
  const AdminPaymentsScreen({super.key});

  @override
  ConsumerState<AdminPaymentsScreen> createState() =>
      _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends ConsumerState<AdminPaymentsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _PayFilter _filter = _PayFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime _paidDate(AstrologerRequestModel r) => r.paidAt ?? r.createdAt;

  List<AstrologerRequestModel> _apply(List<AstrologerRequestModel> list) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    var out = switch (_filter) {
      _PayFilter.all => list,
      _PayFilter.today =>
        list.where((r) => !_paidDate(r).isBefore(todayStart)).toList(),
      _PayFilter.week =>
        list.where((r) => !_paidDate(r).isBefore(weekStart)).toList(),
      _PayFilter.month =>
        list.where((r) => !_paidDate(r).isBefore(monthStart)).toList(),
    };
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((r) => r.userName.toLowerCase().contains(q)).toList();
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final paidAsync = ref.watch(paidAstrologerRequestsProvider);

    return paidAsync.when(
      loading: () => const LoadingState(message: 'Loading transactions...'),
      error: (e, _) => ErrorStateView(
        message: 'Connection Error — unable to load transactions.',
        onRetry: () => ref.invalidate(allAstrologerRequestsProvider),
      ),
      data: (all) {
        final rows = _apply(all);
        final total = rows.fold<int>(0, (s, r) => s + r.amount);

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(allAstrologerRequestsProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              const Text('Transactions',
                  style: TextStyle(
                      fontSize: 24,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('All paid orders — live',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              const SizedBox(height: 16),
              _SummaryCard(
                total: total,
                count: rows.length,
                scope: _filter.label,
              ),
              const SizedBox(height: 14),
              _searchField(),
              const SizedBox(height: 10),
              _filterChips(),
              const SizedBox(height: 14),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: 'No transactions found'),
                )
              else
                for (final r in rows) ...[
                  _TransactionCard(request: r),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        );
      },
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        hintText: 'Search by name…',
        hintStyle: TextStyle(fontSize: 13.5, color: Colors.grey[500]),
        prefixIcon: Icon(Icons.search, color: Colors.grey[500], size: 20),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close, color: Colors.grey[500], size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
    );
  }

  Widget _filterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in _PayFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f.label, style: const TextStyle(fontSize: 12)),
                selected: _filter == f,
                showCheckmark: false,
                selectedColor: AppColors.primary.withValues(alpha: 0.14),
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: _filter == f ? AppColors.primary : Colors.black87,
                  fontWeight:
                      _filter == f ? FontWeight.w600 : FontWeight.normal,
                ),
                side: BorderSide(
                    color:
                        _filter == f ? AppColors.primary : Colors.grey[300]!),
                onSelected: (_) => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }
}

/// Gradient revenue summary for the current filter selection.
class _SummaryCard extends StatelessWidget {
  final int total;
  final int count;
  final String scope;
  const _SummaryCard(
      {required this.total, required this.count, required this.scope});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [
              AppColors.primary,
              AppColors.primary.withValues(alpha: 0.75)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.payments_outlined,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(inr(total),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        height: 1.1)),
                const Text('Total Revenue',
                    style: TextStyle(color: Colors.white, fontSize: 13.5)),
                Text(
                    '$count transaction${count == 1 ? '' : 's'} · $scope',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One paid transaction row: user, type/date/payment id, amount + status.
class _TransactionCard extends StatelessWidget {
  final AstrologerRequestModel request;
  const _TransactionCard({required this.request});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _dateLabel {
    final d = request.paidAt ?? request.createdAt;
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day} ${_months[d.month - 1]} ${d.year} · '
        '$h:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  String get _typeLabel {
    if (request.isExternalReport) return 'External Report';
    if (request.hasAppointment) return 'Appointment';
    return request.type.label;
  }

  String get _paymentIdLabel {
    final id = request.paymentId;
    if (id.isEmpty) return '';
    return id.length <= 18 ? id : '${id.substring(0, 18)}…';
  }

  (String, Color) get _status => switch (request.displayBucket) {
        'completed' => ('Completed', AppColors.success),
        'inProgress' => ('In Progress', AppColors.info),
        'accepted' => ('Accepted', AppColors.info),
        'rejected' => ('Rejected', AppColors.error),
        'expired' => ('Expired', Colors.grey),
        _ => ('Pending', AppColors.warning),
      };

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = _status;
    final name = request.userName.isEmpty ? 'User' : request.userName;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.10),
            child: Text(name[0].toUpperCase(),
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('$_typeLabel · $_dateLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                if (_paymentIdLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('Payment ID: $_paymentIdLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 10.5, color: Colors.grey[500])),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(inr(request.amount),
                  style: const TextStyle(
                      fontSize: 15,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: statusColor)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
