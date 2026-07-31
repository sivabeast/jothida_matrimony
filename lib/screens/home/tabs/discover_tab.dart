import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../core/utils/value_l10n.dart';
import '../../../models/profile_model.dart';
import '../../../core/services/porutham_match.dart';
import '../../../providers/interest_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/ui_preferences_provider.dart';
import '../../../widgets/common/network_photo.dart';
import '../../../widgets/common/profile_highlight_badge.dart';

/// The Matches experience — a vertically scrolling list of EVERY eligible
/// profile (§8).
///
/// It used to be a one-profile-per-page swipe browser, which is why only a
/// single profile ever appeared on screen. It is now an infinite-scroll LIST:
/// all eligible profiles are shown, the next page is fetched automatically as
/// the user nears the bottom, and the footer says explicitly when the end of
/// the list has been reached. If the database holds 20 dummy profiles, all of
/// the eligible ones are listed here (§9) — Home only previews the latest five.
///
/// A COMPACT single-line card sits above the feed: the user's Nakshatra, a
/// "View Matching Stars" action (bottom sheet listing the nakshatras
/// compatible with theirs) and the number of profiles currently shown.
///
/// Eligibility is decided by [DiscoverNotifier] — opposite gender, not
/// self/married/inactive/blocked, and every partner preference the member
/// actually set (including the mandatory age range, §11). Preference and
/// nakshatra matches are ranked first and highlighted with a badge.
class DiscoverTab extends ConsumerStatefulWidget {
  const DiscoverTab({super.key});

  @override
  ConsumerState<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<DiscoverTab> {
  /// Profiles the user has expressed interest in during this session (so the
  /// button can flip to "Interest Sent ✓" immediately).
  final Set<String> _interestSent = {};

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Load ONLY when the feed is empty — returning to this tab (or rebuilding
    // it) must never refetch and jump the user back to the top.
    Future.microtask(() {
      final st = ref.read(discoverProvider);
      if (st.profiles.isEmpty && !st.isLoading) _load();
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Fetch the next page as the user approaches the bottom, so scrolling never
  /// stops at an artificial "first page" boundary (§8).
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      ref.read(discoverProvider.notifier).loadMore();
    }
  }

  Future<void> _load() => ref.read(discoverProvider.notifier).load();

  /// MANUAL refresh (pull-to-refresh / Refresh button).
  Future<void> _refresh() async {
    await ref.read(discoverProvider.notifier).load();
    if (!mounted) return;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
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
    // The full ranked feed — every profile that passes the matching rules.
    final matched = state.profiles;
    var profiles = matched;
    // Hide Interested Profiles (default ON): drop profiles the user has already
    // sent an interest to, so they don't reappear in the feed.
    final hideInterested = ref.watch(hideInterestedProvider);
    if (hideInterested) {
      final sentIds = ref.watch(sentInterestProfileIdsProvider);
      if (sentIds.isNotEmpty) {
        final remaining =
            matched.where((p) => !sentIds.contains(p.id)).toList();
        // Never let this convenience filter empty the page: if every match has
        // an interest sent, keep showing them rather than dropping the user
        // onto "No Matching Profiles" — there ARE matches, they're just all
        // contacted.
        if (remaining.isNotEmpty) profiles = remaining;
      }
    }

    // Reload the feed when something that actually CHANGES the matching rules
    // changes — the user's own gender/age or their partner preferences.
    //
    // `myProfileProvider` is a live snapshot stream, so it emits a brand-new
    // ProfileModel on EVERY write to the document (a view-count bump, a photo
    // edit, an admin touch...). Reloading on identity alone therefore rebuilt
    // the whole feed constantly.
    ref.listen<AsyncValue<ProfileModel?>>(myProfileProvider, (prev, next) {
      final p = prev?.valueOrNull;
      final n = next.valueOrNull;
      if (n == null || p == null) return;
      if (_matchingSignature(p) != _matchingSignature(n)) _load();
    });

    return Container(
      color: AppColors.scaffoldBg,
      child: Column(
        children: [
          _topCompactCard(profiles.length),
          Expanded(
            child: Builder(builder: (_) {
              if (state.isLoading && profiles.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              // "No Matching Profiles" ONLY when zero profiles in the database
              // pass the matching rules.
              if (profiles.isEmpty) return _emptyState(state.error != null);
              return _profileList(profiles, state);
            }),
          ),
        ],
      ),
    );
  }

  /// Everything about the signed-in member that can change WHO matches them.
  /// Used to decide whether a profile-document update warrants reloading the
  /// feed.
  static String _matchingSignature(ProfileModel p) {
    final pp = p.partnerPreferences;
    return [
      p.gender,
      p.age,
      pp.minAge,
      pp.maxAge,
      pp.minHeight,
      pp.maxHeight,
      pp.religion,
      pp.caste,
      pp.casteId,
      pp.subCaste,
      pp.maritalStatus,
      pp.motherTongue,
      pp.physicalStatus,
      pp.income,
      pp.country,
      pp.state,
      pp.district,
      pp.city,
      pp.rasi,
      pp.nakshatra,
      pp.education.join('|'),
      pp.occupation.join('|'),
    ].join('§');
  }

  // ── Top compact card ──────────────────────────────────────────────────────

  /// Whether the app is currently showing Tamil.
  bool get _isTamil => Localizations.localeOf(context).languageCode == 'ta';

  /// Display name for a 1-27 star index in the active app language.
  String _starName(int star) => _isTamil
      ? AppConstants.nakshatraList[star - 1]
      : AppConstants.nakshatraEnList[star - 1];

  /// A minimal single-line card — the user's Nakshatra, the "View Matching
  /// Stars" action and how many profiles are listed — so profiles start
  /// immediately below without wasted vertical space.
  Widget _topCompactCard(int count) {
    final l10n = context.l10n;
    final me = ref.watch(myProfileProvider).valueOrNull;
    final star = me == null ? null : profileStarIndex(me);

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
              '${l10n.nakshatra}: ${star == null ? '—' : _starName(star)}'
              '${count > 0 ? '  ·  ${l10n.profilesShown(count)}' : ''}',
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
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            child: Text(l10n.viewMatchingStars),
          ),
        ],
      ),
    );
  }

  /// Bottom sheet listing every nakshatra compatible with the user's star.
  void _showMatchingStars() {
    final l10n = context.l10n;
    final me = ref.read(myProfileProvider).valueOrNull;
    final star = me == null ? null : profileStarIndex(me);
    final iAmFemale = (me?.gender ?? '').trim().toLowerCase().startsWith('f');

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
                                    color: AppColors.primary.withOpacity(0.07),
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
                          color: Colors.grey[500], fontSize: 11.5, height: 1.4)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// The vertical, infinite-scrolling list of ALL eligible profiles (§8).
  ///
  /// The last item is a footer: a spinner while the next page loads, or an
  /// explicit "end of list" note once everything has been fetched — so the
  /// member can tell the difference between "still loading" and "that's all".
  Widget _profileList(List<ProfileModel> profiles, DiscoverState state) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        itemCount: profiles.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) {
          if (i == profiles.length) return _listFooter(state);
          final p = profiles[i];
          return _MatchProfileCard(
            key: ValueKey(p.id),
            profile: p,
            interestSent: _interestSent.contains(p.id),
            onInterest: () => _sendInterest(p),
            onAccept: (interestId) => _acceptInterest(p, interestId),
          );
        },
      ),
    );
  }

  Widget _listFooter(DiscoverState state) {
    final l10n = context.l10n;
    if (state.isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            Text(l10n.loadingMoreProfiles,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      );
    }
    if (state.hasMore) return const SizedBox(height: 24);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(l10n.noMoreProfiles,
            style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
      ),
    );
  }

  /// Professional empty state — shown when no profile passes the matching
  /// rules (never a blank page), with a Refresh action.
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
              child: Icon(isError ? Icons.cloud_off_outlined : Icons.search_off,
                  size: 44,
                  color: isError ? Colors.grey[400] : AppColors.primary),
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
                isError ? l10n.checkConnectionRetry : l10n.noMatchingProfilesBody,
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

