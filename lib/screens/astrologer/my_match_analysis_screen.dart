import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/astrologer_model.dart';
import '../../models/astrologer_request_model.dart';
import '../../providers/astrologer_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/match_analysis_provider.dart';

/// Bookings already swept this session, so the expiry sweep never re-fires the
/// (idempotent, transaction-guarded) Firestore write more than once per id.
final _sweptExpiry = <String>{};

/// Best-effort client-side expiry sweep: for any of the user's pending bookings
/// whose 24-hour window has lapsed, persist the Expired flag + notify. Scheduled
/// post-frame so it never writes during a build.
void _sweepExpiry(WidgetRef ref, List<AstrologerRequestModel> all) {
  final due = all
      .where((r) =>
          r.isExpiredByTime && !r.expired && !_sweptExpiry.contains(r.id))
      .toList();
  if (due.isEmpty) return;
  for (final r in due) {
    _sweptExpiry.add(r.id);
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    for (final r in due) {
      ref.read(matchAnalysisControllerProvider.notifier).expireIfDue(r);
    }
  });
}

/// "My Match Analysis" — the user's view of the porutham requests they booked
/// with astrologers, in Pending / Accepted / Completed tabs. Completed requests
/// expose the astrologer's report (text + images + PDFs); accepted & completed
/// requests unlock a chat with that astrologer.
class MyMatchAnalysisScreen extends ConsumerWidget {
  const MyMatchAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myMatchAnalysisRequestsProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: const Text('My Match Analysis'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: AppColors.gold,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'Accepted'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        body: async.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (_, __) => _error(ref),
          data: (all) {
            // Flag any of the user's bookings whose response window has lapsed.
            _sweepExpiry(ref, all);
            // Pending tab also surfaces rejected/expired outcomes (status chip
            // makes the result clear) so nothing the user booked silently
            // disappears.
            final pending = all
                .where((r) =>
                    r.status == AstrologerRequestStatus.pending ||
                    r.status == AstrologerRequestStatus.rejected)
                .toList();
            final accepted = all
                .where((r) => r.status == AstrologerRequestStatus.accepted)
                .toList();
            final completed = all
                .where((r) => r.status == AstrologerRequestStatus.completed)
                .toList();
            return TabBarView(
              children: [
                _list(pending, 'No pending requests'),
                _list(accepted, 'No accepted requests yet'),
                _list(completed, 'No completed analysis yet'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _list(List<AstrologerRequestModel> items, String emptyMsg) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_outlined,
                  size: 56, color: AppColors.primary.withOpacity(0.35)),
              const SizedBox(height: 12),
              Text(emptyMsg,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => MatchAnalysisBookingCard(request: items[i]),
    );
  }

  Widget _error(WidgetRef ref) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: AppColors.error),
            const SizedBox(height: 12),
            const Text('Could not load your analysis'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () =>
                  ref.invalidate(myMatchAnalysisRequestsProvider),
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
}

/// A single match-analysis booking card. Public so the unified Bookings page
/// (bottom-nav tab) can reuse it alongside "My Match Analysis".
class MatchAnalysisBookingCard extends ConsumerWidget {
  final AstrologerRequestModel request;
  const MatchAnalysisBookingCard({super.key, required this.request});

  // Colour + label are driven by the booking's DISPLAY status (which folds in
  // the Expired / Reassigned states) rather than the raw enum.
  Color _statusColor(AstrologerRequestModel r) {
    switch (r.displayStatusKey) {
      case 'expired':
        return AppColors.error;
      case 'reassigned':
        return Colors.deepPurple;
      case 'accepted':
        return AppColors.info;
      case 'completed':
        // Completed-but-unpaid (a fee is still owed) reads as a
        // payment-required warning; paid / free completed reads as success.
        return (r.amount > 0 && !r.paid) ? AppColors.warning : AppColors.success;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  String _statusLabel(BuildContext context, AstrologerRequestModel r) {
    final l = context.l10n;
    switch (r.displayStatusKey) {
      case 'expired':
        return l.statusExpired;
      case 'reassigned':
        return l.statusReassigned;
      case 'accepted':
        return l.statusAccepted;
      case 'completed':
        // Spec lifecycle: a completed report with an unpaid fee surfaces as
        // "Completed - Payment Required"; once paid it reads "Paid".
        if (r.amount > 0 && !r.paid) return 'Completed - Payment Required';
        if (r.paid) return 'Paid';
        return l.statusCompleted;
      case 'rejected':
        return l.statusRejected;
      default:
        return l.statusPending;
    }
  }

  Future<void> _chat(BuildContext context, WidgetRef ref) async {
    try {
      final photo =
          ref.read(astrologerByIdProvider(request.astrologerId))?.photoUrl ?? '';
      final id = await ref.read(chatControllerProvider).openChatWith(
            otherUid: request.astrologerId,
            otherName: request.astrologerName.isEmpty
                ? 'Astrologer'
                : request.astrologerName,
            otherPhoto: photo,
          );
      if (!context.mounted) return;
      context.push('/chat/$id', extra: {
        'name':
            request.astrologerName.isEmpty ? 'Astrologer' : request.astrologerName,
        'photo': photo,
      });
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open chat. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final color = _statusColor(r);
    // Chat is gated on payment + approval: only an accepted-AND-paid (or
    // completed) booking unlocks chat. No payment / pending = no chat.
    final canChat = r.paid &&
        (r.status == AstrologerRequestStatus.accepted ||
            r.status == AstrologerRequestStatus.completed);
    // The astrologer has submitted the report (text / images / PDFs).
    final reportReady =
        r.status == AstrologerRequestStatus.completed && r.hasAnalysis;
    // A fee is still owed. Free analyses (amount == 0) are never payment-locked.
    final paymentDue = r.amount > 0 && !r.paid;
    // PAYMENT LOCK (spec): a completed report is viewable ONLY once paid (or
    // free). Until then NOTHING that exposes the report/images/PDFs is shown.
    final canViewReport = reportReady && !paymentDue;
    // Completed but unpaid → show the locked "Report Ready / Pay Now" card.
    final reportLocked = reportReady && paymentDue;
    // Accepted-stage "pay to confirm" is preserved (existing behaviour); paying
    // at EITHER point marks the booking paid and unlocks the report + chat.
    final canPayAccepted = r.awaitingPayment;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.gold, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.astrologerName.isEmpty
                      ? 'Astrologer'
                      : r.astrologerName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_statusLabel(context, r),
                    style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.favorite, size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${r.profileAName ?? 'Groom'}  ×  ${r.profileBName ?? 'Bride'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(DateFormat('d MMM yyyy, h:mm a').format(r.createdAt),
              style: TextStyle(fontSize: 11.5, color: Colors.grey[500])),
          const SizedBox(height: 6),
          _metaFooter(r),
          if (r.message.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
          ],
          if (r.isEffectivelyExpired) _expirySection(context, ref, r),
          if (canPayAccepted) ...[
            const SizedBox(height: 10),
            _payBanner(),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _pay(context, ref, r),
                icon: const Icon(Icons.payment, size: 18),
                label: Text('Pay ₹${r.amount}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
          ],
          // PAYMENT LOCK — completed report, fee still owed: show ONLY the
          // "Report Ready" message + a dummy Pay Now button. No report content,
          // images, PDFs, notes, chat or download are exposed here.
          if (reportLocked) _reportLockCard(context, ref, r),
          if (canChat || canViewReport) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (canViewReport)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showReport(context, r),
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('View Report'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                if (canViewReport && canChat) const SizedBox(width: 10),
                if (canChat)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _chat(context, ref),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: const Text('Chat'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Booking ID · service type · payment status footer (spec display fields).
  Widget _metaFooter(AstrologerRequestModel r) {
    final shortId = r.id.length <= 8 ? r.id : r.id.substring(0, 8);
    final payKey = r.paymentStatusKey;
    final payColor = payKey == 'paid'
        ? AppColors.success
        : payKey == 'pending'
            ? AppColors.warning
            : Colors.grey;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _metaPill(Icons.tag, '#$shortId'),
        _metaPill(Icons.auto_awesome_outlined, 'Match Analysis'),
        if (r.amount > 0)
          _metaPill(Icons.payments_outlined, r.paymentStatusLabel,
              color: payColor),
      ],
    );
  }

  Widget _metaPill(IconData icon, String text, {Color? color}) {
    final c = color ?? Colors.grey[600]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 10.5, color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _payBanner() => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.info.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline, size: 16, color: AppColors.info),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Accepted! Complete the payment to confirm your analysis.',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );

  Future<void> _pay(
      BuildContext context, WidgetRef ref, AstrologerRequestModel r) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(matchAnalysisControllerProvider.notifier).pay(r);
      messenger.showSnackBar(const SnackBar(
          content: Text('Payment successful — your report is unlocked.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Payment could not be completed. Please try again.')));
    }
  }

  /// PAYMENT-LOCK card shown when the astrologer has completed the report but
  /// the user hasn't paid. It exposes NONE of the report (no text, images, PDFs,
  /// notes or download) — only the spec's "Report Ready" message and a single
  /// dummy "Pay Now" button. The dummy [_pay] simulates a successful payment;
  /// once it succeeds the live stream rebuilds this card with the report
  /// unlocked, so this is trivial to swap for a real gateway later.
  Widget _reportLockCard(
      BuildContext context, WidgetRef ref, AstrologerRequestModel r) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.gold.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Report Ready',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Your horoscope matching report has been completed.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 4),
          Text(
            'Please complete payment to unlock and view the report.',
            style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey[700]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _pay(context, ref, r),
              icon: const Icon(Icons.lock_open, size: 18),
              label: Text(r.amount > 0 ? 'Pay Now · ₹${r.amount}' : 'Pay Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shown on an expired booking — the spec notification copy + (for non-admin
  /// modes) a button to manually pick a new astrologer.
  Widget _expirySection(
      BuildContext context, WidgetRef ref, AstrologerRequestModel r) {
    final l = context.l10n;
    final String msg;
    switch (r.reassignMode) {
      case BookingReassignMode.chooseLater:
        msg = l.expiredChooseAnotherMsg;
        break;
      case BookingReassignMode.allowAdmin:
        msg = l.expiredAdminWillAssignMsg;
        break;
      case BookingReassignMode.waitOnly:
        msg = l.expiredWaitOnlyMsg;
        break;
    }
    final canChoose = r.reassignMode != BookingReassignMode.allowAdmin;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.timer_off_outlined,
                  size: 16, color: AppColors.error),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(msg, style: const TextStyle(fontSize: 12.5))),
            ],
          ),
          if (canChoose) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openChooseAnother(context, ref, r),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: Text(l.chooseAnotherAstrologer),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openChooseAnother(
      BuildContext context, WidgetRef ref, AstrologerRequestModel r) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ChooseAstrologerSheet(request: r),
    );
  }

  void _showReport(BuildContext context, AstrologerRequestModel r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 14),
              Text('Analysis by ${r.astrologerName.isEmpty ? 'Astrologer' : r.astrologerName}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${r.profileAName ?? 'Groom'}  ×  ${r.profileBName ?? 'Bride'}',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              const Divider(height: 26),
              if (r.analysisText.trim().isNotEmpty) ...[
                const Text('Report',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Text(r.analysisText,
                    style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 18),
              ],
              if (r.analysisImages.isNotEmpty) ...[
                const Text('Images',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: r.analysisImages.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => showImageGallery(context, r.analysisImages,
                          initialIndex: i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          r.analysisImages[i],
                          width: 110,
                          height: 110,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 110,
                            height: 110,
                            color: AppColors.primary.withOpacity(0.08),
                            child: const Icon(Icons.broken_image_outlined,
                                color: AppColors.primary),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (r.analysisPdfs.isNotEmpty) ...[
                const Text('PDFs',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                for (var i = 0; i < r.analysisPdfs.length; i++)
                  RemotePdfTile(
                      url: r.analysisPdfs[i],
                      label: 'Analysis PDF ${i + 1}',
                      index: i),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for "Choose Another Astrologer" (Option 2 — the user re-points
/// an expired booking themselves). Radio-button single selection of an
/// available astrologer, then [Assign].
class _ChooseAstrologerSheet extends ConsumerStatefulWidget {
  final AstrologerRequestModel request;
  const _ChooseAstrologerSheet({required this.request});

  @override
  ConsumerState<_ChooseAstrologerSheet> createState() =>
      _ChooseAstrologerSheetState();
}

class _ChooseAstrologerSheetState
    extends ConsumerState<_ChooseAstrologerSheet> {
  String? _selectedId;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final list = (ref.watch(astrologersProvider).valueOrNull ??
            const <Astrologer>[])
        .where((a) => a.isAvailable && a.id != widget.request.astrologerId)
        .toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.chooseAnotherAstrologer,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Select ONE astrologer. Your booking moves to them with a fresh '
            '24-hour response window.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                  child: Text('No other available astrologers right now.')),
            )
          else
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final a = list[i];
                    return RadioListTile<String>(
                      value: a.id,
                      groupValue: _selectedId,
                      onChanged: (v) => setState(() => _selectedId = v),
                      activeColor: AppColors.primary,
                      contentPadding: EdgeInsets.zero,
                      title: Text(a.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(
                        '⭐ ${a.rating.toStringAsFixed(1)} · '
                        '${a.experienceYears} yrs'
                        '${a.location.isNotEmpty ? ' · ${a.location}' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      secondary: CircleAvatar(
                        backgroundColor: AppColors.primary.withOpacity(0.12),
                        backgroundImage:
                            a.photoUrl.isNotEmpty ? NetworkImage(a.photoUrl) : null,
                        child: a.photoUrl.isEmpty
                            ? const Icon(Icons.person, color: AppColors.primary)
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_selectedId == null || _busy)
                  ? null
                  : () => _assign(list),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Assign',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _assign(List<Astrologer> list) async {
    final picked = list.firstWhere((a) => a.id == _selectedId);
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(matchAnalysisControllerProvider.notifier)
          .chooseAnotherAstrologer(
            widget.request,
            astrologerId: picked.id,
            astrologerName: picked.name,
          );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
          SnackBar(content: Text('Booking sent to ${picked.name}.')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not reassign. Please try again.')));
    }
  }
}
