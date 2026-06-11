import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/config/dev_config.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_account_model.dart';
import '../../models/astrologer_booking_model.dart';
import '../../models/astrologer_request_model.dart';
import '../../providers/astrologer_session_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';

/// Astrologer dashboard with 7 sections (Overview, Requests, Appointments,
/// Services, Availability, Reviews, Profile) shown in a scrollable tab bar.
class AstrologerDashboardScreen extends ConsumerWidget {
  const AstrologerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(myAstrologerAccountProvider);
    if (account == null) {
      // Not onboarded — router normally prevents this, but guard anyway.
      return const Scaffold(body: Center(child: Text('Please complete onboarding')));
    }

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: Text(account.fullName),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () async {
                ref.read(myAstrologerAccountProvider.notifier).signOut();
                if (!kBypassAuth) {
                  await ref.read(authNotifierProvider.notifier).signOut();
                }
                if (context.mounted) context.go('/account-type');
              },
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: AppColors.gold,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Requests'),
              Tab(text: 'Appointments'),
              Tab(text: 'Services'),
              Tab(text: 'Availability'),
              Tab(text: 'Reviews'),
              Tab(text: 'Profile'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewSection(account: account),
            const _RequestsSection(),
            const _BookingsSection(),
            _ServicesSection(account: account),
            const _AvailabilitySection(),
            const _ReviewsSection(),
            _ProfileSection(account: account),
          ],
        ),
      ),
    );
  }
}

