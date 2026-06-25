import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/profile_model.dart';
import '../../../core/services/match_score_service.dart';
import '../../../providers/interest_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/subscription_provider.dart';
import '../../../providers/ui_preferences_provider.dart';
import '../../../widgets/common/match_score_badge.dart';
import '../../../widgets/common/premium_gate.dart';

/// The Matches experience — a clean, minimal, vertically-scrolling profile feed.
///
/// After the app header (Logo + Notification), profile summary cards begin
/// immediately — there is NO title row, match-count badge, filter icon or any
/// other top control. Each card shows ONLY a summary (photo, name, age, height,
/// location, education, profession, religion, caste and a single match-quality
/// badge) plus two actions: "Express Interest" and "View Profile". Every other
/// detail lives behind "View Profile". No compatibility percentages are shown.
///
/// Opposite-gender matching is resolved automatically from the signed-in user's
/// gender (Male → Female, Female → Male).
class DiscoverTab extends ConsumerStatefulWidget {
  const DiscoverTab({super.key});

  @override
  ConsumerState<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<DiscoverTab> {
  // Profiles the user has expressed interest in during this session (so the
  // button can flip to "Interest Sent ✓" immediately).
  final Set<String> _interestSent = {};

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Load (or reload) the matches feed. The ONLY mandatory filter is gender
  /// (opposite gender).
  Future<void> _load() async {
    await ref.read(discoverProvider.notifier).load();
  }

  /// Prefetch the next page as the user nears the end of the feed.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      ref.read(discoverProvider.notifier).loadMore();
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────
  Future<void> _sendInterest(ProfileModel profile) async {
    final me = ref.read(myProfileProvider).valueOrNull;
    if (me == null) {
      _snack('Create your profile first to send interest');
      return;
    }
    // Free-plan daily interest limit (2/day). Paid plans are unlimited.
    final features = ref.read(planFeaturesProvider);
    if (!features.hasUnlimitedInterests &&
        ref.read(interestsSentTodayProvider) >= features.interestsPerDay) {
      await showUpgradeDialog(
        context,
        title: 'Daily interest limit reached',
        message:
            'Free members can send ${features.interestsPerDay} interests per day. '
            'Upgrade to Basic or Premium for unlimited interests.',
      );
      return;
    }
    try {
      await ref.read(interestNotifierProvider.notifier).sendInterest(
            senderId: me.userId,
            receiverId: profile.userId,
            senderProfileId: me.id,
            receiverProfileId: profile.id,
          );
      if (!mounted) return;
      setState(() => _interestSent.add(profile.id));
      _snack('Interest sent to ${profile.name}');
    } catch (_) {
      _snack('Could not send interest. Please try again.');
    }
  }

  /// Accept a pending interest the target sent us — turns the pair into a
  /// match right from the card.
  Future<void> _acceptInterest(ProfileModel profile, String interestId) async {
    try {
      await ref
          .read(interestNotifierProvider.notifier)
          .acceptInterest(interestId);
      if (!mounted) return;
      _snack('You matched with ${profile.name}');
    } catch (_) {
      _snack('Could not accept interest. Please try again.');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(discoverProvider);
    var profiles = state.profiles;
    // Hide Interested Profiles (default ON): drop profiles the user has already
    // sent an interest to, so they don't reappear in the feed.
    final hideInterested = ref.watch(hideInterestedProvider);
    if (hideInterested) {
      final sentIds = ref.watch(sentInterestProfileIdsProvider);
      if (sentIds.isNotEmpty) {
        profiles = profiles.where((p) => !sentIds.contains(p.id)).toList();
      }
    }

    // Refresh matches automatically when the profile (incl. partner
    // preferences) changes — e.g. after editing preferences.
    ref.listen<AsyncValue<ProfileModel?>>(myProfileProvider, (prev, next) {
      final p = prev?.valueOrNull;
      final n = next.valueOrNull;
      if (n != null && p != null && !identical(p, n)) {
        ref.read(discoverProvider.notifier).load();
      }
    });

    return Container(
      color: AppColors.scaffoldBg,
      child: Builder(builder: (_) {
        if (state.isLoading && profiles.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (profiles.isEmpty) return _emptyState(state.error != null);

        // A clean vertical feed — profile summary cards begin immediately,
        // with no heading/counter/filter row above the first card.
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            itemCount: profiles.length + (state.isLoadingMore ? 1 : 0),
            itemBuilder: (_, i) {
              if (i >= profiles.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final p = profiles[i];
              return _MatchSummaryCard(
                key: ValueKey(p.id),
                profile: p,
                interestSent: _interestSent.contains(p.id),
                onInterest: () => _sendInterest(p),
                onAccept: (interestId) => _acceptInterest(p, interestId),
              );
            },
          ),
        );
      }),
    );
  }

  Widget _emptyState(bool isError) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Icon(isError ? Icons.cloud_off_outlined : Icons.search_off,
              size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Center(
            child: Text(isError ? 'Could not load matches' : 'No matches found',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
                isError
                    ? 'Check your connection and try again'
                    : 'New members appear here as they join',
                style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ],
      );
}

/// A minimal profile **summary** card for the Matches feed. Shows only the
/// essential summary fields — photo, name, age, height, location, education,
/// profession, religion, caste, a single match-quality badge — and the two
/// actions (Express Interest · View Profile). Full details are only available
/// after tapping "View Profile".
class _MatchSummaryCard extends ConsumerWidget {
  final ProfileModel profile;
  final bool interestSent;
  final VoidCallback onInterest;
  final ValueChanged<String> onAccept;

  const _MatchSummaryCard({
    super.key,
    required this.profile,
    required this.interestSent,
    required this.onInterest,
    required this.onAccept,
  });

  String get _location {
    final native = (profile.nativePlace ?? '').trim();
    if (native.isNotEmpty) return native;
    return [profile.city, profile.state]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
  }

  void _openProfile(BuildContext context) =>
      context.push('/profile/${profile.id}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var status = ref.watch(interestStatusForProfileProvider(profile.id));
    if (status == InterestUiStatus.none && interestSent) {
      status = InterestUiStatus.sent;
    }
    final MatchScore? score = ref.watch(matchScorerProvider)?.call(profile);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Photo with the single match-quality badge ──
          GestureDetector(
            onTap: () => _openProfile(context),
            child: SizedBox(
              height: 230,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  profile.photos.isNotEmpty
                      ? Image.network(
                          profile.photos.first,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          errorBuilder: (_, __, ___) => _photoPlaceholder(),
                          loadingBuilder: (ctx, child, progress) =>
                              progress == null
                                  ? child
                                  : Container(
                                      color: Colors.grey[200],
                                      child: const Center(
                                          child: CircularProgressIndicator())),
                        )
                      : _photoPlaceholder(),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 70,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.35),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (score != null)
                    Positioned(
                        top: 12, left: 12, child: MatchScoreBadge(score: score)),
                ],
              ),
            ),
          ),
          // ── Summary details ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${profile.name}, ${profile.age}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 19),
                ),
                const SizedBox(height: 8),
                if (profile.height.trim().isNotEmpty)
                  _infoLine(Icons.height, profile.height),
                if (_location.isNotEmpty)
                  _infoLine(Icons.location_on_outlined, _location),
                if (profile.education.trim().isNotEmpty)
                  _infoLine(Icons.school_outlined, profile.education),
                if (profile.occupation.trim().isNotEmpty)
                  _infoLine(Icons.work_outline, profile.occupation),
                if (profile.religion.trim().isNotEmpty)
                  _infoLine(Icons.church_outlined, profile.religion),
                if ((profile.caste ?? '').trim().isNotEmpty)
                  _infoLine(Icons.people_outline, profile.caste!),
              ],
            ),
          ),
          // ── Actions: Express Interest · View Profile ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Row(
              children: [
                Expanded(child: _interestButton(context, status)),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openProfile(context),
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: const Text('View Profile'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoPlaceholder() => Container(
        color: const Color(0xFFEFE7D6),
        child: Center(
            child: Icon(Icons.person, size: 80, color: Colors.brown.shade200)),
      );

  Widget _infoLine(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey[500]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: Colors.grey[800])),
            ),
          ],
        ),
      );

  /// Status-aware Express Interest action (mirrors the View Profile screen so a
  /// relationship that already exists never offers a duplicate "Express
  /// Interest").
  Widget _interestButton(BuildContext context, InterestUiStatus status) {
    switch (status) {
      case InterestUiStatus.accepted:
        return _statusButton(
            icon: Icons.check_circle,
            label: 'Matched',
            background: AppColors.success);
      case InterestUiStatus.sent:
        return _statusButton(
            icon: Icons.check,
            label: 'Interest Sent',
            background: Colors.grey.shade500);
      case InterestUiStatus.rejected:
        return _statusButton(
            icon: Icons.cancel,
            label: 'Not Interested',
            background: Colors.grey.shade600);
      case InterestUiStatus.receivedPending:
        return Consumer(builder: (context, ref, _) {
          final pending = ref
              .watch(pendingReceivedInterestFromProfileProvider(profile.id));
          return ElevatedButton.icon(
            onPressed: pending == null ? null : () => onAccept(pending.id),
            icon: const Icon(Icons.favorite, size: 18),
            label: const Text('Accept'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        });
      case InterestUiStatus.none:
        return ElevatedButton.icon(
          onPressed: onInterest,
          icon: const Text('❤️', style: TextStyle(fontSize: 15)),
          label: const Text('Express Interest',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
    }
  }

  Widget _statusButton({
    required IconData icon,
    required String label,
    required Color background,
  }) =>
      ElevatedButton.icon(
        onPressed: null,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          disabledBackgroundColor: background,
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
}
