import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/data/muhurtham_dates.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../core/utils/profile_completion.dart';
import '../../../core/utils/value_l10n.dart';
import '../../../models/banner_model.dart';
import '../../../models/interest_model.dart';
import '../../../models/muhurtham_model.dart';
import '../../../models/profile_model.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/announcement_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/banner_provider.dart';
import '../../auth/login_required_screen.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/interest_provider.dart';
import '../../../providers/navigation_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/wedding_provider.dart';
import '../../../widgets/common/auto_fit_label.dart';
import '../../../widgets/common/coming_soon.dart';
import '../../../widgets/common/create_profile_cta.dart';
import '../../../widgets/common/face_centered_photo.dart';
import '../../../widgets/common/network_photo.dart';
import '../../../widgets/common/skeletons.dart';
import '../../../widgets/home/home_banner_slide.dart';
import '../../../widgets/profile/verification_tick.dart';

// ── Shared card styling — every home card uses the SAME radius, shadow and
//    padding so the page reads as one system (spec: home cards consistency).
const double _kCardRadius = 16;
const List<BoxShadow> _kCardShadow = [
  BoxShadow(
    color: Color(0x0D000000), // black @ 5%
    blurRadius: 10,
    offset: Offset(0, 4),
  ),
];

/// Home dashboard tab. Clean, modern flow:
///   Header → Profile Completion · Find Your Life Partner · Upgrade To Premium
///   (compact notification-style cards) → Recommended Profiles → Recent
///   Interests → Astrologers. No compatibility percentages are shown anywhere.
class HomeDashboardTab extends ConsumerStatefulWidget {
  const HomeDashboardTab({super.key});

  @override
  ConsumerState<HomeDashboardTab> createState() => _HomeDashboardTabState();
}

class _HomeDashboardTabState extends ConsumerState<HomeDashboardTab> {
  final PageController _bannerCtrl = PageController();
  int _bannerPage = 0;
  Timer? _bannerTimer;

