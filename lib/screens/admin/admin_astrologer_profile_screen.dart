import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/astrologer_account_model.dart';
import '../../models/astrologer_certificate.dart';
import '../../models/astrologer_review_model.dart';
import '../../models/consultation_model.dart';
import '../../models/settlement_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/astrologer_provider.dart';
import '../../providers/astrologer_review_provider.dart';
import '../../providers/consultation_provider.dart';
import '../../providers/settlement_provider.dart';
import '../../widgets/common/data_states.dart';
import 'admin_export.dart' show inr;

/// Admin → Astrologer profile (`/admin/astrologer/:id`).
///
/// A full operational view of one approved astrologer across six tabs:
/// Profile · Documents · Availability · Bookings · Reviews · Payouts. The
/// account is read live from [allAstrologersProvider] so a suspend reflects
/// immediately; it falls back to a direct fetch for accounts not in that stream.
class AdminAstrologerProfileScreen extends ConsumerWidget {
  final String astrologerId;
  const AdminAstrologerProfileScreen({super.key, required this.astrologerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Prefer the live stream; fall back to a one-shot fetch.
    AstrologerAccount? account;
    final all = ref.watch(allAstrologersProvider).valueOrNull ??
        const <AstrologerAccount>[];
    for (final a in all) {
      if (a.id == astrologerId) {
        account = a;
        break;
      }
    }
    account ??= ref.watch(astrologerAccountByIdProvider(astrologerId)).valueOrNull;

    if (account == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Astrologer'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: const LoadingState(message: 'Loading astrologer…'),
      );
    }

    final a = account;
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: Text(a.fullName.isEmpty ? 'Astrologer' : a.fullName),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [
            if (a.isApproved)
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'suspend') _suspend(context, ref, a);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'suspend', child: Text('Suspend / Disable')),
                ],
              ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: AppColors.gold,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Profile'),
              Tab(text: 'Documents'),
              Tab(text: 'Availability'),
              Tab(text: 'Bookings'),
              Tab(text: 'Reviews'),
              Tab(text: 'Payouts'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ProfileTab(account: a),
            _DocumentsTab(account: a),
            _AvailabilityTab(account: a),
            _BookingsTab(astrologerId: a.id),
            _ReviewsTab(astrologerId: a.id),
            _PayoutsTab(astrologerId: a.id, name: a.fullName),
          ],
        ),
      ),
    );
  }

  Future<void> _suspend(
      BuildContext context, WidgetRef ref, AstrologerAccount a) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suspend Astrologer'),
        content: Text('Suspend ${a.fullName}? They lose live visibility and '
            'return to the verification queue.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Suspend'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(adminActionsProvider.notifier).suspendAstrologer(a.id);
    final st = ref.read(adminActionsProvider);
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not suspend. Please try again.'
          : '${a.fullName} suspended.'),
      backgroundColor: st.hasError ? AppColors.error : null,
    ));
  }
}

// ── Profile tab ──────────────────────────────────────────────────────────────
class _ProfileTab extends StatelessWidget {
  final AstrologerAccount account;
  const _ProfileTab({required this.account});

