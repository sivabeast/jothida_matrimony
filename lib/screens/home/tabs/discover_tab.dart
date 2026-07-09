import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../models/profile_model.dart';
import '../../../core/services/match_score_service.dart';
import '../../../core/services/porutham_match.dart';
import '../../../providers/interest_provider.dart';
import '../../../providers/matches_prefs_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/ui_preferences_provider.dart';
import '../../../widgets/common/match_score_badge.dart';
import '../../../widgets/common/network_photo.dart';

/// The Matches experience — a modern, swipeable profile browser.
///
/// ONE profile fills the screen at a time. Swiping HORIZONTALLY moves to the
/// previous / next profile (and only that). Each profile is itself VERTICALLY
/// scrollable so the user can scroll down past the photo to read the summary and
/// reach the actions — the two axes never conflict (horizontal → pager,
/// vertical → the profile's own scroll view).
///
/// A COMPACT single-line card sits above the feed: the user's Nakshatra, a
/// "View Matching Stars" action (bottom sheet listing the nakshatras
/// compatible with theirs) and the Filter menu with exactly two modes:
///   • Compatible Matches (DEFAULT) — partner preferences (age + caste
///     mandatory) AND nakshatra compatibility;
///   • All Matches — partner preferences only (compatibility not required).
/// Switching the mode re-filters the already-fetched pool instantly.
///
/// Browsing progress is remembered PER USER: profiles already viewed sort to
/// the end of the feed, so the next session resumes from the first unseen
/// profile instead of restarting at profile 1.
class DiscoverTab extends ConsumerStatefulWidget {
  const DiscoverTab({super.key});

