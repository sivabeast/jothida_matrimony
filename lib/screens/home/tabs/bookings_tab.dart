import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../providers/match_analysis_provider.dart';
import '../../astrologer/my_match_analysis_screen.dart';

/// Unified "Bookings" tab (bottom-nav item 5).
///
/// The app's only booking pipeline is now Match Analysis (`astrologer_requests`,
/// type==matching) — the per-astrologer consultation system was removed. Three
/// tabs over the user's requests:
///   • Match Analysis — every porutham request
///   • Completed      — finished analyses
///   • Cancelled      — rejected / expired requests
///
/// Cards are reused from "My Match Analysis" ([MatchAnalysisBookingCard]) so
/// every request shows its id, service type, date, status and the full
/// report / chat actions.
class BookingsTab extends ConsumerStatefulWidget {
  const BookingsTab({super.key});

  @override
  ConsumerState<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends ConsumerState<BookingsTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analysisAsync = ref.watch(myMatchAnalysisRequestsProvider);

    final analysis =
        analysisAsync.valueOrNull ?? const <AstrologerRequestModel>[];
    final loading = analysisAsync.isLoading;
    final hasError = analysisAsync.hasError;

    final analysisSorted = [...analysis]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final completed = analysisSorted
        .where((r) => r.status == AstrologerRequestStatus.completed)
        .toList();
    final cancelled = analysisSorted
        .where((r) =>
            r.status == AstrologerRequestStatus.rejected ||
            r.isEffectivelyExpired)
        .toList();

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          alignment: Alignment.centerLeft,
          child: const Text('My Bookings',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
        ),
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
            tabs: [
              Tab(text: 'Match Analysis (${analysisSorted.length})'),
              Tab(text: 'Completed (${completed.length})'),
              Tab(text: 'Cancelled (${cancelled.length})'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _list(
                analysisSorted,
                loading: loading,
                hasError: hasError,
                emptyIcon: Icons.auto_awesome_outlined,
                emptyText: 'No match analysis bookings yet',
              ),
              _list(
                completed,
                loading: loading,
                hasError: hasError,
                emptyIcon: Icons.verified_outlined,
                emptyText: 'No completed bookings yet',
              ),
              _list(
                cancelled,
                loading: loading,
                hasError: hasError,
                emptyIcon: Icons.cancel_outlined,
                emptyText: 'No cancelled bookings',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _list(
    List<AstrologerRequestModel> requests, {
    required bool loading,
    required bool hasError,
    required IconData emptyIcon,
    required String emptyText,
  }) {
    if (requests.isEmpty) {
      if (loading) {
        return const Center(
            child: CircularProgressIndicator(color: AppColors.primary));
      }
      if (hasError) {
        return _empty(Icons.error_outline, 'Could not load your bookings',
            retry: () => ref.invalidate(myMatchAnalysisRequestsProvider));
      }
      return _empty(emptyIcon, emptyText);
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(myMatchAnalysisRequestsProvider),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: requests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => MatchAnalysisBookingCard(
            key: ValueKey('a_${requests[i].id}'), request: requests[i]),
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
