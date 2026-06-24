import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../models/consultation_model.dart';
import '../../../providers/consultation_provider.dart';
import '../../../providers/match_analysis_provider.dart';
import '../../astrologer/my_consultations_screen.dart';
import '../../astrologer/my_match_analysis_screen.dart';

/// Unified "Bookings" tab (bottom-nav item 5).
///
/// Four tabs over the user's two booking pipelines — match-analysis
/// (`astrologer_requests`, type==matching) and consultations (`consultations`):
///   • Match Analysis — every porutham booking
///   • Consultation   — every in-app / direct-visit booking
///   • Completed      — finished bookings of either kind
///   • Cancelled      — rejected / cancelled / expired bookings of either kind
///
/// Cards are reused from "My Match Analysis" ([MatchAnalysisBookingCard]) and
/// "My Consultations" ([ConsultationBookingCard]), so every booking shows its
/// Booking ID, Astrologer Name, Service Type, Date, Status and Payment Status
/// and keeps the full pay / report / chat / cancel actions.
class BookingsTab extends ConsumerStatefulWidget {
  const BookingsTab({super.key});

  @override
  ConsumerState<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends ConsumerState<BookingsTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analysisAsync = ref.watch(myMatchAnalysisRequestsProvider);
    final consultAsync = ref.watch(myConsultationsProvider);

    final analysis =
        analysisAsync.valueOrNull ?? const <AstrologerRequestModel>[];
    final consults = consultAsync.valueOrNull ?? const <ConsultationBooking>[];
    final loading = analysisAsync.isLoading || consultAsync.isLoading;
    final hasError = analysisAsync.hasError || consultAsync.hasError;

    // Newest-first ordering for every tab.
    final analysisSorted = [...analysis]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final consultsSorted = [...consults]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Completed / Cancelled mix both pipelines into one date-sorted list.
    final completed = _merge(
      analysisSorted.where(
          (r) => r.status == AstrologerRequestStatus.completed),
      consultsSorted
          .where((c) => c.status == ConsultationStatus.completed),
    );
    final cancelled = _merge(
      analysisSorted.where((r) =>
          r.status == AstrologerRequestStatus.rejected ||
          r.isEffectivelyExpired),
      consultsSorted.where((c) =>
          c.status == ConsultationStatus.rejected ||
          c.status == ConsultationStatus.cancelled ||
          c.status == ConsultationStatus.refunded),
    );

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
              Tab(text: 'Consultation (${consultsSorted.length})'),
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
                analysisSorted.map(_analysisItem).toList(),
                loading: loading,
                hasError: hasError,
                emptyIcon: Icons.auto_awesome_outlined,
                emptyText: 'No match analysis bookings yet',
              ),
              _list(
                consultsSorted.map(_consultItem).toList(),
                loading: loading,
                hasError: hasError,
                emptyIcon: Icons.event_note_outlined,
                emptyText: 'No consultation bookings yet',
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

  // A booking + its date, so the mixed Completed / Cancelled tabs sort together.
  Widget _analysisItem(AstrologerRequestModel r) =>
      MatchAnalysisBookingCard(key: ValueKey('a_${r.id}'), request: r);

  Widget _consultItem(ConsultationBooking c) =>
      ConsultationBookingCard(key: ValueKey('c_${c.id}'), booking: c);

  List<Widget> _merge(
    Iterable<AstrologerRequestModel> analysis,
    Iterable<ConsultationBooking> consults,
  ) {
    final entries = <({DateTime date, Widget card})>[
      for (final r in analysis) (date: r.createdAt, card: _analysisItem(r)),
      for (final c in consults) (date: c.createdAt, card: _consultItem(c)),
    ]..sort((a, b) => b.date.compareTo(a.date));
    return entries.map((e) => e.card).toList();
  }

  Widget _list(
    List<Widget> cards, {
    required bool loading,
    required bool hasError,
    required IconData emptyIcon,
    required String emptyText,
  }) {
    if (cards.isEmpty) {
      if (loading) {
        return const Center(
            child: CircularProgressIndicator(color: AppColors.primary));
      }
      if (hasError) {
        return _empty(Icons.error_outline, 'Could not load your bookings',
            retry: () {
          ref.invalidate(myMatchAnalysisRequestsProvider);
          ref.invalidate(myConsultationsProvider);
        });
      }
      return _empty(emptyIcon, emptyText);
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(myMatchAnalysisRequestsProvider);
        ref.invalidate(myConsultationsProvider);
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => cards[i],
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