  /// How many slides the carousel currently shows — ONLY admin-published
  /// banners. Kept as a field so the auto-scroll timer always wraps at the
  /// LIVE count. There are no built-in / demo / fallback banners: when the
  /// admin has published none the carousel is not rendered at all.
  int _bannerCount = 0;

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerCtrl.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _bannerCount <= 1 || !_bannerCtrl.hasClients) return;
      final next = (_bannerPage + 1) % _bannerCount;
      _bannerCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Home is ONLY for discovering newly-joined members (spec). The full
    // matching directory lives on the Matches tab.
    final myProfileAsync = ref.watch(myProfileProvider);
    final myProfile = myProfileAsync.valueOrNull;
    // A member without a matrimony profile sees NO profiles anywhere on Home —
    // no recommendations, no newly-joined members, no received interests — just
    // the premium "Create Profile" call-to-action. While the profile document is
    // still loading we withhold the sections too, so nothing flashes in and out.
    final hasProfile = myProfile != null;
    final newProfilesAsync = hasProfile
        ? ref.watch(newProfilesProvider)
        : const AsyncValue<List<ProfileModel>>.data([]);

    // Automatic "Married" status: once the wedding date passes, the couple
    // member's profile leaves matchmaking. The sweep no-ops unless due.
    ref.listen(myCoupleWeddingProvider, (_, next) {
      final wedding = next.valueOrNull;
      if (wedding != null) {
        ref
            .read(weddingControllerProvider.notifier)
            .runMarriedSweepIfDue(wedding);
      }
    });

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(newProfilesProvider),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Curved luxury header + overlapping hero banner ────────────────
          _buildHeaderBanner(context),
          const SizedBox(height: 18),

          // ── Guest Mode strip (§13) — renders itself only for an anonymous
          //    session, so it costs nothing for a signed-in member. ──────────
          const GuestModeBanner(),

          // ── Profile Under Review — shown only while the member's profile is
          //    awaiting admin approval. Streams off myProfileProvider, so it
          //    disappears the moment the status changes. ─────────────────────
          if (myProfile != null &&
              (myProfile.status == 'pending' ||
                  myProfile.status == 'rejected')) ...[
            _buildPendingReviewBanner(context,
                rejected: myProfile.status == 'rejected'),
            const SizedBox(height: 18),
          ],

          // ── Quick actions — one-tap access to the core journeys ───────────
          _buildQuickActions(context),
          const SizedBox(height: 18),

          // ── No profile yet → the premium Create Profile call-to-action, in
          //    place of every matrimony profile section below. Withheld while
          //    the profile doc is still loading so it never flashes for
          //    members who DO have a profile. ─────────────────────────────────
          if (!hasProfile && !myProfileAsync.isLoading) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: CreateProfileCta(),
            ),
          ],

          // ── Wedding Workspace (only once a wedding exists) ────────────────
          _buildWeddingCard(context),

          // ── Info cards: Muhurtham | Profile Completion (side by side) ─────
          _buildInfoCardsRow(context, myProfile),

          // ── Trust / feature highlights ───────────────────────────────────
          _buildFeatureHighlights(context),

          // ── Compact notification-style action cards ───────────────────────
          ..._buildActionCards(context, myProfile),
          const SizedBox(height: 8),

          // Matrimony profiles are shown ONLY to members who have a profile.
          if (hasProfile) ...[
            // ── New Profiles (newly joined members) ─────────────────────────
            _buildNewProfiles(context, newProfilesAsync),
            const SizedBox(height: 22),

            // ── Recent Interests ────────────────────────────────────────────
            _buildRecentInterests(context),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Curved header + overlapping banner ─────────────────────────────────────

  /// The admin-published banners (Banner Management). Empty = the Home page
  /// shows NO banner at all (no default, demo or fallback artwork).
  List<HomeBannerModel> get _remoteBanners =>
      ref.watch(activeBannersProvider).valueOrNull ?? const [];

  /// Carousel height as a fraction of its width — FIXED to the official Home
  /// banner shape ([kBannerAspectRatio]); admin banners are produced/validated
  /// at exactly this shape, so there is no per-banner height any more.
  double get _bannerRatio => kBannerAspectRatio;

  /// A premium curved maroon header (profile + name on the left, a single
  /// notification bell on the right) whose background extends behind the hero
  /// banner. The banner is positioned to overlap the curve so the two feel like
  /// one connected, elevated unit.
  Widget _buildHeaderBanner(BuildContext context) {
    final media = MediaQuery.of(context);
    final topPad = media.padding.top;
    const headerRowHeight = 56.0;
    final bannerWidth = media.size.width - 24;
    // No admin banner published -> the carousel collapses to nothing and the
    // curved header shrinks to just the profile/bell row, leaving no empty gap.
    final hasBanner = _remoteBanners.isNotEmpty;
    final bannerHeight = hasBanner ? bannerWidth * _bannerRatio : 0.0;
    final bannerTop = topPad + headerRowHeight + 10;
    final headerBgHeight =
        hasBanner ? bannerTop + bannerHeight * 0.45 : bannerTop + 12;
    final totalHeight =
        hasBanner ? bannerTop + bannerHeight + 28 : headerBgHeight + 8;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light, // white status-bar icons over maroon
      child: SizedBox(
        height: totalHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipPath(
              clipper: _HeaderCurveClipper(),
              child: Container(
                height: headerBgHeight,
                decoration:
                    const BoxDecoration(gradient: AppColors.primaryGradient),
              ),
            ),
            Positioned(
              top: topPad + 4,
              left: 16,
              right: 6,
              height: headerRowHeight,
              child: _buildHeaderRow(context),
            ),
            // Only mounted when the admin has published a banner — with none,
            // the header is just the curved profile/bell row.
            if (hasBanner)
              Positioned(
                top: bannerTop,
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBannerCarousel(context),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow(BuildContext context) {
    final myProfile = ref.watch(myProfileProvider).valueOrNull;
    final user = ref.watch(currentUserProvider).valueOrNull;
    final fullName = (myProfile?.fullName.trim().isNotEmpty ?? false)
        ? myProfile!.fullName.trim()
        : (user?.displayName?.trim().isNotEmpty ?? false)
            ? user!.displayName!.trim()
            : context.l10n.guest;
    final firstName = fullName.split(' ').first;
    final photo = (myProfile?.profilePhotoUrl?.isNotEmpty ?? false)
        ? myProfile!.profilePhotoUrl!
        : (user?.photoUrl ?? '');
    final unread = ref.watch(unreadNotificationCountProvider) +
        ref.watch(unreadAnnouncementsCountProvider);
    final unreadChats = ref.watch(myUnreadChatCountProvider);
    // Admin dashboard shortcut — visible to admin accounts only (admin /
    // super_admin, plus the AdminConfig e-mail whitelist as a fallback so a
    // stale stored role can't hide it). Regular users never see it.
    final isAdmin = user?.isAdmin ?? false;

    return Row(
      children: [
        Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white, size: 26),
            tooltip: 'Menu',
            visualDensity: VisualDensity.compact,
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        const SizedBox(width: 2),
        CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white24,
          backgroundImage: cachedPhotoProvider(photo),
          child: photo.isEmpty
              ? Text(firstName.isNotEmpty ? firstName[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16))
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.welcomeBack,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.8), fontSize: 12.5)),
              Text(firstName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        // Admin shortcut only — the old Astrology Dashboard icon was removed
        // along with the whole email-based astrology access system.
        if (isAdmin)
          IconButton(
            tooltip: 'Admin Dashboard',
            visualDensity: VisualDensity.compact,
            onPressed: () => context.push('/admin'),
            icon: const Icon(Icons.admin_panel_settings,
                color: AppColors.gold, size: 25),
          ),
        // Chat icon with an unread badge — replaces the removed Chats tab so
        // users see new messages straight from the Home header.
        IconButton(
          tooltip: 'Chats',
          visualDensity: VisualDensity.compact,
          onPressed: () => context.push('/chats'),
          icon: unreadChats > 0
              ? Badge(
                  backgroundColor: Colors.red,
                  label: Text('$unreadChats',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.white)),
                  child: const Icon(Icons.chat_bubble_outline,
                      color: Colors.white, size: 24),
                )
              : const Icon(Icons.chat_bubble_outline,
                  color: Colors.white, size: 24),
        ),
        IconButton(
          tooltip: 'Notifications',
          visualDensity: VisualDensity.compact,
          onPressed: () => _openNotifications(context),
          icon: unread > 0
              ? Badge(
                  backgroundColor: AppColors.gold,
                  label: Text('$unread',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.primary)),
                  child: const Icon(Icons.notifications_none,
                      color: Colors.white, size: 26),
                )
              : const Icon(Icons.notifications_none,
                  color: Colors.white, size: 26),
        ),
      ],
    );
  }

  /// Opens the notifications inbox via its go_router route so that a
  /// notification tap that jumps to a Home tab (e.g. Reports) can cleanly
  /// replace the navigation stack with `go('/home')`.
  void _openNotifications(BuildContext context) =>
      context.push('/notifications');

  // ── Banner Carousel ────────────────────────────────────────────────────────

  Widget _buildBannerCarousel(BuildContext context) {
    final bannerWidth = MediaQuery.of(context).size.width - 24;
    final bannerHeight = bannerWidth * _bannerRatio;

    // ONLY admin-published banners are ever shown. When Banner Management is
    // empty (or every banner is hidden) the whole section disappears.
    final remote = _remoteBanners;
    final count = remote.length;
    _bannerCount = count; // keep the auto-scroll timer wrapping correctly
    if (count == 0) return const SizedBox.shrink();
    final page = _bannerPage < count ? _bannerPage : 0;

    return Column(
      children: [
        SizedBox(
          height: bannerHeight,
          child: PageView.builder(
            controller: _bannerCtrl,
            itemCount: count,
            onPageChanged: (i) => setState(() => _bannerPage = i),
            itemBuilder: (_, i) =>
                _bannerCard(HomeBannerSlide(banner: remote[i])),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(count, (i) {
            final active = i == page;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 20 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }

  /// Wraps an admin banner slide in the rounded, elevated carousel card so the
  /// uploaded artwork is framed consistently (nothing is drawn over it).
  Widget _bannerCard(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kCardRadius),
            // Soft, subtle gold hairline — a premium accent that frames the
            // banner without dominating it (spec §8). The artwork leads; a
            // gentle neutral elevation shadow does the lifting, not the border.
            border: Border.all(color: AppColors.gold.withOpacity(0.40), width: 1),
            boxShadow: _kCardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kCardRadius - 1),
            child: child,
          ),
        ),
      );

  // ── Quick actions ──────────────────────────────────────────────────────────

  /// A premium white card of five one-tap shortcuts (reference layout):
  /// Matches · Interests · Astrology · Reports · Muhurtham Day. Each has a soft
  /// coloured circular icon.
  Widget _buildQuickActions(BuildContext context) {
    void goTab(int i) => ref.read(homeTabIndexProvider.notifier).state = i;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_kCardRadius),
          boxShadow: _kCardShadow,
        ),
        // `start` (not the default `center`) is what keeps all four icons on
        // EXACTLY the same baseline: a two-line Tamil label used to make its
        // column taller, and centring then pushed that column's icon down
        // relative to the others.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _quickAction(
                icon: Icons.favorite,
                label: context.l10n.matches,
                color: const Color(0xFFE64A6B),
                onTap: () => goTab(kMatchesTabIndex),
              ),
            ),
            Expanded(
              child: _quickAction(
                icon: Icons.people_alt_rounded,
                label: context.l10n.interests,
                color: const Color(0xFF7C4DFF),
                onTap: () => goTab(kInterestsTabIndex),
              ),
            ),
            Expanded(
              child: _quickAction(
                icon: Icons.auto_awesome,
                label: context.l10n.astrology,
                color: const Color(0xFFF5A623),
                onTap: () => goTab(kAstrologyTabIndex),
              ),
            ),
            Expanded(
              child: _quickAction(
                icon: Icons.description_outlined,
                label: context.l10n.reports,
                color: const Color(0xFF2F80ED),
                onTap: () => goTab(kReportsTabIndex),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Premium circular icon: soft two-tone tint + a subtle drop shadow.
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withOpacity(0.20), color.withOpacity(0.08)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            // Fixed-height label area so all five columns are exactly the same
            // height and the icons above them stay perfectly in line, whether
            // the label needs one line (English) or two (Tamil).
            SizedBox(
              height: 26,
              child: Align(
                alignment: Alignment.topCenter,
                // Prefers a single line and only wraps between WHOLE words,
                // shrinking the font slightly when a long Tamil word would
                // otherwise be split mid-word.
                child: AutoFitLabel(
                  label,
                  maxLines: 2,
                  minFontSize: 7.5,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Profile Under Review banner ────────────────────────────────────────────

  /// Premium status banner shown while the member's profile is not live:
  /// amber/gold + hourglass while `pending` (admin review), red + info icon
  /// when `rejected` so the member gets clear feedback instead of silence.
  Widget _buildPendingReviewBanner(BuildContext context,
      {bool rejected = false}) {
    final tint = rejected ? AppColors.error : AppColors.warning;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              tint.withValues(alpha: 0.14),
              (rejected ? tint : AppColors.gold).withValues(alpha: 0.10),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tint.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                  rejected ? Icons.info_outline : Icons.hourglass_top,
                  color: tint,
                  size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      rejected
                          ? context.l10n.profileRejectedTitle
                          : context.l10n.profileUnderReviewTitle,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          fontFamily: 'Poppins')),
                  const SizedBox(height: 3),
                  Text(
                      rejected
                          ? context.l10n.profileRejectedBody
                          : context.l10n.profileUnderReviewBody,
                      style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 12,
                          height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Marriage Muhurtham Calendar card ────────────────────────────────────────

  /// Home entry for the Marriage Muhurtham Calendar — a "View Calendar"
  /// button that opens the month-wise auspicious-dates page.
  ///
  /// LAUNCH LOCK: for non-admin users the button is locked (🔒 + Coming Soon)
  /// and only shows the shared Coming Soon dialog. Admins keep full access.
  /// Side-by-side info cards (reference): Muhurtham | Profile Completion,
  /// equalised in height so both cards match.
  Widget _buildInfoCardsRow(BuildContext context, ProfileModel? profile) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _muhurthamMini(context)),
            const SizedBox(width: 12),
            Expanded(child: _profileCompletionMini(context, profile)),
          ],
        ),
      ),
    );
  }

  /// The next upcoming muhurtham from the curated dataset (today counts), or
  /// null when the dataset has run out of future dates.
  MuhurthamDate? get _nextMuhurtham {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final m in kMuhurthamDates) {
      if (!m.date.isBefore(today)) return m;
    }
    return null;
  }

  /// Marriage Muhurtham Calendar card (spec §12).
  ///
  /// Requirements this layout satisfies:
  ///  • the FULL title is always shown — it wraps onto as many lines as it
  ///    needs and is never truncated with an ellipsis (no `maxLines`, no
  ///    `TextOverflow.ellipsis`, no auto-shrinking);
  ///  • while the feature is locked, a LARGE CENTRED "Coming Soon" fills the
  ///    body instead of the old small badge;
  ///  • it reads as the twin of the Profile Completion card beside it — same
  ///    radius, shadow, icon bubble and title treatment, with the equal height
  ///    coming from the row's `IntrinsicHeight`;
  ///  • it stays responsive: everything is fluid width, so it holds up from
  ///    320 px phones to tablets.
  Widget _muhurthamMini(BuildContext context) {
    final unlocked = ref.watch(upcomingFeaturesUnlockedProvider);
    final next = _nextMuhurtham;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return InkWell(
      borderRadius: BorderRadius.circular(_kCardRadius),
      onTap: () => unlocked
          ? context.push('/muhurtham-calendar')
          : showComingSoonDialog(context,
              featureName: context.l10n.featureMuhurthamCalendar),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF8EC), Color(0xFFFDEFD2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: Border.all(color: AppColors.gold.withOpacity(0.45)),
          boxShadow: _kCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.20),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.calendar_month,
                      size: 18, color: AppColors.goldDark),
                ),
                const SizedBox(width: 8),
                Expanded(
                  // The COMPLETE title, wrapped over as many lines as it takes.
                  // Never clipped, never "…" — in either language.
                  child: Text(
                    context.l10n.muhurthamCalendarTitle,
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.25,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (unlocked && next != null) ...[
              // Next auspicious date — day + month kept front and centre.
              Center(
                child: Column(
                  children: [
                    Text('${next.date.day}',
                        style: const TextStyle(
                            fontSize: 30,
                            height: 1.0,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Poppins',
                            color: AppColors.goldDark)),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMMM yyyy', locale).format(next.date),
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        context.localizeValue(next.nakshatra),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.goldDark),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(context.l10n.muhurthamSubtitle,
                  softWrap: true,
                  style: const TextStyle(
                      color: Colors.black54, fontSize: 11, height: 1.3)),
              const Spacer(),
            ] else if (unlocked) ...[
              Text(context.l10n.muhurthamSubtitle,
                  softWrap: true,
                  style: const TextStyle(
                      color: Colors.black54, fontSize: 11, height: 1.3)),
              const Spacer(),
            ] else ...[
              // LOCKED — a large, centred "Coming Soon" owns the card body
              // (Expanded, so it centres in whatever height the twin cards
              // settle on) instead of a small corner badge.
              const Expanded(child: _ComingSoonPanel()),
            ],
          ],
        ),
      ),
    );
  }

  /// Trust / feature highlights (reference): verified profiles, safe
  /// conversations, genuine matches, 24/7 support. Laid out as a 2×2 grid so
  /// Tamil labels stay READABLE (11px, max 2 lines) instead of shrinking to
  /// 7px in a cramped four-across row.
  Widget _buildFeatureHighlights(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: Border.all(color: AppColors.divider),
          boxShadow: _kCardShadow,
        ),
        child: Column(
          children: [
            Row(
              children: [
                _highlight(Icons.verified_user, AppColors.gold,
                    l10n.trustVerifiedProfiles),
                const SizedBox(width: 10),
                _highlight(Icons.lock_outline_rounded, AppColors.primary,
                    l10n.trustSafeConversations),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _highlight(Icons.workspace_premium, const Color(0xFFE8590C),
                    l10n.trustGenuineMatches),
                const SizedBox(width: 10),
                _highlight(Icons.headset_mic, const Color(0xFF2F80ED),
                    l10n.trustSupport247),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One trust/feature highlight cell: tinted icon bubble beside a label that
  /// wraps between whole words (never mid-word) at a readable size.
  Widget _highlight(IconData icon, Color color, String label) => Expanded(
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AutoFitLabel(
                label,
                maxLines: 2,
                minFontSize: 9,
                textAlign: TextAlign.start,
                style: const TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  // ── Profile Completion card ─────────────────────────────────────────────────

  /// A premium profile-completion card: a circular progress ring with the live
  /// percentage in its centre, the localized title/subtitle, and a "Complete
  /// Now" CTA. Derived from [computeProfileCompletion] so it always agrees with
  /// the Complete-Profile screen, and hidden once the profile reaches 100%.
  /// Compact vertical Profile Completion card for the info row (reference):
  /// title, purple circular % ring, subtitle, "Complete Now" link.
  Widget _profileCompletionMini(BuildContext context, ProfileModel? profile) {
    final completion = computeProfileCompletion(profile);
    final pct = completion.percent.clamp(0, 100);
    final done = pct >= 100;
    final ringColor = done ? AppColors.success : AppColors.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(_kCardRadius),
      // With no matrimony profile yet there is nothing to "complete" — the card
      // opens the creation wizard instead of the section-by-section editor.
      onTap: () => context.push(
          profile == null ? '/profile/create' : '/complete-profile'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF7F0FB), Color(0xFFFDF4F6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: Border.all(color: AppColors.primary.withOpacity(0.10)),
          boxShadow: _kCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: ringColor.withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(done ? Icons.verified : Icons.person_outline,
                      size: 18, color: ringColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  // Tamil title wraps between whole words rather than
                  // truncating.
                  child: AutoFitLabel(context.l10n.profileCompletionTitle,
                      maxLines: 2,
                      minFontSize: 10,
                      textAlign: TextAlign.start,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.2,
                          fontFamily: 'Poppins')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: 62,
                height: 62,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 62,
                      height: 62,
                      child: CircularProgressIndicator(
                        value: pct / 100,
                        strokeWidth: 6,
                        strokeCap: StrokeCap.round,
                        backgroundColor: ringColor.withOpacity(0.12),
                        valueColor: AlwaysStoppedAnimation(ringColor),
                      ),
                    ),
                    Text('$pct%',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                            color: ringColor)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(context.l10n.completeProfile,
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.grey[600], fontSize: 11, height: 1.3)),
            const Spacer(),
            const SizedBox(height: 10),
            if (!done)
              Row(
                children: [
                  Flexible(
                    child: Text(context.l10n.completeNow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5)),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.arrow_forward,
                      size: 14, color: AppColors.primary),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ── Wedding Workspace card ──────────────────────────────────────────────────

  /// Shown once a Marriage Fixed proposal / wedding exists for this user:
  ///   • fixed → opens the shared Wedding Workspace (with countdown teaser);
  ///   • proposed & awaiting MY confirmation → confirm prompt;
  ///   • proposed & awaiting partner → status card.
  ///
  /// LAUNCH LOCK: Marriage Fixed and the Wedding Workspace are locked for
  /// non-admin users — the card stays visible but tapping it only shows the
  /// shared Coming Soon dialog.
  Widget _buildWeddingCard(BuildContext context) {
    final wedding = ref.watch(myCoupleWeddingProvider).valueOrNull;
    if (wedding == null) return const SizedBox.shrink();
    final unlocked = ref.watch(upcomingFeaturesUnlockedProvider);
    final myUid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid ?? '';
    final partnerName = wedding.nameOf(wedding.otherUid(myUid));

    final l10n = context.l10n;
    final String subtitle;
    if (wedding.isFixed) {
      final days = wedding.daysRemaining;
      subtitle = days == null
          ? l10n.weddingPlanTogether
          : days > 0
              ? l10n.weddingDaysToGo(days)
              : days == 0
                  ? l10n.weddingToday
                  : l10n.weddingCongrats;
    } else if (wedding.confirmedBy(myUid)) {
      subtitle = l10n.weddingWaitingConfirm(partnerName);
    } else {
      subtitle = l10n.weddingPartnerConfirmed(partnerName);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_kCardRadius),
          // Locked (non-admin) → Coming Soon dialog only. Unlocked:
          // fixed → open the workspace; still proposed → jump to the
          // Interests tab (Accepted), where the confirm button lives.
          onTap: () {
            if (!unlocked) {
              showComingSoonDialog(context,
                  featureName: wedding.isFixed
                      ? context.l10n.featureWeddingWorkspace
                      : context.l10n.featureMarriageFixed);
              return;
            }
            wedding.isFixed
                ? context.push('/wedding-workspace')
                : ref.read(homeTabIndexProvider.notifier).state =
                    kInterestsTabIndex;
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(_kCardRadius),
              boxShadow: _kCardShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text('💍', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(context.l10n.weddingWorkspaceTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    fontFamily: 'Poppins')),
                          ),
                          if (!unlocked) ...[
                            const SizedBox(width: 6),
                            const ComingSoonBadge(compact: true),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 11.5)),
                    ],
                  ),
                ),
                Icon(unlocked ? Icons.chevron_right : Icons.lock,
                    color: Colors.white70, size: unlocked ? 24 : 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Compact notification-style action cards ────────────────────────────────

  List<Widget> _buildActionCards(BuildContext context, ProfileModel? profile) {
    final cards = <Widget>[];

    // Profile Completion is rendered above in the side-by-side info row
    // (`_buildInfoCardsRow` → `_profileCompletionMini`).

    // (The old "Upgrade To Premium" card was removed — the app has NO
    // subscription system; every matrimony feature is free.)

    // 🎉 Married status — the "found your life partner" flow. Fully
    // user-manageable: confirming asks the source + a final confirmation, and
    // the married state can always be UNDONE (tap the card) to return the
    // profile to normal matchmaking.
    if (profile != null) {
      cards.add(profile.isMarried
          ? _notifCard(
              emoji: '🎉',
              title: context.l10n.married,
              subtitle: context.l10n.marriedLeftMatchmaking,
              accent: AppColors.success,
              onTap: () => _confirmUndoMarried(context, profile),
            )
          : _notifCard(
              emoji: '💍',
              title: context.l10n.foundLifePartnerQ,
              subtitle: context.l10n.markProfileMarried,
              accent: AppColors.success,
              onTap: () => _startMarriedFlow(context, profile),
            ));
    }

    return cards;
  }

  /// A compact, full-width notification-style card: small icon on the left,
  /// title + subtitle, and a chevron on the right. ~62px tall.
  Widget _notifCard({
    required String emoji,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color accent,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kCardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_kCardRadius),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_kCardRadius),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: _kCardShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: accent.withOpacity(0.12), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              fontFamily: 'Poppins')),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 11.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.grey[400], size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// STAGE 1 of the "Found Your Life Partner" flow: ask HOW the partner was
  /// found (through this app / another source) with a Skip escape, then hand
  /// the answer to the final confirmation. Nothing is saved until the user
  /// explicitly confirms in stage 2.
  Future<void> _startMarriedFlow(
      BuildContext context, ProfileModel profile) async {
    final via = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.foundLifePartnerSheetTitle,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins')),
              const SizedBox(height: 6),
              Text(context.l10n.foundLifePartnerSheetBody,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              const SizedBox(height: 16),
              _marriedSourceTile(
                ctx,
                emoji: '❤️',
                title: context.l10n.marriedViaAppTitle,
                subtitle: context.l10n.marriedViaAppSubtitle,
                value: 'app',
              ),
              const SizedBox(height: 10),
              _marriedSourceTile(
                ctx,
                emoji: '🌸',
                title: context.l10n.marriedViaOtherTitle,
                subtitle: context.l10n.marriedViaOtherSubtitle,
                value: 'other',
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(context.l10n.skipNotYet,
                      style: const TextStyle(color: Colors.grey)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (via == null || !context.mounted) return; // skipped

    // STAGE 2 — final confirmation before anything is saved.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.l10n.confirmMarkMarriedTitle),
        content: Text(context.l10n.confirmMarkMarriedBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n; // capture before the async gap
    await ref
        .read(accountControllerProvider.notifier)
        .markMarried(profile, via: via);
    ref.invalidate(newProfilesProvider);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text(l10n.marriedSuccessSnack),
      // One-tap UNDO right from the confirmation — accidental confirms are
      // reversed instantly (the card's "Tap to undo" stays available after).
      action: SnackBarAction(
        label: l10n.undoUpper,
        onPressed: () async {
          await ref
              .read(accountControllerProvider.notifier)
              .unmarkMarried(profile);
          ref.invalidate(newProfilesProvider);
        },
      ),
    ));
  }

  /// A tappable option row in the married-source sheet.
  Widget _marriedSourceTile(
    BuildContext sheetCtx, {
    required String emoji,
    required String title,
    required String subtitle,
    required String value,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(sheetCtx, value),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  /// UNDO — returns a married profile to normal matchmaking (accidental
  /// confirmation or changed plans). Confirmed with its own dialog.
  Future<void> _confirmUndoMarried(
      BuildContext context, ProfileModel profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.l10n.undoMarriedTitle),
        content: Text(context.l10n.undoMarriedBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.keepAsMarried)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.undo),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n; // capture before the async gap
    await ref.read(accountControllerProvider.notifier).unmarkMarried(profile);
    ref.invalidate(newProfilesProvider);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.backInMatchmaking)));
  }

  // ── New Profiles (newly joined members) ─────────────────────────────────────

  Widget _buildNewProfiles(
      BuildContext context, AsyncValue<List<ProfileModel>> async) {
    return async.when(
      // Skeleton cards in the exact rail layout — no spinner, no jump when
      // the real cards arrive.
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SkeletonProfileRail(height: 274, cardWidth: 164),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _emptyBox(context.l10n.noNewProfilesYet),
      ),
      data: (profiles) {
        if (profiles.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _emptyBox(context.l10n.noNewProfilesYet),
          );
        }
        return _horizontalMatchSection(
            context, '💫', context.l10n.latestProfiles, profiles);
      },
    );
  }

  Widget _horizontalMatchSection(BuildContext context, String emoji,
      String title, List<ProfileModel> profiles) {
    // PREVIEW ONLY (§7): Home never lists every profile — just the latest few
    // newly-registered members. "View All" switches to the Matches tab, which
    // is where the complete list lives (§8).
    final preview =
        profiles.take(kHomeNewProfilesPreviewCount).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, emoji, title,
            onViewAll: () => ref.read(homeTabIndexProvider.notifier).state = 1),
        const SizedBox(height: 12),
        SizedBox(
          height: 274,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: preview.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) =>
                SizedBox(width: 164, child: _MatchCard(profile: preview[i])),
          ),
        ),
      ],
    );
  }

  // ── Recent Interests ───────────────────────────────────────────────────────

  Widget _buildRecentInterests(BuildContext context) {
    final receivedAsync = ref.watch(receivedInterestsProvider);
    final received = [...(receivedAsync.valueOrNull ?? const [])]
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
    // Home shows only the latest 5 — the full list lives behind "View All".
    final recent = received.take(5).toList();
    // While the stream is still connecting show skeletons, not the empty
    // state — "no interests yet" must never flash during a normal load.
    final loading = receivedAsync.isLoading && recent.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, '💌', context.l10n.recentInterests,
            onViewAll: recent.isEmpty
                ? null
                : () => ref.read(homeTabIndexProvider.notifier).state =
                    kInterestsTabIndex),
        const SizedBox(height: 12),
        if (loading)
          const SkeletonProfileRail(height: 256, cardWidth: 172)
        else if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _recentInterestsEmpty(context),
          )
        else
          SizedBox(
            height: 256,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: recent.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) =>
                  _RecentInterestCard(interest: recent[i]),
            ),
          ),
      ],
    );
  }

  /// Friendly empty state for Recent Interests — an illustration, a short line
  /// and a primary CTA that jumps to the Matches tab.
  Widget _recentInterestsEmpty(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.favorite_border,
                size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          Text(context.l10n.recentInterestsEmptyTitle,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          const SizedBox(height: 4),
          Text(
            context.l10n.recentInterestsEmptySubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () => ref.read(homeTabIndexProvider.notifier).state =
                kMatchesTabIndex,
            icon: const Icon(Icons.search, size: 18),
            label: Text(context.l10n.exploreMatches),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared bits ────────────────────────────────────────────────────────────

  Widget _sectionHeader(BuildContext context, String emoji, String title,
      {VoidCallback? onViewAll}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: AutoFitLabel('$emoji  $title',
                maxLines: 2,
                minFontSize: 12,
                textAlign: TextAlign.start,
                style: const TextStyle(
                    fontSize: 16.5,
                    height: 1.2,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold)),
          ),
          if (onViewAll != null)
            GestureDetector(
              onTap: onViewAll,
              child: Row(
                children: [
                  Text(context.l10n.viewAll,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_forward_ios,
                      size: 12, color: AppColors.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyBox(String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kCardRadius),
        boxShadow: _kCardShadow,
      ),
      child: Column(
        children: [
          Icon(Icons.favorite_border, size: 40, color: Colors.grey[300]),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        ],
      ),
    );
  }
}

// ── Recommended Match Card ────────────────────────────────────────────────────

class _MatchCard extends ConsumerWidget {
  final ProfileModel profile;
  const _MatchCard({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => context.push('/profile/${profile.id}'),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo expands to fill the remaining height, FACE-CENTRED so the
            // head is never cropped (plain centre crop when no face is found).
            // No online status, no percentage, no overlay badge — the "star
            // matching" hint is shown as simple green text below the details.
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: FaceCenteredPhoto(
                  url: profile.hidesPhoto
                      ? ''
                      : (profile.profilePhotoUrl?.trim().isNotEmpty ?? false)
                          ? profile.profilePhotoUrl!
                          : (profile.photos.isNotEmpty
                              ? profile.photos.first
                              : ''),
                  fit: BoxFit.cover,
                  fallbackIconSize: 48,
                  fallbackBg: Colors.grey[200],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${profile.name}, ${profile.age}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              fontFamily: 'Poppins'),
                        ),
                      ),
                      // Verification tick — green when the admin has verified
                      // the profile, dark/inactive when not.
                      const SizedBox(width: 4),
                      VerificationTick.forProfile(profile, size: 15),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _metaLine(Icons.school_outlined,
                      profile.education.isEmpty ? 'N/A' : profile.education),
                  if (profile.occupation.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    _metaLine(Icons.work_outline, profile.occupation),
                  ],
                  const SizedBox(height: 3),
                  _metaLine(Icons.location_on_outlined,
                      profile.city.isEmpty ? 'N/A' : profile.city),
                  const SizedBox(height: 6),
                  // Simple green "star matching" text (spec) — NOT a badge/card.
                  Row(
                    children: [
                      const Text('⭐', style: TextStyle(fontSize: 11)),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          context.l10n.starMatching,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A compact icon + single-line meta row (education, occupation, location).
  Widget _metaLine(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 12, color: Colors.grey[500]),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey[600], fontSize: 10.5),
            ),
          ),
        ],
      );

}