  @override
  ConsumerState<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<DiscoverTab> {
  // Profiles the user has expressed interest in during this session (so the
  // button can flip to "Interest Sent ✓" immediately).
  final Set<String> _interestSent = {};

  // Horizontal pager — one profile per page.
  final PageController _pageController = PageController();

  // The list currently shown by the pager (after the hide-interested filter),
  // so page-change events can record the viewed profile.
  List<ProfileModel> _visible = const [];

  @override
  void initState() {
    super.initState();
    // Load ONLY when the feed is empty — returning to this tab (or rebuilding
    // it) must never reload from the first profile. The persisted per-user
    // browsing progress then resumes from the first unseen profile.
    Future.microtask(() {
      final st = ref.read(discoverProvider);
      if (st.profiles.isEmpty && !st.isLoading) {
        _load();
      } else {
        _jumpToResume();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// The index browsing should CONTINUE from: the first profile the user has
  /// not viewed yet. When every profile has been viewed, the rotation restarts
  /// from profile 1 (and the history is cleared so progress tracks again).
  int _resumeIndex(List<ProfileModel> profiles) {
    if (profiles.isEmpty) return 0;
    final viewed = ref.read(viewedProfilesProvider);
    final idx = profiles.indexWhere((p) => !viewed.contains(p.id));
    if (idx == -1) {
      // Every profile viewed once → restart the rotation from profile 1.
      ref.read(viewedProfilesProvider.notifier).resetHistory();
      return 0;
    }
    return idx;
  }

  /// Snaps the pager to the resume position (post-frame, when attached).
  void _jumpToResume() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      final target = _resumeIndex(_visible);
      if (target != (_pageController.page?.round() ?? 0)) {
        _pageController.jumpToPage(target);
      }
    });
  }

  /// Load the matches feed, then continue from the first unseen profile.
  Future<void> _load() async {
    await ref.read(discoverProvider.notifier).load();
    if (mounted) _jumpToResume();
  }

  /// MANUAL refresh (pull-to-refresh / Refresh button) — reloads and
  /// explicitly resets the browsing position back to the first profile.
  Future<void> _refresh() async {
    await ref.read(discoverProvider.notifier).load();
    if (mounted && _pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  /// Switch between Compatible / All matches. The actual re-filter happens in
  /// the [matchModeProvider] listener in [build], so a mode change from ANY
  /// source (the Filter menu or the persisted choice restoring at startup)
  /// updates the feed instantly without a page refresh.
  Future<void> _setMode(MatchMode mode) =>
      ref.read(matchModeProvider.notifier).set(mode);

  /// Record the viewed profile (per-user browsing progress) and prefetch the
  /// next page as the user nears the end of the pager.
  void _onPageChanged(int index) {
    if (index >= 0 && index < _visible.length) {
      ref
          .read(viewedProfilesProvider.notifier)
          .markViewed(_visible[index].id);
    }
    if (index >= _visible.length - 2) {
      ref.read(discoverProvider.notifier).loadMore();
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────
  Future<void> _sendInterest(ProfileModel profile) async {
    final l10n = context.l10n;
    final me = ref.read(myProfileProvider).valueOrNull;
    if (me == null) {
      _snack(l10n.createProfileFirst);
      return;
    }
    // Sending interests is FREE and unlimited — no plan gate.
    try {
      await ref.read(interestNotifierProvider.notifier).sendInterest(
            senderId: me.userId,
            receiverId: profile.userId,
            senderProfileId: me.id,
            receiverProfileId: profile.id,
          );
      if (!mounted) return;
      setState(() => _interestSent.add(profile.id));
      _snack(l10n.interestSentTo(profile.name));
    } catch (_) {
      _snack(l10n.couldNotSendInterest);
    }
  }

  /// Accept a pending interest the target sent us — turns the pair into a
  /// match right from the card.
  Future<void> _acceptInterest(ProfileModel profile, String interestId) async {
    final l10n = context.l10n;
    try {
      await ref
          .read(interestNotifierProvider.notifier)
          .acceptInterest(interestId);
      if (!mounted) return;
      _snack(l10n.youMatchedWith(profile.name));
    } catch (_) {
      _snack(l10n.couldNotAcceptInterest);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

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
    _visible = profiles;

    // The profile currently on screen counts as viewed (the pager only fires
    // onPageChanged for page 2 onwards) — resume-from-here on the next launch.
    if (profiles.isNotEmpty) {
      final current = _pageController.hasClients
          ? (_pageController.page?.round() ?? 0)
          : 0;
      final shown = profiles[current.clamp(0, profiles.length - 1)];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(viewedProfilesProvider.notifier).markViewed(shown.id);
      });
    }

    // Re-filter the feed instantly (from the cached pool — no page refresh)
    // whenever the match mode changes, then continue from the first unseen
    // profile of the re-filtered list.
    ref.listen<MatchMode>(matchModeProvider, (prev, next) async {
      if (prev == next) return;
      await ref.read(discoverProvider.notifier).refilter();
      if (mounted) _jumpToResume();
    });

    // Refresh matches automatically when the profile (incl. partner
    // preferences) changes — e.g. after editing preferences — resuming from
    // the first unseen profile of the new list.
    ref.listen<AsyncValue<ProfileModel?>>(myProfileProvider, (prev, next) {
      final p = prev?.valueOrNull;
      final n = next.valueOrNull;
      if (n != null && p != null && !identical(p, n)) _load();
    });

    return Container(
      color: AppColors.scaffoldBg,
      child: Column(
        children: [
          _topCompactCard(),
          Expanded(
            child: Builder(builder: (_) {
              if (state.isLoading && profiles.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (profiles.isEmpty) return _emptyState(state.error != null);
              return _swipeBrowser(profiles);
            }),
          ),
        ],
      ),
    );
  }

  // ── Top compact card ──────────────────────────────────────────────────────

  /// Whether the app is currently showing Tamil.
  bool get _isTamil =>
      Localizations.localeOf(context).languageCode == 'ta';

  /// Display name for a 1-27 star index in the active app language.
  String _starName(int star) => _isTamil
      ? AppConstants.nakshatraList[star - 1]
      : AppConstants.nakshatraEnList[star - 1];

  /// A minimal single-line card — the user's Nakshatra, the "View Matching
  /// Stars" action and the Filter menu — so profiles start immediately below
  /// without wasted vertical space.
  Widget _topCompactCard() {
    final l10n = context.l10n;
    final me = ref.watch(myProfileProvider).valueOrNull;
    final star = me == null ? null : profileStarIndex(me);
    final mode = ref.watch(matchModeProvider);

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          const Text('⭐', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${l10n.nakshatra}: ${star == null ? '—' : _starName(star)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: _showMatchingStars,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700),
            ),
            child: Text(l10n.viewMatchingStars),
          ),
          PopupMenuButton<MatchMode>(
            tooltip: l10n.filter,
            position: PopupMenuPosition.under,
            onSelected: _setMode,
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: MatchMode.compatible,
                checked: mode == MatchMode.compatible,
                child: Text(l10n.compatibleMatches,
                    style: const TextStyle(fontSize: 13.5)),
              ),
              CheckedPopupMenuItem(
                value: MatchMode.all,
                checked: mode == MatchMode.all,
                child: Text(l10n.allMatches,
                    style: const TextStyle(fontSize: 13.5)),
              ),
            ],
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.filter_list,
                  size: 19, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom sheet listing every nakshatra compatible with the user's star —
  /// exactly the stars whose profiles can appear in Compatible Matches.
  void _showMatchingStars() {
    final l10n = context.l10n;
    final me = ref.read(myProfileProvider).valueOrNull;
    final star = me == null ? null : profileStarIndex(me);
    final iAmFemale =
        (me?.gender ?? '').trim().toLowerCase().startsWith('f');

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        final stars = star == null
            ? const <int>[]
            : compatibleStarsFor(myStar: star, iAmFemale: iAmFemale);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text('⭐', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l10n.compatibleNakshatras,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Poppins')),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (star == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(l10n.matchingStarsUnavailable,
                        style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13.5,
                            height: 1.4)),
                  )
                else ...[
                  Text('${l10n.nakshatra}: ${_starName(star)}',
                      style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: stars
                            .map((s) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.primary.withOpacity(0.07),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: AppColors.primary
                                            .withOpacity(0.25)),
                                  ),
                                  child: Text(
                                    _starName(s),
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(l10n.compatibleNakshatrasHint,
                      style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 11.5,
                          height: 1.4)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// The horizontal pager: one full-screen, vertically-scrollable profile per
  /// page. Swiping left/right snaps to the previous/next profile only.
  Widget _swipeBrowser(List<ProfileModel> profiles) {
    final count = profiles.length;
    return PageView.builder(
      controller: _pageController,
      // Snap one profile at a time; horizontal only.
      physics: const PageScrollPhysics(),
      itemCount: count,
      onPageChanged: _onPageChanged,
      itemBuilder: (_, i) {
        final p = profiles[i];
        return _MatchProfilePage(
          key: ValueKey(p.id),
          profile: p,
          position: i + 1,
          total: count,
          interestSent: _interestSent.contains(p.id),
          onInterest: () => _sendInterest(p),
          onAccept: (interestId) => _acceptInterest(p, interestId),
          onRefresh: _refresh,
        );
      },
    );
  }

  /// Professional empty state — shown when no profile passes the current
  /// match mode's gates (never a blank page), with a Refresh action.
  Widget _emptyState(bool isError) {
    final l10n = context.l10n;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 56),
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.07),
                shape: BoxShape.circle,
              ),
              child: Icon(
                  isError ? Icons.cloud_off_outlined : Icons.search_off,
                  size: 44,
                  color:
                      isError ? Colors.grey[400] : AppColors.primary),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
                isError
                    ? l10n.couldNotLoadMatches
                    : l10n.noMatchingProfilesTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins')),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
                isError
                    ? l10n.checkConnectionRetry
                    : l10n.noMatchingProfilesBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey[600], fontSize: 13.5, height: 1.5)),
          ),
          const SizedBox(height: 20),
          Center(
            child: OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: Text(isError ? l10n.tryAgain : l10n.refresh),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single full-screen profile PREVIEW inside the swipe browser.
///
/// Layout (top → bottom, vertically scrollable):
///   • a large photo (tap → full profile) with the single match-quality badge
///     and a subtle "position / total" pager pill,
///   • the essential summary (name·age, verification, location, height,
///     education, profession, religion, community/caste),
///   • two equally-sized actions: Express Interest · View Profile.
class _MatchProfilePage extends ConsumerWidget {
  final ProfileModel profile;
  final int position;
  final int total;
  final bool interestSent;
  final VoidCallback onInterest;
  final ValueChanged<String> onAccept;
  final Future<void> Function() onRefresh;

  const _MatchProfilePage({
    super.key,
    required this.profile,
    required this.position,
    required this.total,
    required this.interestSent,
    required this.onInterest,
    required this.onAccept,
    required this.onRefresh,
  });

  // Shared action-button geometry/typography so "Express Interest" and "View
  // Profile" are pixel-for-pixel consistent (height, radius, padding, text).
  static const double _btnHeight = 52;
  static final BorderRadius _btnRadius = BorderRadius.circular(14);
  static const TextStyle _btnTextStyle =
      TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: 0.2);

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

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: LayoutBuilder(builder: (context, constraints) {
        // The photo takes the upper ~58% of the page (clamped so it stays
        // sensible on very short and very tall screens). The rest scrolls.
        final imageHeight =
            (constraints.maxHeight * 0.58).clamp(300.0, 520.0).toDouble();
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            // Fill at least the viewport so the layout looks intentional even
            // when the content is short, and scrolls when it's tall.
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _photo(context, score, imageHeight),
                  const SizedBox(height: 16),
                  _summary(context),
                  const SizedBox(height: 18),
                  _actions(context, status),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  // ── Photo ────────────────────────────────────────────────────────────────
  Widget _photo(BuildContext context, MatchScore? score, double height) {
    return GestureDetector(
      onTap: () => _openProfile(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetworkPhoto(
                url: profile.photos.isNotEmpty ? profile.photos.first : '',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                fallbackIcon: Icons.person,
                fallbackIconSize: 100,
                fallbackBg: const Color(0xFFEFE7D6),
                showLoadingSpinner: true,
              ),
              // Soft bottom scrim — keeps the rounded photo grounded and adds
              // depth without overlaying any text.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 90,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.28),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (score != null)
                Positioned(
                    top: 14, left: 14, child: MatchScoreBadge(score: score)),
              // Pager position pill — orients the user in the swipe stack.
              Positioned(top: 14, right: 14, child: _pagerPill()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pagerPill() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.42),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swipe, size: 13, color: Colors.white),
            const SizedBox(width: 5),
            Text('$position / $total',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  // ── Summary (essential preview info only) ─────────────────────────────────
  Widget _summary(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name, Age + optional verification badge.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                '${profile.name}, ${profile.age}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (profile.isVerified) ...[
              const SizedBox(width: 8),
              _verifiedChip(context),
            ],
          ],
        ),
        const SizedBox(height: 14),
        // Essential fields — each rendered only when present.
        _infoRow(Icons.location_on_outlined, l10n.location, _location),
        _infoRow(Icons.straighten, l10n.height, profile.height),
        _infoRow(Icons.school_outlined, l10n.education, profile.education),
        _infoRow(Icons.work_outline_rounded, l10n.profession,
            profile.occupation),
        _infoRow(Icons.temple_hindu_outlined, l10n.religion, profile.religion),
        _infoRow(Icons.groups_outlined, l10n.community, profile.caste ?? ''),
      ],
    );
  }

  Widget _verifiedChip(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified, size: 14, color: AppColors.success),
            const SizedBox(width: 4),
            Text(context.l10n.verified,
                style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _infoRow(IconData icon, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey[500],
                        letterSpacing: 0.2)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  Widget _actions(BuildContext context, InterestUiStatus status) {
    return Row(
      children: [
        Expanded(child: _interestButton(context, status)),
        const SizedBox(width: 12),
        Expanded(
          child: _outlinedButton(
            icon: Icons.person_outline,
            label: context.l10n.viewProfile,
            onPressed: () => _openProfile(context),
          ),
        ),
      ],
    );
  }

  /// Status-aware Express Interest action (mirrors the View Profile screen so a
  /// relationship that already exists never offers a duplicate "Express
  /// Interest"). Every variant shares the exact button geometry of
  /// [_outlinedButton] so the two actions always line up.
  Widget _interestButton(BuildContext context, InterestUiStatus status) {
    final l10n = context.l10n;
    switch (status) {
      case InterestUiStatus.accepted:
        return _filledButton(
            icon: Icons.check_circle,
            label: l10n.matchedLabel,
            onPressed: null,
            background: AppColors.success);
      case InterestUiStatus.sent:
        return _filledButton(
            icon: Icons.check,
            label: l10n.interestSent,
            onPressed: null,
            background: Colors.grey.shade500);
      case InterestUiStatus.rejected:
        return _filledButton(
            icon: Icons.cancel,
            label: l10n.notInterested,
            onPressed: null,
            background: Colors.grey.shade600);
      case InterestUiStatus.receivedPending:
        return Consumer(builder: (context, ref, _) {
          final pending = ref
              .watch(pendingReceivedInterestFromProfileProvider(profile.id));
          return _filledButton(
            icon: Icons.favorite,
            label: l10n.accept,
            onPressed: pending == null ? null : () => onAccept(pending.id),
            background: AppColors.success,
          );
        });
      case InterestUiStatus.none:
        return _filledButton(
          icon: Icons.favorite_border,
          label: l10n.expressInterest,
          onPressed: onInterest,
          background: AppColors.primary,
        );
    }
  }

  /// A filled action button. [FittedBox] guarantees the icon+label never
  /// overflow when the row is split into two equal halves on narrow screens.
  Widget _filledButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color background,
  }) {
    return SizedBox(
      height: _btnHeight,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: Colors.white,
          disabledBackgroundColor: background,
          disabledForegroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: _btnRadius),
        ),
        child: _buttonContent(icon, label),
      ),
    );
  }

  Widget _outlinedButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: _btnHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: _btnRadius),
        ),
        child: _buttonContent(icon, label),
      ),
    );
  }

  Widget _buttonContent(IconData icon, String label) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19),
            const SizedBox(width: 7),
            Text(label, style: _btnTextStyle),
          ],
        ),
      );
}
