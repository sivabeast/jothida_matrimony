import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/master_location_model.dart';
import '../../../models/profile_model.dart';
import '../../../core/services/match_score_service.dart';
import '../../../providers/interest_provider.dart';
import '../../../providers/master_location_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/subscription_provider.dart';
import '../../../providers/ui_preferences_provider.dart';
import '../../../widgets/common/match_score_badge.dart';
import '../../../widgets/common/premium_gate.dart';
import '../../../widgets/common/searchable_field.dart';

/// The Matches experience — a full-screen, swipeable profile carousel.
///
/// One profile fills the entire area at a time. A horizontal swipe (left/right)
/// moves between matched profiles, while a vertical scroll reveals every detail
/// of the current profile — photos, basic & personal info, education, career,
/// horoscope, family, lifestyle and partner preferences — ending in a single
/// "Express Interest" action. There are no browse-mode tabs, no Skip action and
/// no compatibility percentages — only a clean match-quality badge.
///
/// Horizontal scroll = switch profiles · Vertical scroll = view current profile.
///
/// Opposite-gender matching is resolved automatically from the signed-in user's
/// gender (Male → Female, Female → Male) — there is no manual toggle.
class DiscoverTab extends ConsumerStatefulWidget {
  const DiscoverTab({super.key});

  @override
  ConsumerState<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<DiscoverTab> {
  // Drives the horizontal profile carousel (one full-screen profile per page).
  final PageController _pageController = PageController();

  // Profiles the user has expressed interest in during this session (so the
  // button can flip to "Interest Sent ✓" immediately).
  final Set<String> _interestSent = {};

  // Currently applied optional filters (gender restriction is always separate).
  MatchFilters _filters = const MatchFilters();

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

  /// Load (or reload) the matches feed. The ONLY mandatory filter is gender
  /// (opposite gender); optional [MatchFilters] are applied on top.
  Future<void> _load() async {
    await ref.read(discoverProvider.notifier).load();
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

  /// Open the optional-filters bottom sheet, then apply the result.
  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<MatchFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterMatchesSheet(initial: _filters),
    );
    if (result == null || !mounted) return;
    setState(() => _filters = result);
    await ref.read(discoverProvider.notifier).applyFilters(result);
    // Reset the carousel to the first match of the freshly filtered feed.
    if (mounted && _pageController.hasClients) {
      _pageController.jumpToPage(0);
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
    final total = profiles.length;

    // Refresh matches automatically when the profile (incl. partner
    // preferences) changes — e.g. after editing preferences.
    ref.listen<AsyncValue<ProfileModel?>>(myProfileProvider, (prev, next) {
      final p = prev?.valueOrNull;
      final n = next.valueOrNull;
      if (n != null && p != null && !identical(p, n)) {
        ref.read(discoverProvider.notifier).load();
      }
    });

    final me = ref.watch(myProfileProvider).valueOrNull;
    final showPrefReminder = me != null && !partnerPreferencesComplete(me);

    return Container(
      color: AppColors.scaffoldBg,
      child: Column(
        children: [
          _topBar(total),
          if (showPrefReminder) _partnerPrefBanner(context),
          Expanded(
            child: Builder(builder: (_) {
              if (state.isLoading && profiles.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (profiles.isEmpty) return _emptyState(state.error != null);

              // Full-screen, horizontally-swipeable carousel: one profile per
              // page. Horizontal swipe = switch profiles; the per-profile page
              // scrolls vertically on its own, so the two gestures never clash.
              return PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.horizontal,
                itemCount: total,
                onPageChanged: (i) {
                  // Prefetch the next batch as the user nears the end.
                  if (i >= total - 3) {
                    ref.read(discoverProvider.notifier).loadMore();
                  }
                },
                itemBuilder: (_, i) => _MatchProfilePage(
                  key: ValueKey(profiles[i].id),
                  profile: profiles[i],
                  interestSent: _interestSent.contains(profiles[i].id),
                  onInterest: () => _sendInterest(profiles[i]),
                  onAccept: (interestId) =>
                      _acceptInterest(profiles[i], interestId),
                  onRefresh: _load,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Top bar: title · "N Matches" · filter ────────────────────────────────
  Widget _topBar(int total) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      color: Colors.white,
      child: Row(
        children: [
          const Text('Matches',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
          const SizedBox(width: 10),
          if (total > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(total == 1 ? '1 Match' : '$total Matches',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
          const Spacer(),
          // Filter — opens the optional "Filter Matches" sheet. A gold dot marks
          // that one or more filters are active.
          IconButton(
            onPressed: _openFilters,
            tooltip: 'Filter Matches',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.tune, color: AppColors.primary),
                if (_filters.isActive)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
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

  /// Shown when the user hasn't set partner preferences — matches stay broad
  /// until they do, so nudge them to narrow it down for better matches.
  Widget _partnerPrefBanner(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: AppColors.gold.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.gold.withOpacity(0.45)),
        ),
        child: Row(
          children: [
            const Icon(Icons.favorite_border, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Complete your Partner Preferences to receive better matches.',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
              ),
            ),
            TextButton(
              onPressed: () => context.push('/partner-preferences'),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact),
              child: const Text('Set'),
            ),
          ],
        ),
      );

  Widget _emptyState(bool isError) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Icon(isError ? Icons.cloud_off_outlined : Icons.search_off,
              size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Center(
            child: Text(isError ? 'Could not load matches' : 'No matches found',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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

/// A full-screen, single-profile page used inside the Matches carousel.
///
/// The whole page scrolls vertically to reveal every section of the profile —
/// a dominant photo header (with match-quality + horoscope badges), basic and
/// personal details, education & career, location, horoscope, family, lifestyle
/// and partner preferences — while a pinned bottom bar keeps the single
/// "Express Interest" action always in reach. There is NO match percentage and
/// NO Skip button. Horizontal swipes between pages are handled by the parent
/// PageView; this page only ever scrolls vertically, so the gestures never
/// conflict.
class _MatchProfilePage extends ConsumerStatefulWidget {
  final ProfileModel profile;
  final bool interestSent;
  final VoidCallback onInterest;
  final ValueChanged<String> onAccept;
  final Future<void> Function() onRefresh;

  const _MatchProfilePage({
    super.key,
    required this.profile,
    required this.interestSent,
    required this.onInterest,
    required this.onAccept,
    required this.onRefresh,
  });

  @override
  ConsumerState<_MatchProfilePage> createState() => _MatchProfilePageState();
}

class _MatchProfilePageState extends ConsumerState<_MatchProfilePage> {
  // Index of the photo currently shown in the header gallery.
  int _photoIndex = 0;

  ProfileModel get profile => widget.profile;

  String get _placeLine {
    final native = (profile.nativePlace ?? '').trim();
    if (native.isNotEmpty) return native;
    return [profile.city, profile.state]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
  }

  void _openProfile() => context.push('/profile/${profile.id}');

  @override
  Widget build(BuildContext context) {
    var status = ref.watch(interestStatusForProfileProvider(profile.id));
    if (status == InterestUiStatus.none && widget.interestSent) {
      status = InterestUiStatus.sent;
    }
    final MatchScore? score = ref.watch(matchScorerProvider)?.call(profile);

    return Column(
      children: [
        // ── Vertically-scrolling profile body (the whole page) ─────────────
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: widget.onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                _photoHeader(context, score),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: _identityBlock(),
                ),
                ..._detailSections(),
                // Breathing room so the last section clears the pinned bar.
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        // ── Pinned Express Interest action (status-aware, no Skip) ─────────
        _bottomActionBar(context, status),
      ],
    );
  }

  // ── Photo header ─────────────────────────────────────────────────────────
  /// Edge-to-edge photo header (~52% of the screen). Tapping the left/right
  /// half steps between photos — deliberately tap-based (not a nested
  /// horizontal PageView) so it never fights the parent profile-swipe gesture.
  Widget _photoHeader(BuildContext context, MatchScore? score) {
    final photos = profile.photos;
    final height = MediaQuery.of(context).size.height * 0.52;
    final index = photos.isEmpty ? 0 : _photoIndex.clamp(0, photos.length - 1);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photos.isEmpty)
            _photoPlaceholder()
          else
            Image.network(
              photos[index],
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, __, ___) => _photoPlaceholder(),
              loadingBuilder: (ctx, child, progress) => progress == null
                  ? child
                  : Container(
                      color: Colors.grey[200],
                      child:
                          const Center(child: CircularProgressIndicator())),
            ),
          // Left / right tap zones to step through photos.
          if (photos.length > 1)
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => setState(() {
                      _photoIndex = (index - 1 + photos.length) % photos.length;
                    }),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => setState(() {
                      _photoIndex = (index + 1) % photos.length;
                    }),
                  ),
                ),
              ],
            ),
          // Subtle bottom gradient so the name/badges stay legible.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 120,
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
          // A single match-quality badge (top-left), derived from the final
          // calculated match %. Never two badges on one card.
          if (score != null)
            Positioned(top: 14, left: 14, child: MatchScoreBadge(score: score)),
          // Photo dots indicator.
          if (photos.length > 1)
            Positioned(
              bottom: 14,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  photos.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == index ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == index
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _photoPlaceholder() => Container(
        color: const Color(0xFFEFE7D6),
        child: Center(
            child: Icon(Icons.person, size: 96, color: Colors.brown.shade200)),
      );

  // ── Identity block (name · age · key lines) ──────────────────────────────
  Widget _identityBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                '${profile.name}, ${profile.age}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 22),
              ),
            ),
            if (profile.isVerified) ...[
              const SizedBox(width: 6),
              const Icon(Icons.verified, size: 20, color: AppColors.primary),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (_placeLine.isNotEmpty)
          _infoLine(Icons.location_on_outlined, _placeLine),
        if (profile.education.trim().isNotEmpty)
          _infoLine(Icons.school_outlined, profile.education),
        if (profile.occupation.trim().isNotEmpty)
          _infoLine(Icons.work_outline, profile.occupation),
      ],
    );
  }

  Widget _infoLine(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey[500]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: Colors.grey[800])),
            ),
          ],
        ),
      );

  // ── Detail sections ──────────────────────────────────────────────────────
  /// Every detail section, in matrimony reading order. Empty sections render
  /// nothing, so a sparse profile never shows blank cards or overflow.
  List<Widget> _detailSections() {
    final h = profile.horoscope;
    final f = profile.family;
    final l = profile.lifestyle;
    final p = profile.partnerPreferences;

    return [
      // About / Additional information.
      if (profile.about.trim().isNotEmpty) _aboutSection(profile.about),
      // Basic & personal details.
      _section('Basic Details', [
        _Item(Icons.cake_outlined, 'Age', '${profile.age} years'),
        _Item(Icons.height, 'Height', profile.height),
        _Item(Icons.monitor_weight_outlined, 'Weight', profile.weight),
        _Item(Icons.wc, 'Marital Status', profile.maritalStatus),
        _Item(Icons.translate, 'Mother Tongue', profile.motherTongue),
        _Item(Icons.accessibility_new, 'Physical Status',
            profile.physicalStatus),
      ]),
      _section('Personal Information', [
        _Item(Icons.church_outlined, 'Religion', profile.religion),
        _Item(Icons.people_outline, 'Caste', profile.caste ?? ''),
        _Item(Icons.groups_2_outlined, 'Sub-caste', profile.subCaste ?? ''),
        _Item(Icons.account_balance_outlined, 'Gothram', profile.gothram),
        _Item(Icons.auto_awesome_outlined, 'Kuladeivam', profile.kuladeivam),
        _Item(Icons.location_city_outlined, 'Native Place',
            profile.nativePlace ?? ''),
        _Item(Icons.public, 'Citizenship', profile.citizenship ?? ''),
      ]),
      // Education.
      _section('Education', [
        _Item(Icons.school_outlined, 'Education', profile.education),
        _Item(Icons.account_balance, 'College', profile.collegeName ?? ''),
      ]),
      // Occupation.
      _section('Occupation', [
        _Item(Icons.work_outline, 'Occupation', profile.occupation),
        _Item(Icons.badge_outlined, 'Employment Type', profile.employmentType),
        _Item(Icons.business_outlined, 'Company', profile.companyName ?? ''),
        _Item(Icons.place_outlined, 'Work Location', profile.workLocation ?? ''),
        _Item(Icons.payments_outlined, 'Annual Income', profile.annualIncome),
      ]),
      // Location.
      _section('Location', [
        _Item(Icons.location_city, 'City', profile.city),
        _Item(Icons.map_outlined, 'District', profile.district),
        _Item(Icons.terrain_outlined, 'State', profile.state),
        _Item(Icons.flag_outlined, 'Country', profile.country),
      ]),
      // Horoscope — only Rasi & Nakshatra are public (full chart stays private,
      // matching the detailed Profile screen's privacy rules).
      _section('Horoscope Details', [
        _Item(Icons.stars, 'Rasi', h.rasi),
        _Item(Icons.star_border, 'Nakshatra', h.nakshatra),
      ]),
      // Family.
      _section('Family Details', [
        _Item(Icons.man_outlined, 'Father', f.fatherName),
        _Item(Icons.work_history_outlined, "Father's Occupation",
            f.fatherOccupation),
        _Item(Icons.woman_outlined, 'Mother', f.motherName),
        _Item(Icons.work_history_outlined, "Mother's Occupation",
            f.motherOccupation),
        _Item(Icons.group_outlined, 'Brothers',
            f.brothersCount > 0 ? '${f.brothersCount}' : ''),
        _Item(Icons.group_outlined, 'Sisters',
            f.sistersCount > 0 ? '${f.sistersCount}' : ''),
        _Item(Icons.family_restroom, 'Family Type', f.familyType),
        _Item(Icons.diamond_outlined, 'Family Status', f.familyStatus),
      ]),
      if (f.aboutFamily.trim().isNotEmpty)
        _aboutSection(f.aboutFamily, title: 'About Family'),
      // Lifestyle (additional information).
      _section('Lifestyle', [
        _Item(Icons.restaurant_outlined, 'Eating Habit', l.eatingHabit),
        _Item(Icons.smoke_free, 'Smoking', l.smokingHabit),
        _Item(Icons.no_drinks_outlined, 'Drinking', l.drinkingHabit),
        _Item(Icons.sports_esports_outlined, 'Hobbies', l.hobbies),
        _Item(Icons.interests_outlined, 'Interests', l.interests),
        _Item(Icons.translate, 'Languages Known', l.languagesKnown.join(', ')),
      ]),
      // Partner preferences.
      _section('Partner Preferences', [
        _Item(Icons.cake_outlined, 'Age', '${p.minAge} - ${p.maxAge} yrs'),
        _Item(Icons.height, 'Height', '${p.minHeight} - ${p.maxHeight}'),
        if (p.education.isNotEmpty)
          _Item(Icons.school_outlined, 'Education', p.education.join(', ')),
        if (p.occupation.isNotEmpty)
          _Item(Icons.work_outline, 'Occupation', p.occupation.join(', ')),
        if (p.income != 'Any')
          _Item(Icons.payments_outlined, 'Income', p.income),
        if (p.religion != 'Any')
          _Item(Icons.church_outlined, 'Religion', p.religion),
        if ((p.caste ?? '').trim().isNotEmpty)
          _Item(Icons.people_outline, 'Caste', p.caste!),
        if (p.maritalStatus != 'Any')
          _Item(Icons.wc, 'Marital Status', p.maritalStatus),
        if (p.motherTongue != 'Any')
          _Item(Icons.translate, 'Mother Tongue', p.motherTongue),
        _Item(Icons.auto_awesome, 'Horoscope Match',
            p.horoscopeMatchRequired ? 'Required' : 'Not required'),
      ]),
      // Quick path to the detailed profile (report, contact reveal once
      // matched, family tree, consult astrologer all live there).
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: OutlinedButton.icon(
          onPressed: _openProfile,
          icon: const Icon(Icons.open_in_full, size: 18),
          label: const Text('View Full Profile'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            minimumSize: const Size.fromHeight(46),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    ];
  }

  /// A titled "card" of label → value rows. Rows with empty values are hidden,
  /// and the whole section disappears when every row is empty.
  Widget _section(String title, List<_Item> items) {
    final visible = items.where((i) => i.value.trim().isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(title),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Colors.grey[200]),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(visible[i].icon,
                            size: 20, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(visible[i].label,
                              style: const TextStyle(
                                  fontSize: 12.5, color: Colors.grey)),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            visible[i].value,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutSection(String text, {String title = 'About'}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(title),
            const SizedBox(height: 8),
            Text(text,
                style: TextStyle(
                    fontSize: 14, height: 1.45, color: Colors.grey[800])),
          ],
        ),
      );

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 15,
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: AppColors.primary),
      );

  // ── Pinned bottom action bar ─────────────────────────────────────────────
  Widget _bottomActionBar(BuildContext context, InterestUiStatus status) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: _interestButton(context, status),
        ),
      ),
    );
  }

  Widget _interestButton(BuildContext context, InterestUiStatus status) {
    switch (status) {
      case InterestUiStatus.accepted:
        return _statusButton(
            icon: Icons.check_circle,
            label: '✓ Matched',
            background: AppColors.success);
      case InterestUiStatus.sent:
        return _statusButton(
            icon: Icons.check,
            label: '✓ Interest Sent',
            background: Colors.grey.shade500);
      case InterestUiStatus.rejected:
        return _statusButton(
            icon: Icons.cancel,
            label: 'Not Interested',
            background: Colors.grey.shade600);
      case InterestUiStatus.receivedPending:
        final pending =
            ref.watch(pendingReceivedInterestFromProfileProvider(profile.id));
        return ElevatedButton.icon(
          onPressed: pending == null ? null : () => widget.onAccept(pending.id),
          icon: const Icon(Icons.favorite, size: 20),
          label: const Text('Accept Interest'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      case InterestUiStatus.none:
        return ElevatedButton.icon(
          onPressed: widget.onInterest,
          icon: const Text('❤️', style: TextStyle(fontSize: 18)),
          label: const Text('Express Interest',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            elevation: 3,
            shadowColor: AppColors.primary.withOpacity(0.4),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
        icon: Icon(icon, size: 20),
        label: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          disabledBackgroundColor: background,
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
}

/// One label → value row inside a profile detail section.
class _Item {
  final IconData icon;
  final String label;
  final String value;
  const _Item(this.icon, this.label, this.value);
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter Matches — optional, multi-field filter bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

/// The "Filter Matches" bottom sheet. Every field is OPTIONAL — leaving one
/// empty ignores that filter. Returns the chosen [MatchFilters] on Apply, or
/// `const MatchFilters()` on Reset; returns `null` if dismissed without action.
class _FilterMatchesSheet extends ConsumerStatefulWidget {
  final MatchFilters initial;
  const _FilterMatchesSheet({required this.initial});

  @override
  ConsumerState<_FilterMatchesSheet> createState() =>
      _FilterMatchesSheetState();
}

class _FilterMatchesSheetState extends ConsumerState<_FilterMatchesSheet> {
  int? _minAge;
  int? _maxAge;
  String? _state;
  String? _district;
  String? _city;
  String? _religion;
  String? _caste;
  String? _education;
  String? _occupation;
  String? _maritalStatus;
  String? _rasi;
  String? _nakshatra;
  String? _matchQuality;

  static final List<String> _ages = [for (var i = 18; i <= 70; i++) '$i'];
  static const List<String> _maritalStatuses = [
    'Never Married',
    'Divorced',
    'Widowed',
  ];
  static const List<String> _matchQualities = [
    'Excellent Match',
    'Good Match',
    'Average Match',
  ];

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    _minAge = f.minAge;
    _maxAge = f.maxAge;
    _state = f.state;
    _district = f.district;
    _city = f.city;
    _religion = f.religion;
    _caste = f.caste;
    _education = f.education;
    _occupation = f.occupation;
    _maritalStatus = f.maritalStatus;
    _rasi = f.rasi;
    _nakshatra = f.nakshatra;
    _matchQuality = f.matchQuality;
  }

  void _reset() {
    setState(() {
      _minAge = _maxAge = null;
      _state = _district = _city = null;
      _religion = _caste = _education = _occupation = null;
      _maritalStatus = _rasi = _nakshatra = _matchQuality = null;
    });
  }

  /// "Hide Interested Profiles" switch (default ON). Toggles the persisted
  /// [hideInterestedProvider] directly — it is not part of [MatchFilters].
  Widget _hideInterestedTile() {
    final hide = ref.watch(hideInterestedProvider);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SwitchListTile(
        value: hide,
        activeColor: AppColors.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        title: const Text('Hide Interested Profiles',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: const Text(
            'Profiles you’ve sent interest to won’t appear in the feed',
            style: TextStyle(fontSize: 11.5)),
        onChanged: (v) => ref.read(hideInterestedProvider.notifier).set(v),
      ),
    );
  }

  /// A locked filter row shown to Free members; tapping opens the upgrade sheet.
  Widget _lockedFilterTile(String label, String message) {
    return InkWell(
      onTap: () =>
          showUpgradeDialog(context, title: '$label locked', message: message),
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon:
              const Icon(Icons.lock_outline, color: AppColors.primary),
        ),
        child: Text('Premium feature — tap to upgrade',
            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      ),
    );
  }

  void _apply() {
    // Normalise the age range so a swapped min/max never yields an empty feed.
    var lo = _minAge, hi = _maxAge;
    if (lo != null && hi != null && lo > hi) {
      final t = lo;
      lo = hi;
      hi = t;
    }
    Navigator.pop(
      context,
      MatchFilters(
        minAge: lo,
        maxAge: hi,
        state: _state,
        district: _district,
        city: _city,
        religion: _religion,
        caste: _caste,
        education: _education,
        occupation: _occupation,
        maritalStatus: _maritalStatus,
        rasi: _rasi,
        nakshatra: _nakshatra,
        matchQuality: _matchQuality,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── Dependent location options (State → District → City) ──
    final states =
        ref.watch(statesProvider).valueOrNull ?? const <MasterState>[];
    final stateNames = states.map((s) => s.name).toList();
    final stateId =
        _idForName<MasterState>(states, _state, (s) => s.name, (s) => s.id);

    final districts = stateId == null
        ? const <MasterDistrict>[]
        : (ref.watch(districtsProvider(stateId)).valueOrNull ??
            const <MasterDistrict>[]);
    final districtNames = districts.map((d) => d.name).toList();
    final districtId = _idForName<MasterDistrict>(
        districts, _district, (d) => d.name, (d) => d.id);

    final List<String> cityNames = districtId != null
        ? ((ref.watch(citiesProvider(districtId)).valueOrNull ??
                const <MasterCity>[])
            .map((c) => c.name)
            .toList())
        : (ref.watch(allCityNamesProvider).valueOrNull ?? const <String>[]);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.scaffoldBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(3)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.tune, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text('Filter Matches',
                      style: TextStyle(
                          fontSize: 18,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('All optional',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  _groupLabel('Feed Options'),
                  _hideInterestedTile(),
                  const SizedBox(height: 8),
                  _groupLabel('Age Range'),
                  Row(
                    children: [
                      Expanded(
                        child: _dropdown('Min Age', _ages, _minAge?.toString(),
                            (v) => setState(() {
                                  _minAge = v == null ? null : int.tryParse(v);
                                })),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _dropdown('Max Age', _ages, _maxAge?.toString(),
                            (v) => setState(() {
                                  _maxAge = v == null ? null : int.tryParse(v);
                                })),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _groupLabel('Location'),
                  _dropdown('State', stateNames, _state, (v) => setState(() {
                        _state = v;
                        _district = null; // dependent fields reset
                        _city = null;
                      })),
                  const SizedBox(height: 12),
                  _dropdown('District', districtNames, _district,
                      (v) => setState(() {
                            _district = v;
                            _city = null;
                          })),
                  const SizedBox(height: 12),
                  _dropdown('City', cityNames, _city,
                      (v) => setState(() => _city = v)),
                  const SizedBox(height: 8),
                  _groupLabel('Community'),
                  _dropdown('Religion', AppConstants.religionList, _religion,
                      (v) => setState(() => _religion = v)),
                  const SizedBox(height: 12),
                  _dropdown('Caste', AppConstants.castList, _caste,
                      (v) => setState(() => _caste = v)),
                  const SizedBox(height: 8),
                  _groupLabel('Education & Career'),
                  _dropdown('Education', AppConstants.educationList, _education,
                      (v) => setState(() => _education = v)),
                  const SizedBox(height: 12),
                  _dropdown('Occupation', AppConstants.occupations, _occupation,
                      (v) => setState(() => _occupation = v)),
                  const SizedBox(height: 8),
                  _groupLabel('Marital Status'),
                  _dropdown('Marital Status', _maritalStatuses, _maritalStatus,
                      (v) => setState(() => _maritalStatus = v)),
                  const SizedBox(height: 8),
                  _groupLabel('Horoscope'),
                  _dropdown('Rasi', AppConstants.rasiList, _rasi,
                      (v) => setState(() => _rasi = v)),
                  const SizedBox(height: 12),
                  _dropdown('Nakshatra', AppConstants.nakshatraList, _nakshatra,
                      (v) => setState(() => _nakshatra = v)),
                  const SizedBox(height: 12),
                  // Horoscope (porutham) match-quality filter — a paid feature.
                  if (ref.watch(planFeaturesProvider).canUseHoroscopeMatchFilter)
                    _dropdown('Match Quality', _matchQualities, _matchQuality,
                        (v) => setState(() => _matchQuality = v))
                  else
                    _lockedFilterTile(
                      'Match Quality',
                      'Horoscope match filter is available on Basic & Premium.',
                    ),
                ],
              ),
            ),
            // ── Reset / Apply ──
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _reset,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          side: BorderSide(color: Colors.grey[400]!),
                          foregroundColor: AppColors.primary,
                        ),
                        child: const Text('Reset Filters'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _apply,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: const Text('Apply Filters'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Id of the first master entry whose name matches [name] (case-insensitive).
  String? _idForName<T>(List<T> list, String? name, String Function(T) getName,
      String Function(T) getId) {
    if (name == null || name.trim().isEmpty) return null;
    for (final e in list) {
      if (getName(e).trim().toLowerCase() == name.trim().toLowerCase()) {
        return getId(e);
      }
    }
    return null;
  }

  Widget _groupLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.primary)),
      );

  Widget _dropdown(String label, List<String> items, String? value,
          ValueChanged<String?> onChanged) =>
      SearchableField(
        label: label,
        items: items,
        selectedItem: value,
        popupMode: SearchablePopupMode.modalBottomSheet,
        onChanged: onChanged,
      );
}