  @override
  Widget build(BuildContext context) {
    final a = account;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Card(
          child: Column(
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: AppColors.primary.withOpacity(0.12),
                backgroundImage:
                    a.photoUrl.isNotEmpty ? NetworkImage(a.photoUrl) : null,
                child: a.photoUrl.isEmpty
                    ? Text(a.fullName.isNotEmpty ? a.fullName[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 26))
                    : null,
              ),
              const SizedBox(height: 10),
              Text(a.fullName,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star_rounded,
                      color: Color(0xFFFFB300), size: 18),
                  Text(' ${a.rating.toStringAsFixed(1)} · ${a.reviewCount} reviews',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  _badge(a.isApproved ? 'Approved' : a.status.label,
                      a.isApproved ? AppColors.success : AppColors.warning),
                  _badge(a.manuallyAvailable ? 'Active' : 'Inactive',
                      a.manuallyAvailable ? AppColors.success : Colors.grey),
                  _badge(a.isAvailableNow ? 'Online' : 'Offline',
                      a.isAvailableNow ? AppColors.success : Colors.grey),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row(Icons.phone_outlined, 'Mobile', a.mobile),
              _row(Icons.email_outlined, 'Email', a.email),
              _row(Icons.location_on_outlined, 'Location',
                  [a.district.isNotEmpty ? a.district : a.city, a.state]
                      .where((p) => p.trim().isNotEmpty)
                      .join(', ')),
              _row(Icons.work_history_outlined, 'Experience',
                  '${a.experienceYears} yrs'),
              _row(Icons.school_outlined, 'Qualification',
                  a.qualification.isEmpty ? '—' : a.qualification),
              _row(Icons.payments_outlined, 'Consultation Fee',
                  inr(a.consultationFee.toInt())),
              _row(Icons.translate_outlined, 'Languages',
                  a.languages.isEmpty ? '—' : a.languages.join(', ')),
              _row(Icons.auto_awesome_outlined, 'Expertise',
                  a.expertise.isEmpty ? '—' : a.expertise.join(', ')),
              _row(Icons.confirmation_number_outlined, 'Bookings',
                  '${a.bookingCount}'),
            ],
          ),
        ),
        if (a.about.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('About',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(a.about, style: const TextStyle(fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Documents tab ────────────────────────────────────────────────────────────
class _DocumentsTab extends StatelessWidget {
  final AstrologerAccount account;
  const _DocumentsTab({required this.account});

  @override
  Widget build(BuildContext context) {
    final docs = account.certificates;
    if (docs.isEmpty) {
      return const EmptyState(
          icon: Icons.folder_open_outlined, message: 'No documents uploaded');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _DocCard(cert: docs[i]),
    );
  }
}

class _DocCard extends StatelessWidget {
  final AstrologerCertificate cert;
  const _DocCard({required this.cert});

  Color get _statusColor => cert.isApproved
      ? AppColors.success
      : cert.isRejected
          ? AppColors.error
          : AppColors.warning;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(cert.isPdf ? Icons.picture_as_pdf : Icons.image,
                color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cert.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 3),
                Text(cert.status.toUpperCase(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _statusColor)),
              ],
            ),
          ),
          if (cert.url.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.open_in_new, color: AppColors.primary),
              onPressed: () =>
                  openRemoteFile(context, cert.url, pdf: cert.isPdf),
            ),
        ],
      ),
    );
  }
}

// ── Availability tab ─────────────────────────────────────────────────────────
class _AvailabilityTab extends StatelessWidget {
  final AstrologerAccount account;
  const _AvailabilityTab({required this.account});

