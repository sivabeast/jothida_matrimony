import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../providers/match_analysis_provider.dart';
import '../../astrologer/my_match_analysis_screen.dart';

/// Reports tab (bottom-nav item 5) — the user's Horoscope Compatibility Reports.
///
/// Two sections only (no booking terminology): **Under Analysis** (still being
/// prepared) and **Completed Reports** (delivered). Cards are reused from
/// [MatchAnalysisBookingCard], which exposes View Report · Download PDF · Open
/// Analysis Chat on completed reports.
class ReportsTab extends ConsumerStatefulWidget {
  const ReportsTab({super.key});

  @override
  ConsumerState<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<ReportsTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myMatchAnalysisRequestsProvider);
    final all = async.valueOrNull ?? const <AstrologerRequestModel>[];
    final loading = async.isLoading;
    final hasError = async.hasError;

    final sorted = [...all]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final underAnalysis = sorted
        .where((r) => r.status != AstrologerRequestStatus.completed)
        .toList();
    final completed = sorted
        .where((r) => r.status == AstrologerRequestStatus.completed)
        .toList();

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          alignment: Alignment.centerLeft,
          child: const Text('Reports',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
        ),
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tab,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
            tabs: [
              Tab(text: 'Under Analysis (${underAnalysis.length})'),
              Tab(text: 'Completed Reports (${completed.length})'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _list(
                underAnalysis,
                loading: loading,
                hasError: hasError,
                emptyIcon: Icons.hourglass_empty,
                emptyText: 'No reports under analysis yet',
              ),
              _list(
                completed,
                loading: loading,
                hasError: hasError,
                emptyIcon: Icons.verified_outlined,
                emptyText: 'No completed reports yet',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _list(
    List<AstrologerRequestModel> reports, {
    required bool loading,
    required bool hasError,
    required IconData emptyIcon,
    required String emptyText,
  }) {
    if (reports.isEmpty) {
      if (loading) {
        return const Center(
            child: CircularProgressIndicator(color: AppColors.primary));
      }
      if (hasError) {
        return _empty(Icons.error_outline, 'Could not load your reports',
            retry: () => ref.invalidate(myMatchAnalysisRequestsProvider));
      }
      return _empty(emptyIcon, emptyText);
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(myMatchAnalysisRequestsProvider),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => MatchAnalysisBookingCard(
            key: ValueKey('r_${reports[i].id}'), request: reports[i]),
      ),
    );
  }

  Widget _empty(IconData icon, String text, {VoidCallback? retry}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: AppColors.primary.withOpacity(0.35)),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14)),
              if (retry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                    onPressed: retry, child: const Text('Try Again')),
              ],
            ],
          ),
        ),
      );
}
