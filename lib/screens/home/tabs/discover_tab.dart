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
import '../../../widgets/common/network_photo.dart';
import '../../../widgets/common/premium_gate.dart';

/// The Matches experience — a modern, swipeable profile browser.
///
/// ONE profile fills the screen at a time. Swiping HORIZONTALLY moves to the
/// previous / next profile (and only that). Each profile is itself VERTICALLY
/// scrollable so the user can scroll down past the photo to read the summary and
/// reach the actions — the two axes never conflict (horizontal → pager,
/// vertical → the profile's own scroll view).
///
/// The page is a PREVIEW only: a large photo plus the essential summary (name,
/// age, location, height, education, profession, religion, community/caste and a
/// verification badge) and two equally-sized actions — "Express Interest" and
/// "View Profile". Everything else (about, family, horoscope, partner
/// preferences, lifestyle, photos, …) lives on the full profile, opened by
/// tapping the photo or "View Profile". No compatibility percentages are shown.
///
/// Opposite-gender matching is resolved automatically from the signed-in user's
/// gender (Male → Female, Female → Male). Caste/community and the preferred age
/// range are MANDATORY filters; every other preference only ranks the results.
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

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Load (or reload) the matches feed and return to the first profile.
  Future<void> _load() async {
    await ref.read(discoverProvider.notifier).load();
    if (mounted && _pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  /// Prefetch the next page as the user nears the end of the pager.
  void _onPageChanged(int index, int count) {
    if (index >= count - 2) {
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
    // preferences) changes — e.g. after editing preferences — and snap back to
    // the first profile.
    ref.listen<AsyncValue<ProfileModel?>>(myProfileProvider, (prev, next) {
      final p = prev?.valueOrNull;
      final n = next.valueOrNull;
      if (n != null && p != null && !identical(p, n)) {
        ref.read(discoverProvider.notifier).load();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
        });
      }
    });

    return Container(
      color: AppColors.scaffoldBg,
      child: Builder(builder: (_) {
        if (state.isLoading && profiles.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (profiles.isEmpty) return _emptyState(state.error != null);
        return _swipeBrowser(profiles);
      }),
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
      onPageChanged: (i) => _onPageChanged(i, count),
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
          onRefresh: _load,
        );
      },
    );
  }

  Widget _emptyState(bool isError) => RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            Icon(isError ? Icons.cloud_off_outlined : Icons.search_off,
                size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Center(
              child: Text(
                  isError ? 'Could not load matches' : 'No matches found',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                  isError
                      ? 'Check your connection and try again'
                      : 'New members appear here as they join',
                  textAlign: TextAlign.center,
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
        ),
      );
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
              _verifiedChip(),
            ],
          ],
        ),
        const SizedBox(height: 14),
        // Essential fields — each rendered only when present.
        _infoRow(Icons.location_on_outlined, 'Location', _location),
        _infoRow(Icons.straighten, 'Height', profile.height),
        _infoRow(Icons.school_outlined, 'Education', profile.education),
        _infoRow(Icons.work_outline_rounded, 'Profession', profile.occupation),
        _infoRow(Icons.temple_hindu_outlined, 'Religion', profile.religion),
        _infoRow(Icons.groups_outlined, 'Community', profile.caste ?? ''),
      ],
    );
  }

  Widget _verifiedChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, size: 14, color: AppColors.success),
            SizedBox(width: 4),
            Text('Verified',
                style: TextStyle(
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
            label: 'View Profile',
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
    switch (status) {
      case InterestUiStatus.accepted:
        return _filledButton(
            icon: Icons.check_circle,
            label: 'Matched',
            onPressed: null,
            background: AppColors.success);
      case InterestUiStatus.sent:
        return _filledButton(
            icon: Icons.check,
            label: 'Interest Sent',
            onPressed: null,
            background: Colors.grey.shade500);
      case InterestUiStatus.rejected:
        return _filledButton(
            icon: Icons.cancel,
            label: 'Not Interested',
            onPressed: null,
            background: Colors.grey.shade600);
      case InterestUiStatus.receivedPending:
        return Consumer(builder: (context, ref, _) {
          final pending = ref
              .watch(pendingReceivedInterestFromProfileProvider(profile.id));
          return _filledButton(
            icon: Icons.favorite,
            label: 'Accept',
            onPressed: pending == null ? null : () => onAccept(pending.id),
            background: AppColors.success,
          );
        });
      case InterestUiStatus.none:
        return _filledButton(
          icon: Icons.favorite_border,
          label: 'Express Interest',
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