/// One profile card in the Matches list.
///
/// Layout (top → bottom):
///   • the member's 1:1 photo (tap → full profile) with the match-quality
///     badge — or a neutral placeholder when they hide their photo (§16),
///   • the essential summary (name·age, verification, location, height,
///     education, profession, community),
///   • two equally-sized actions: Express Interest · View Profile.
class _MatchProfileCard extends ConsumerWidget {
  final ProfileModel profile;
  final bool interestSent;
  final VoidCallback onInterest;
  final ValueChanged<String> onAccept;

  const _MatchProfileCard({
    super.key,
    required this.profile,
    required this.interestSent,
    required this.onInterest,
    required this.onAccept,
  });

  // Shared action-button geometry/typography so "Express Interest" and "View
  // Profile" are pixel-for-pixel consistent (height, radius, padding, text).
  static const double _btnHeight = 48;
  static final BorderRadius _btnRadius = BorderRadius.circular(14);
  static const TextStyle _btnTextStyle =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.2);

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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _photo(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summary(context),
                const SizedBox(height: 14),
                _actions(context, status),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Photo ────────────────────────────────────────────────────────────────
  Widget _photo(BuildContext context) {
    // "Hide Profile Photo" is ON by default (§17) — a hidden photo shows a
    // neutral placeholder and is never revealed by an accepted interest.
    final hidden = profile.hidesPhoto;
    final url = hidden ? '' : (profile.profilePhotoUrl ?? '');
    return GestureDetector(
      onTap: () => _openProfile(context),
      child: AspectRatio(
        // 1:1 — the photo is always a square crop (§1).
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetworkPhoto(
              url: url,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              fallbackIcon: Icons.person,
              fallbackIconSize: 88,
              fallbackBg: const Color(0xFFEFE7D6),
              showLoadingSpinner: true,
            ),
            // Soft bottom scrim — adds depth without overlaying any text.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 80,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.26),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              // Green "star match" badge (spec) — no online status, no
              // percentage. Renders only for star-compatible profiles.
              child: ProfileHighlightBadge(
                  profile: profile, color: AppColors.success),
            ),
            if (hidden)
              Positioned(
                bottom: 10,
                left: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline,
                          size: 12, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(context.l10n.photoHiddenByMember,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

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
                '${profile.displayName(context.isTamil)}, ${profile.age}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 19,
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
        const SizedBox(height: 10),
        // Essential fields — each rendered only when present.
        // Free-text (city) / numeric (height) stay as entered; the controlled-
        // vocabulary fields are localized for display via context.localizeValue.
        _infoRow(Icons.location_on_outlined, l10n.location, _location),
        _infoRow(Icons.straighten, l10n.height, profile.height),
        _infoRow(Icons.school_outlined, l10n.education,
            context.localizeValue(profile.education)),
        _infoRow(Icons.work_outline_rounded, l10n.profession,
            context.localizeValue(profile.occupation)),
        _infoRow(Icons.groups_outlined, l10n.community,
            context.localizeValue(profile.caste ?? '')),
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                        letterSpacing: 0.2)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
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
            Icon(icon, size: 18),
            const SizedBox(width: 7),
            Text(label, style: _btnTextStyle),
          ],
        ),
      );
}