  @override
  Widget build(BuildContext context) {
    final a = account;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row(Icons.event_available_outlined, 'Working Days',
                  a.workingDaysLabel),
              _row(Icons.schedule_outlined, 'Hours',
                  '${formatMinutes(a.availableStartMinutes)} – ${formatMinutes(a.availableEndMinutes)}'),
              _row(Icons.timelapse_outlined, 'Slot Length',
                  '${a.slotDurationMinutes} min'),
              if (a.lunchStartMinutes != null && a.lunchEndMinutes != null)
                _row(Icons.lunch_dining_outlined, 'Break',
                    '${formatMinutes(a.lunchStartMinutes!)} – ${formatMinutes(a.lunchEndMinutes!)}'),
              _row(Icons.event_busy_outlined, 'Max / Day',
                  a.maxBookingsPerDay == 0 ? 'No cap' : '${a.maxBookingsPerDay}'),
              _row(Icons.category_outlined, 'Modes', a.consultationModesLabel),
              _row(
                  a.manuallyAvailable
                      ? Icons.toggle_on
                      : Icons.toggle_off_outlined,
                  'Accepting Bookings',
                  a.manuallyAvailable ? 'Yes' : 'Paused'),
              _row(Icons.beach_access_outlined, 'On Leave',
                  a.onLeave ? 'Yes' : 'No'),
            ],
          ),
        ),
        if (a.unavailableDates.isNotEmpty) ...[
          const SizedBox(height: 14),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Unavailable Dates',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in a.unavailableDates) _badge(d, Colors.grey),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Bookings tab ─────────────────────────────────────────────────────────────
class _BookingsTab extends ConsumerWidget {
  final String astrologerId;
  const _BookingsTab({required this.astrologerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allConsultationsProvider).valueOrNull ??
        const <ConsultationBooking>[];
    final list = all.where((b) => b.astrologerId == astrologerId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (list.isEmpty) {
      return const EmptyState(
          icon: Icons.event_note_outlined, message: 'No bookings yet');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final b = list[i];
        return _Card(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text('${b.mode.label} · '
                        '${DateFormat('d MMM yyyy').format(b.createdAt)}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(inr(b.amount),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 3),
                  _badge(b.statusLabel, _statusColor(b.status), small: true),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Reviews tab ──────────────────────────────────────────────────────────────
class _ReviewsTab extends ConsumerWidget {
  final String astrologerId;
  const _ReviewsTab({required this.astrologerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(astrologerReviewsProvider(astrologerId));
    return async.when(
      loading: () => const LoadingState(message: 'Loading reviews…'),
      error: (_, __) => const EmptyState(
          icon: Icons.reviews_outlined, message: 'Could not load reviews'),
      data: (reviews) {
        if (reviews.isEmpty) {
          return const EmptyState(
              icon: Icons.reviews_outlined, message: 'No reviews yet');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: reviews.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _ReviewCard(review: reviews[i]),
        );
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final AstrologerReviewModel review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(review.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              Row(
                children: [
                  for (var s = 1; s <= 5; s++)
                    Icon(
                      s <= review.rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 16,
                      color: const Color(0xFFFFB300),
                    ),
                ],
              ),
            ],
          ),
          if (review.review.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(review.review,
                style: const TextStyle(fontSize: 13, height: 1.35)),
          ],
        ],
      ),
    );
  }
}

// ── Payouts tab ──────────────────────────────────────────────────────────────
class _PayoutsTab extends ConsumerWidget {
  final String astrologerId;
  final String name;
  const _PayoutsTab({required this.astrologerId, required this.name});

  Future<void> _markPaid(BuildContext context, WidgetRef ref,
      AstrologerSettlement s, List<ConsultationBooking> due) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as Paid'),
        content: Text('Settle ${inr(s.pendingPayout)} to $name for '
            '${due.length} consultation${due.length == 1 ? '' : 's'}? '
            'This records a full (100%) payout.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Payout'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(consultationControllerProvider.notifier).settle(
          astrologerId: astrologerId,
          astrologerName: name,
          bookings: due,
        );
    final st = ref.read(consultationControllerProvider);
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not settle. Please try again.'
          : 'Payout settled to $name.'),
      backgroundColor: st.hasError ? AppColors.error : AppColors.success,
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(astrologerSettlementByIdProvider(astrologerId));
    final due = ref.watch(settleableBookingsProvider(astrologerId));
    final history = ref
            .watch(settlementsHistoryProvider)
            .valueOrNull
            ?.where((h) => h.astrologerId == astrologerId)
            .toList() ??
        const <Settlement>[];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.9,
          children: [
            _payTile('This Week', inr(s.thisWeek), const Color(0xFF2F80ED)),
            _payTile('This Month', inr(s.thisMonth), AppColors.primary),
            _payTile('Pending Payout', inr(s.pendingPayout), AppColors.warning),
            _payTile('Total Paid', inr(s.paidAmount), AppColors.success),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_user_outlined,
                  size: 18, color: AppColors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'No commission — the astrologer receives 100% of every '
                    'consultation. Last settlement: '
                    '${s.lastSettlement == null ? '—' : DateFormat('d MMM yyyy').format(s.lastSettlement!)}.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[800])),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (s.pendingPayout > 0)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _markPaid(context, ref, s, due),
              icon: const Icon(Icons.check_circle_outline),
              label: Text('Mark ${inr(s.pendingPayout)} as Paid'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ),
        const SizedBox(height: 20),
        const Text('Settlement History',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 10),
        if (history.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('No settlements yet',
                style: TextStyle(color: Colors.grey[600])),
          )
        else
          for (final h in history)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: AppColors.success, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        '${h.bookingCount} consultation'
                        '${h.bookingCount == 1 ? '' : 's'} · '
                        '${DateFormat('d MMM yyyy').format(h.createdAt)}',
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Text(inr(h.amount),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.success)),
                ],
              ),
            ),
      ],
    );
  }

  Widget _payTile(String label, String value, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 19, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      );
}

// ── Shared bits ──────────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
          ],
        ),
        child: child,
      );
}

Widget _row(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: Colors.grey[500]),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(value.isEmpty ? '—' : value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

Widget _badge(String text, Color color, {bool small = false}) => Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 9, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: small ? 10 : 11.5,
              color: color,
              fontWeight: FontWeight.w600)),
    );

Color _statusColor(ConsultationStatus s) {
  switch (s) {
    case ConsultationStatus.completed:
      return AppColors.success;
    case ConsultationStatus.rejected:
    case ConsultationStatus.cancelled:
    case ConsultationStatus.refunded:
      return AppColors.error;
    case ConsultationStatus.pending:
      return AppColors.warning;
    default:
      return const Color(0xFF2F80ED);
  }
}