// ── Requests: consultations · inquiries · horoscope matching ───────────────
class _RequestsSection extends ConsumerWidget {
  const _RequestsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(astrologerRequestsProvider);

    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load requests: $e')),
      data: (requests) {
        List<AstrologerRequestModel> of(AstrologerRequestType t) =>
            requests.where((r) => r.type == t).toList();

        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              TabBar(
                labelColor: AppColors.primary,
                indicatorColor: AppColors.primary,
                tabs: [
                  Tab(
                      text:
                          'Consultations (${of(AstrologerRequestType.consultation).length})'),
                  Tab(
                      text:
                          'Inquiries (${of(AstrologerRequestType.inquiry).length})'),
                  Tab(
                      text:
                          'Matching (${of(AstrologerRequestType.matching).length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _requestList(of(AstrologerRequestType.consultation)),
                    _requestList(of(AstrologerRequestType.inquiry)),
                    _requestList(of(AstrologerRequestType.matching)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _requestList(List<AstrologerRequestModel> items) {
    if (items.isEmpty) {
      return const Center(child: Text('No requests here yet'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _RequestCard(request: items[i]),
    );
  }
}

class _RequestCard extends ConsumerWidget {
  final AstrologerRequestModel request;
  const _RequestCard({required this.request});

  Future<void> _setStatus(
      WidgetRef ref, AstrologerRequestStatus status) async {
    if (kBypassAuth) {
      ref
          .read(demoAstrologerRequestsProvider.notifier)
          .setStatus(request.id, status);
      return;
    }
    await ref
        .read(astrologerServiceProvider)
        .updateRequestStatus(request.id, status);
  }

  Color get _statusColor {
    switch (request.status) {
      case AstrologerRequestStatus.pending:
        return AppColors.warning;
      case AstrologerRequestStatus.accepted:
        return AppColors.info;
      case AstrologerRequestStatus.completed:
        return AppColors.success;
      case AstrologerRequestStatus.rejected:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage: request.userPhotoUrl.isNotEmpty
                    ? NetworkImage(request.userPhotoUrl)
                    : null,
                child: request.userPhotoUrl.isEmpty
                    ? Text(
                        request.userName.isNotEmpty
                            ? request.userName[0]
                            : '?',
                        style: const TextStyle(color: AppColors.primary))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.userName,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(request.type.label,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(request.status.label,
                    style: TextStyle(fontSize: 11, color: _statusColor)),
              ),
            ],
          ),
          if (request.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(request.message,
                style: TextStyle(fontSize: 13, color: Colors.grey[800])),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              if (request.amount > 0)
                Text('₹${request.amount}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              const Spacer(),
              if (request.status == AstrologerRequestStatus.pending) ...[
                TextButton(
                  onPressed: () =>
                      _setStatus(ref, AstrologerRequestStatus.rejected),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.error),
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () =>
                      _setStatus(ref, AstrologerRequestStatus.accepted),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Accept'),
                ),
              ] else if (request.status ==
                  AstrologerRequestStatus.accepted)
                ElevatedButton(
                  onPressed: () =>
                      _setStatus(ref, AstrologerRequestStatus.completed),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Mark Completed'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Verification banner reused across sections ──────────────────────────────
Widget _verificationBanner(AstrologerAccount a) {
  final pending = a.status == VerificationStatus.pending;
  final rejected = a.status == VerificationStatus.rejected;
  if (a.isApproved) return const SizedBox.shrink();
  return Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: (rejected ? AppColors.error : AppColors.warning).withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(rejected ? Icons.cancel : Icons.hourglass_top,
            color: rejected ? AppColors.error : AppColors.warning),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            rejected
                ? 'Your certificate was rejected. Please re-submit valid documents.'
                : 'Your profile is under review. You will be visible to users once '
                    'an admin approves your certificate.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

// ── 1. Overview ─────────────────────────────────────────────────────────────
class _OverviewSection extends ConsumerWidget {
  final AstrologerAccount account;
  const _OverviewSection({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(astrologerStatsProvider);
    return ListView(
      children: [
        _verificationBanner(account),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _statCard('Appointments', '${stats['totalBookings']}',
                  Icons.event_note, AppColors.primary),
              _statCard('Pending Requests', '${stats['pendingRequests']}',
                  Icons.mark_email_unread_outlined, AppColors.info),
              _statCard('Earnings', '₹${stats['monthlyEarnings']}',
                  Icons.payments_outlined, AppColors.success),
              _statCard('Rating', '${stats['avgRating']} ★',
                  Icons.star, AppColors.gold),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rating Summary',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('${stats['avgRating']}',
                        style: const TextStyle(
                            fontSize: 34, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: List.generate(
                              5,
                              (i) => Icon(
                                    i < (stats['avgRating'] as double).round()
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: AppColors.gold,
                                    size: 18,
                                  )),
                        ),
                        Text('${stats['reviewCount']} reviews',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color),
            Text(value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      );
}

// ── 2. Bookings ─────────────────────────────────────────────────────────────
class _BookingsSection extends ConsumerWidget {
  const _BookingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(astrologerBookingsProvider);
    List<AstrologerBooking> of(BookingStatus s) =>
        bookings.where((b) => b.status == s).toList();

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            labelColor: AppColors.primary,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Completed'),
              Tab(text: 'Cancelled'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _list(of(BookingStatus.upcoming)),
                _list(of(BookingStatus.completed)),
                _list(of(BookingStatus.cancelled)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<AstrologerBooking> items) {
    if (items.isEmpty) {
      return const Center(child: Text('No bookings here'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final b = items[i];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              CircleAvatar(
                  radius: 24, backgroundImage: NetworkImage(b.userPhotoUrl)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.userName,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(b.serviceName,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(Icons.videocam_outlined, size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text('${b.mode} · ${_fmt(b.dateTime)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ]),
                  ],
                ),
              ),
              Text('₹${b.amount}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: AppColors.primary)),
            ],
          ),
        );
      },
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ── 3. Services ─────────────────────────────────────────────────────────────
class _ServicesSection extends StatelessWidget {
  final AstrologerAccount account;
  const _ServicesSection({required this.account});

  @override
  Widget build(BuildContext context) {
    final services = account.services;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final s in services)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (s.description.isNotEmpty)
                        Text(s.description,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Text('₹${s.price}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: AppColors.primary)),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  // TODO(next): full add/edit/remove service management.
                  onPressed: () => _soon(context),
                ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => _soon(context),
          icon: const Icon(Icons.add),
          label: const Text('Add Service'),
        ),
      ],
    );
  }

  void _soon(BuildContext context) => ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Full service management coming next')));
}

// ── 4. Availability ─────────────────────────────────────────────────────────
class _AvailabilitySection extends ConsumerWidget {
  const _AvailabilitySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(astrologerAvailabilityProvider);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final day in week.keys)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(day, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Icon(Icons.edit_calendar_outlined,
                        size: 18, color: AppColors.primary),
                  ],
                ),
                const SizedBox(height: 6),
                if (week[day]!.isEmpty)
                  Text('Unavailable', style: TextStyle(color: Colors.grey[500]))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: week[day]!
                        .map((slot) => Chip(
                              label: Text('${slot.start} - ${slot.end}',
                                  style: const TextStyle(fontSize: 12)),
                              backgroundColor: slot.enabled
                                  ? AppColors.success.withOpacity(0.1)
                                  : Colors.grey.withOpacity(0.15),
                              labelStyle: TextStyle(
                                  color: slot.enabled
                                      ? AppColors.success
                                      : Colors.grey,
                                  decoration: slot.enabled
                                      ? null
                                      : TextDecoration.lineThrough),
                              side: BorderSide.none,
                            ))
                        .toList(),
                  ),
              ],
            ),
          ),
        // TODO(next): full slot create/edit/disable management.
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Tap a day to manage slots (full editor coming next)',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
      ],
    );
  }
}

// ── 5. Reviews ──────────────────────────────────────────────────────────────
class _ReviewsSection extends ConsumerWidget {
  const _ReviewsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(astrologerReviewsProvider);
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: reviews.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = reviews[i];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: Text(r.userName[0],
                        style: const TextStyle(color: AppColors.primary)),
                  ),
                  const SizedBox(width: 8),
                  Text(r.userName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  const Icon(Icons.star, size: 15, color: AppColors.gold),
                  Text(' ${r.rating}'),
                ],
              ),
              const SizedBox(height: 6),
              Text(r.comment, style: TextStyle(color: Colors.grey[700])),
            ],
          ),
        );
      },
    );
  }
}

// ── 6. Profile ──────────────────────────────────────────────────────────────
class _ProfileSection extends StatelessWidget {
  final AstrologerAccount account;
  const _ProfileSection({required this.account});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: const Icon(Icons.person, size: 44, color: AppColors.primary),
              ),
              const SizedBox(height: 10),
              Text(account.fullName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(account.status.label,
                  style: TextStyle(
                      color: account.isApproved ? AppColors.success : AppColors.warning)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _info('Experience', '${account.experienceYears} years'),
        _info('Expertise', account.expertise.join(', ')),
        _info('Languages', account.languages.join(', ')),
        _info('Consultation', account.consultationModes.join(', ')),
        _info('Location', '${account.city}, ${account.state}, ${account.country}'),
        _info('Mobile', '+91 ${account.mobile}'),
        _info('Email', account.email),
        _info('Certificate', '${account.certName} · ${account.certOrg}'),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          // TODO(next): edit profile screen.
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Edit profile coming next'))),
          icon: const Icon(Icons.edit),
          label: const Text('Edit Profile'),
        ),
      ],
    );
  }

  Widget _info(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 110,
                child: Text(label,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13))),
            Expanded(
                child: Text(value.isEmpty ? '—' : value,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
      );
}
