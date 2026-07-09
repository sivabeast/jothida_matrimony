import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/interest_model.dart';
import '../../models/wedding_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/interest_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/wedding_provider.dart';
import '../../widgets/common/coming_soon.dart';

/// Interest Management Center — replaces the old chat/messages page.
///
/// Four tabs over the Firestore `interests` collection:
///  • Received  — pending interests others sent me (Accept / Reject)
///  • Sent      — interests I sent (with status)
///  • Accepted  — mutually accepted (View Profile / Horoscope)
///  • Rejected  — declined history
class InterestsCenterScreen extends ConsumerStatefulWidget {
  /// Initial tab to open: 0 Received · 1 Sent · 2 Accepted · 3 Rejected.
  final int initialTab;

  /// When true the screen provides its own Scaffold + AppBar (pushed as a route,
  /// e.g. from the side menu's "Interests Sent / Received"). When false it is
  /// rendered inline as the Home shell's Interests tab.
  final bool standalone;

  const InterestsCenterScreen({
    super.key,
    this.initialTab = 0,
    this.standalone = false,
  });

  @override
  ConsumerState<InterestsCenterScreen> createState() =>
      _InterestsCenterScreenState();
}

class _InterestsCenterScreenState extends ConsumerState<InterestsCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(
      length: 4, vsync: this, initialIndex: widget.initialTab.clamp(0, 3));

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
    //
    // Accepted/Rejected merge BOTH directions (interests I sent + interests I
    // received), so the same person can appear twice — once per direction, or
    // from a duplicate interest doc. De-duplicate by the OTHER user's id so each
    // matched profile is shown exactly once.
    final receivedPending = _sorted(received.where((i) => i.isPending));
    final sentAll = _sorted(sent);
    final accepted = _dedupByCounterpart(
        _sorted([...sent, ...received].where((i) => i.isAccepted)), myUid);
    final rejected = _dedupByCounterpart(
        _sorted([...sent, ...received].where((i) => i.isRejected)), myUid);

    final l10n = context.l10n;
    final content = Column(
      children: [
        // Inline (Home-tab) heading. When shown as a standalone route the AppBar
        // title already names the page, so this in-body title is dropped.
        if (!widget.standalone)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            alignment: Alignment.centerLeft,
            child: Text(l10n.interests,
                style: const TextStyle(
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
              Tab(text: '${l10n.received} (${receivedPending.length})'),
              Tab(text: '${l10n.sent} (${sentAll.length})'),
              Tab(text: '${l10n.accepted} (${accepted.length})'),
              Tab(text: '${l10n.rejected} (${rejected.length})'),
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
                  emptyText: l10n.noReceivedInterests),
              _InterestList(
                  items: sentAll,
                  mode: _CardMode.sent,
                  myUid: myUid,
                  loading: loading,
                  hasError: hasError,
                  emptyText: l10n.noSentInterests),
              _InterestList(
                  items: accepted,
                  mode: _CardMode.accepted,
                  myUid: myUid,
                  loading: loading,
                  hasError: hasError,
                  emptyText: l10n.noAcceptedInterests),
              _InterestList(
                  items: rejected,
                  mode: _CardMode.rejected,
                  myUid: myUid,
                  loading: loading,
                  hasError: hasError,
                  emptyText: l10n.noRejectedInterests),
            ],
          ),
        ),
      ],
    );

    if (widget.standalone) {
      return Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: Text(l10n.interests),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: content,
      );
    }
    return content;
  }

  List<InterestModel> _sorted(Iterable<InterestModel> it) {
    final list = it.toList()..sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return list;
  }

  /// Keeps only the first interest per counterpart (the other user's id), so a
  /// profile never appears more than once. [items] should already be sorted
  /// newest-first so the most recent interest is the one kept.
  List<InterestModel> _dedupByCounterpart(
      List<InterestModel> items, String myUid) {
    final seen = <String>{};
    final out = <InterestModel>[];
    for (final i in items) {
      final otherId = i.senderId == myUid ? i.receiverId : i.senderId;
      if (otherId.isEmpty) continue;
      if (seen.add(otherId)) out.add(i);
    }
    return out;
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
        text: hasError ? context.l10n.couldntLoadInterests : emptyText,
        subtitle: hasError
            ? context.l10n.checkConnectionRetry
            : context.l10n.interestStartHint,
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
    final name = profile?.name ?? context.l10n.member;
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
              if (mode == _CardMode.sent) _statusChip(context, interest.status),
              if (mode == _CardMode.rejected) _statusChip(context, 'rejected'),
            ],
          ),
          const SizedBox(height: 12),
          _actions(context, ref, otherUserId, name),
        ],
      ),
    );
  }

  Widget _actions(
      BuildContext context, WidgetRef ref, String otherUserId, String name) {
    final l10n = context.l10n;
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
                  _snack(context, l10n.interestDeclined);
                },
                style:
                    OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                child: Text(l10n.reject),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  ref
                      .read(interestNotifierProvider.notifier)
                      .acceptInterest(interest.id);
                  _snack(context, l10n.interestAcceptedMatch);
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white),
                child: Text(l10n.accept),
              ),
            ),
          ],
        );
      case _CardMode.accepted:
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (otherUserId.isEmpty) {
                        _snack(context, l10n.profileUnavailableMatch);
                        return;
                      }
                      context.push('/profile-user/$otherUserId');
                    },
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: Text(l10n.viewProfile),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    // Accepted → opens the Horoscope Match Result page. It compares
                    // the logged-in user's horoscope with this member's horoscope
                    // and shows the compatibility (porutham) analysis only — the
                    // member's raw horoscope fields are never revealed.
                    onPressed: () {
                      if (otherUserId.isEmpty) {
                        _snack(context, l10n.horoscopeUnavailableMember);
                        return;
                      }
                      context.push('/horoscope-match/$otherUserId');
                    },
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(l10n.horoscope),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Get a professional Horoscope Compatibility Report — creates a paid
            // report request that is auto-assigned to an employee and delivered
            // to the user's Reports page.
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  if (otherUserId.isEmpty) {
                    _snack(context, l10n.horoscopeUnavailableMember);
                    return;
                  }
                  context.push('/horoscope-report/$otherUserId');
                },
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Get Horoscope Compatibility Report'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary)),
              ),
            ),
            const SizedBox(height: 10),
            // Marriage Fixed → mutual confirmation unlocks the shared
            // Wedding Workspace for the couple + invited family members.
            _MarriageFixedButton(otherUserId: otherUserId, otherName: name),
          ],
        );
      case _CardMode.sent:
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(
            interest.isAccepted
                ? l10n.sentAcceptedHint
                : interest.isRejected
                    ? l10n.interestDeclinedStatus
                    : l10n.waitingForResponse,
            style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
          ),
        );
      case _CardMode.rejected:
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(l10n.interestDeclinedStatus,
              style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
        );
    }
  }


  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));

  Widget _statusChip(BuildContext context, String status) {
    final accepted = status == 'accepted';
    final rejected = status == 'rejected';
    final color = accepted
        ? AppColors.success
        : rejected
            ? AppColors.error
            : AppColors.warning;
    final label = accepted
        ? context.l10n.accepted
        : rejected
            ? context.l10n.rejected
            : context.l10n.pending;
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

/// The "Marriage Fixed" action for an accepted match. Reflects the live
/// wedding state between the two users:
///   • no wedding yet          → "💍 Marriage Fixed" (starts the confirmation)
///   • I confirmed, they haven't → waiting chip
///   • they confirmed, I haven't → "Confirm Marriage Fixed"
///   • both confirmed (fixed)  → "Open Wedding Workspace"
class _MarriageFixedButton extends ConsumerWidget {
  final String otherUserId;
  final String otherName;
  const _MarriageFixedButton(
      {required this.otherUserId, required this.otherName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (otherUserId.isEmpty) return const SizedBox.shrink();

    // ── LAUNCH LOCK: Marriage Fixed (and the workspace it unlocks) is not in
    // the initial release. Non-admin users see the shared lock state; tapping
    // it only shows the Coming Soon dialog. Admins keep the full flow below.
    if (!ref.watch(upcomingFeaturesUnlockedProvider)) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => showComingSoonDialog(context,
              featureName: context.l10n.featureMarriageFixed),
          icon: const Icon(Icons.lock, size: 16),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(context.l10n.featureMarriageFixed,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              const ComingSoonBadge(compact: true),
            ],
          ),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade400,
              foregroundColor: Colors.white),
        ),
      );
    }

    final myUid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid ?? '';
    final wedding =
        ref.watch(weddingWithUserProvider(otherUserId)).valueOrNull;

    // ── Workspace unlocked ──
    if (wedding != null && wedding.isFixed) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => context.push('/wedding-workspace'),
          icon: const Text('💍', style: TextStyle(fontSize: 15)),
          label: const Text('Open Wedding Workspace'),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white),
        ),
      );
    }

    // ── I already confirmed — waiting for the partner ──
    if (wedding != null && wedding.confirmedBy(myUid)) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.warning.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.warning.withOpacity(0.4)),
        ),
        child: Text(
          '💍 Marriage Fixed sent — waiting for $otherName to confirm.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.warning),
        ),
      );
    }

    // ── They proposed / nothing yet — I can confirm ──
    final partnerProposed = wedding != null && !wedding.confirmedBy(myUid);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _confirm(context, ref, partnerProposed),
        icon: const Text('💍', style: TextStyle(fontSize: 15)),
        label: Text(partnerProposed
            ? 'Confirm Marriage Fixed'
            : 'Marriage Fixed'),
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.goldDark,
            foregroundColor: Colors.white),
      ),
    );
  }

  Future<void> _confirm(
      BuildContext context, WidgetRef ref, bool partnerProposed) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marriage Fixed 💍'),
        content: Text(partnerProposed
            ? '$otherName has confirmed the marriage. Confirm from your side '
                'too?\n\nOnce both of you confirm, the Wedding Workspace '
                'unlocks — a shared space for your families to plan the '
                'wedding together.'
            : 'Have both families decided to proceed with the marriage with '
                '$otherName?\n\nWhen $otherName also confirms, the Wedding '
                'Workspace unlocks — a shared space for your families to '
                'plan the wedding together.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not Yet')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Marriage Fixed'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final WeddingModel? wedding = await ref
        .read(weddingControllerProvider.notifier)
        .confirmMarriageFixed(otherUserId);
    if (wedding == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not save Marriage Fixed. Please try again.')));
      return;
    }
    messenger.showSnackBar(SnackBar(
        content: Text(wedding.isFixed
            ? '🎉 Marriage Fixed! Your Wedding Workspace is now unlocked.'
            : '💍 Marriage Fixed sent — waiting for $otherName to confirm.')));
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