// ── Recent Interest Card ──────────────────────────────────────────────────────

/// A structured card for a received interest. Resolves the sender's profile and
/// shows their photo, name·age, education, location, the date the interest was
/// received and a "View Profile" button. Cached image (never re-downloads).
class _RecentInterestCard extends ConsumerWidget {
  final InterestModel interest;
  const _RecentInterestCard({required this.interest});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final senderAsync = ref.watch(profileByIdProvider(interest.senderProfileId));
    final p = senderAsync.valueOrNull;
    final photo = (p?.profilePhotoUrl?.trim().isNotEmpty ?? false)
        ? p!.profilePhotoUrl!
        : ((p?.photos.isNotEmpty ?? false) ? p!.photos.first : '');
    final name = p == null
        ? context.l10n.newInterestLabel
        : '${p.name}${p.age > 0 ? ', ${p.age}' : ''}';
    final education = p?.education.trim() ?? '';
    final location = p == null
        ? ''
        : [p.city, p.state].where((s) => s.trim().isNotEmpty).join(', ');
    final open = p == null ? null : () => context.push('/profile/${p.id}');

    return Container(
      width: 172,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: open,
            child: SizedBox(
              height: 118,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Face-centred so the sender's head is never cut off.
                  FaceCenteredPhoto(url: photo, fallbackIconSize: 40),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: interest.isAccepted
                            ? AppColors.success
                            : AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        interest.isAccepted
                            ? context.l10n.matchedBadge
                            : context.l10n.interestedBadge,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontFamily: 'Poppins'),
                  ),
                  if (education.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    _metaRow(Icons.school_outlined, education),
                  ],
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    _metaRow(Icons.location_on_outlined, location),
                  ],
                  const Spacer(),
                  Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 11, color: Colors.grey[400]),
                      const SizedBox(width: 3),
                      Text(_ago(interest.sentAt),
                          style: TextStyle(
                              fontSize: 10.5, color: Colors.grey[500])),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 30,
                    child: OutlinedButton(
                      onPressed: open,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9)),
                      ),
                      child: Text(context.l10n.viewProfile,
                          style: const TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 12, color: Colors.grey[500]),
          const SizedBox(width: 3),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ),
        ],
      );

  /// Compact relative time for the "received" date (e.g. Today, 3d, 2w).
  String _ago(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inDays >= 7) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}

// ── Home Astrologer Card ──────────────────────────────────────────────────────

// ── Curved header clipper ─────────────────────────────────────────────────────

/// Clips the maroon header background with a smooth convex bottom edge so the
/// banner appears gently embedded into the header.
class _HeaderCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..lineTo(0, size.height - 36)
      ..quadraticBezierTo(
          size.width / 2, size.height + 14, size.width, size.height - 36)
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// ── "Coming Soon" panel (Muhurtham card, §12) ────────────────────────────────

/// A large, CENTRED "Coming Soon" that fills a locked feature card's body.
///
/// Replaces the small corner badge the Muhurtham card used to carry: the label
/// is the card's message while the feature is locked, so it gets the space and
/// weight to read as one. `FittedBox(scaleDown)` keeps it on a single line on
/// the narrowest phones without ever clipping it.
class _ComingSoonPanel extends StatelessWidget {
  const _ComingSoonPanel();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_clock,
                size: 22, color: AppColors.goldDark),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              context.l10n.comingSoon,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                height: 1.15,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                color: AppColors.goldDark,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
