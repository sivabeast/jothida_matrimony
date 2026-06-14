import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/interest_model.dart';
import '../../models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/interest_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/contact_reveal_card.dart';

/// Interest Management Center — replaces the old chat/messages page.
///
/// Four tabs over the Firestore `interests` collection:
///  • Received  — pending interests others sent me (Accept / Reject)
///  • Sent      — interests I sent (with status)
///  • Accepted  — mutually accepted (View Profile / View Contact)
///  • Rejected  — declined history
class InterestsCenterScreen extends ConsumerStatefulWidget {
  const InterestsCenterScreen({super.key});

  @override
  ConsumerState<InterestsCenterScreen> createState() =>
      _InterestsCenterScreenState();
}

class _InterestsCenterScreenState extends ConsumerState<InterestsCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid ?? '';
    final sentAsync = ref.watch(sentInterestsProvider);
    final receivedAsync = ref.watch(receivedInterestsProvider);

    final sent = sentAsync.valueOrNull ?? const <InterestModel>[];
    final received = receivedAsync.valueOrNull ?? const <InterestModel>[];
    final loading = sentAsync.isLoading || receivedAsync.isLoading;
    final hasError = sentAsync.hasError || receivedAsync.hasError;

    // Tab contents. Received shows only PENDING (actionable) interests; once
    // accepted/rejected they move to the Accepted / Rejected tabs.
    final receivedPending = _sorted(received.where((i) => i.isPending));
    final sentAll = _sorted(sent);
    final accepted = _sorted([...sent, ...received].where((i) => i.isAccepted));
    final rejected = _sorted([...sent, ...received].where((i) => i.isRejected));

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          alignment: Alignment.centerLeft,
          child: const Text('Interests',
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
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
            tabs: [
              Tab(text: 'Received (${receivedPending.length})'),
              Tab(text: 'Sent (${sentAll.length})'),
              Tab(text: 'Accepted (${accepted.length})'),
              Tab(text: 'Rejected (${rejected.length})'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _InterestList(
                  items: receivedPending,
                  mode: _CardMode.received,
                  myUid: myUid,
                  loading: loading,
                  hasError: hasError,
                  emptyText: 'No interests received yet'),
              _InterestList(
                  items: sentAll,
                  mode: _CardMode.sent,
                  myUid: myUid,
                  loading: loading,
                  hasError: hasError,
                  emptyText: 'You haven\'t sent any interests yet'),
              _InterestList(
                  items: accepted,
                  mode: _CardMode.accepted,
                  myUid: myUid,
                  loading: loading,
                  hasError: hasError,
                  emptyText: 'No accepted interests yet'),
              _InterestList(
                  items: rejected,
                  mode: _CardMode.rejected,
                  myUid: myUid,
                  loading: loading,
                  hasError: hasError,
                  emptyText: 'No rejected interests'),
            ],
          ),
        ),
      ],
    );
  }

  List<InterestModel> _sorted(Iterable<InterestModel> it) {
    final list = it.toList()..sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return list;
  }
}

enum _CardMode { received, sent, accepted, rejected }

class _InterestList extends StatelessWidget {
  final List<InterestModel> items;
  final _CardMode mode;
  final String myUid;
  final bool loading;
  final bool hasError;
  final String emptyText;

  const _InterestList({
    required this.items,
    required this.mode,
    required this.myUid,
    required this.loading,
    required this.hasError,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      if (loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _EmptyState(
        text: hasError ? 'Couldn\'t load interests' : emptyText,
        subtitle: hasError
            ? 'Please check your connection and try again.'
            : 'Send or receive an interest to get started.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) =>
          _InterestCard(interest: items[i], mode: mode, myUid: myUid),
    );
  }
}

class _InterestCard extends ConsumerWidget {
  final InterestModel interest;
  final _CardMode mode;
  final String myUid;

  const _InterestCard({
    required this.interest,
    required this.mode,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amSender = interest.senderId == myUid;
    final otherUserId = amSender ? interest.receiverId : interest.senderId;

    // Resolve the other person's profile by their USER id (UID). The interest's
    // senderId / receiverId always identify the right account, whereas a stored
    // profile-document id can be stale or missing — which is what made "View
    // Profile" fail to load on accepted matches.
    final profile = ref.watch(profileByUserIdProvider(otherUserId)).valueOrNull;
    final name = profile?.name ?? 'Member';
    final age = profile?.age ?? 0;
    final location = profile == null
        ? ''
        : [profile.city, profile.state].where((s) => s.trim().isNotEmpty).join(', ');
    final photo = profile?.profilePhotoUrl ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                child: photo.isEmpty
                    ? const Icon(Icons.person, color: AppColors.primary)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(age > 0 ? '$name, $age' : name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15.5)),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 13, color: Colors.grey[500]),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12.5, color: Colors.grey[600])),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (mode == _CardMode.sent) _statusChip(interest.status),
              if (mode == _CardMode.rejected) _statusChip('rejected'),
            ],
          ),
          const SizedBox(height: 12),
          _actions(context, ref, otherUserId, name, profile?.contact),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, WidgetRef ref, String otherUserId,
      String name, ContactDetails? contact) {
    switch (mode) {
      case _CardMode.received:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  ref
                      .read(interestNotifierProvider.notifier)
                      .rejectInterest(interest.id);
                  _snack(context, 'Interest declined');
                },
                style:
                    OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Reject'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  ref
                      .read(interestNotifierProvider.notifier)
                      .acceptInterest(interest.id);
                  _snack(context, "It's a match! Interest accepted 🎉");
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white),
                child: const Text('Accept'),
              ),
            ),
          ],
        );
      case _CardMode.accepted:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  if (otherUserId.isEmpty) {
                    _snack(context, 'Profile unavailable for this match.');
                    return;
                  }
                  context.push('/profile-user/$otherUserId');
                },
                icon: const Icon(Icons.person_outline, size: 18),
                label: const Text('View Profile'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                // Accepted → contact unlocked. Reveal directly from the
                // (readable) profile contact; no connection/gated-read needed.
                onPressed: () =>
                    _showContact(context, otherUserId, name, contact),
                icon: const Icon(Icons.call, size: 18),
                label: const Text('View Contact'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
              ),
            ),
          ],
        );
      case _CardMode.sent:
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(
            interest.isAccepted
                ? 'Accepted — open the Accepted tab to view contact.'
                : interest.isRejected
                    ? 'This interest was declined.'
                    : 'Waiting for a response…',
            style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
          ),
        );
      case _CardMode.rejected:
        return const Align(
          alignment: Alignment.centerLeft,
          child: Text('This interest was rejected.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey)),
        );
    }
  }

  void _showContact(BuildContext context, String otherUserId, String name,
      ContactDetails? contact) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ContactRevealCard(
                otherUserId: otherUserId, otherName: name, contact: contact),
          ],
        ),
      ),
    );
  }

  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));

  Widget _statusChip(String status) {
    final accepted = status == 'accepted';
    final rejected = status == 'rejected';
    final color = accepted
        ? AppColors.success
        : rejected
            ? AppColors.error
            : AppColors.warning;
    final label = accepted
        ? 'Accepted'
        : rejected
            ? 'Rejected'
            : 'Pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  final String subtitle;
  const _EmptyState({required this.text, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
