import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../core/utils/profile_completion.dart';
import '../../../models/banner_model.dart';
import '../../../models/interest_model.dart';
import '../../../models/profile_model.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/announcement_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/banner_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/interest_provider.dart';
import '../../../providers/navigation_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/wedding_provider.dart';
import '../../../widgets/common/coming_soon.dart';
import '../../../widgets/common/profile_highlight_badge.dart';
import '../../../widgets/home/home_banner_slide.dart';

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

  /// How many slides the carousel currently shows — admin-published banners
  /// when any exist, otherwise the built-in asset banners. Kept as a field so
  /// the auto-scroll timer always wraps at the LIVE count.
  int _bannerCount = _banners.length;

  // Built-in FALLBACK hero banners — shown only while the admin has not
  // published any banner in Banner Management (`banners` collection). The full
  // artwork is baked into each image; headline/subtitle/cta are used by the
  // graceful fallback if an asset ever fails to load.
  static const _banners = [
    _BannerData(
      assetPath: 'assets/images/banner_1.png',
      headline: 'Perfect Match\nWritten in the Stars',
      subtitle: 'Astrology meets compatibility\nto create your perfect match.',
      cta: 'Explore Your Match →',
    ),
    _BannerData(
      assetPath: 'assets/images/banner_2.png',
      headline: 'Find Your\nLife Partner',
      subtitle: 'Where stars align,\nhearts connect.',
      cta: 'Explore Matches →',
    ),
  ];

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
    final newProfilesAsync = ref.watch(newProfilesProvider);
    final myProfile = ref.watch(myProfileProvider).valueOrNull;

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

          // ── Quick actions — one-tap access to the core journeys ───────────
          _buildQuickActions(context),
          const SizedBox(height: 18),

          // ── Wedding Workspace (only once a wedding exists) ────────────────
          _buildWeddingCard(context),

          // ── Marriage Muhurtham Calendar ───────────────────────────────────
          _buildMuhurthamCard(context),
          const SizedBox(height: 8),

          // ── Compact notification-style action cards ───────────────────────
          ..._buildActionCards(context, myProfile),
          const SizedBox(height: 8),

          // ── New Profiles (newly joined members) ───────────────────────────
          _buildNewProfiles(context, newProfilesAsync),
          const SizedBox(height: 22),

          // ── Recent Interests ──────────────────────────────────────────────
          _buildRecentInterests(context),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Curved header + overlapping banner ─────────────────────────────────────

  /// The admin-published banners (Banner Management). Empty = fall back to the
  /// built-in asset banners.
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
    final bannerHeight = bannerWidth * _bannerRatio;
    final bannerTop = topPad + headerRowHeight + 10;
    final headerBgHeight = bannerTop + bannerHeight * 0.45;
    final totalHeight = bannerTop + bannerHeight + 28; // + dots block

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
            : 'Guest';
    final firstName = fullName.split(' ').first;
    final photo = (myProfile?.profilePhotoUrl?.isNotEmpty ?? false)
        ? myProfile!.profilePhotoUrl!
        : (user?.photoUrl ?? '');
    final unread = ref.watch(unreadNotificationCountProvider) +
        ref.watch(unreadAnnouncementsCountProvider);
    final unreadChats = ref.watch(myUnreadChatCountProvider);
    // Admin + Astrology dashboard shortcuts are visible ONLY to the privileged
    // super-admin account (the one whitelisted Gmail). Regular users and the
    // internal astrology account never see them.
    final isSuperAdmin = user?.isSuperAdmin ?? false;

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
          backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
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
              Text('Welcome back,',
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
        if (isSuperAdmin)
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

    // Admin-published banners take over the carousel; the built-in asset
    // banners remain only as the fallback when none are published.
    final remote = _remoteBanners;
    final count = remote.isNotEmpty ? remote.length : _banners.length;
    _bannerCount = count; // keep the auto-scroll timer wrapping correctly
    final page = _bannerPage < count ? _bannerPage : 0;

    return Column(
      children: [
        SizedBox(
          height: bannerHeight,
          child: PageView.builder(
            controller: _bannerCtrl,
            itemCount: count,
            onPageChanged: (i) => setState(() => _bannerPage = i),
            itemBuilder: (_, i) => remote.isNotEmpty
                ? _bannerCard(HomeBannerSlide(banner: remote[i]))
                : _BannerSlide(data: _banners[i]),
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

  /// Wraps an admin banner slide in the same rounded, elevated card the asset
  /// banners use, so the carousel look stays consistent.
  Widget _bannerCard(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: child,
          ),
        ),
      );

  // ── Quick actions ──────────────────────────────────────────────────────────

  /// A clean row of four premium one-tap shortcuts to the core journeys. Keeps
  /// the most important destinations visible without crowding the dashboard.
  Widget _buildQuickActions(BuildContext context) {
    void goTab(int i) => ref.read(homeTabIndexProvider.notifier).state = i;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _quickAction(
              icon: Icons.favorite,
              label: 'Matches',
              color: AppColors.primary,
              onTap: () => goTab(kMatchesTabIndex),
            ),
          ),
          Expanded(
            child: _quickAction(
              icon: Icons.people_alt_rounded,
              label: 'Interests',
              color: const Color(0xFF2F80ED),
              onTap: () => goTab(kInterestsTabIndex),
            ),
          ),
          Expanded(
            child: _quickAction(
              icon: Icons.auto_awesome,
              label: 'Astrology',
              color: AppColors.goldDark,
              onTap: () => goTab(kAstrologyTabIndex),
            ),
          ),
          Expanded(
            child: _quickAction(
              icon: Icons.description_outlined,
              label: 'Reports',
              color: AppColors.gold,
              onTap: () => goTab(kReportsTabIndex),
            ),
          ),
        ],
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
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withOpacity(0.18)),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins'),
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
  Widget _buildMuhurthamCard(BuildContext context) {
    final unlocked = ref.watch(upcomingFeaturesUnlockedProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF8EC), Color(0xFFFDEFD2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.gold.withOpacity(0.45)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text('📅', style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Marriage Muhurtham Calendar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          fontFamily: 'Poppins')),
                  const SizedBox(height: 2),
                  if (unlocked)
                    const Text('Auspicious marriage & engagement dates',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: Colors.black54, fontSize: 11.5))
                  else
                    const ComingSoonBadge(compact: true),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.goldDark,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
              onPressed: () => unlocked
                  ? context.push('/muhurtham-calendar')
                  : showComingSoonDialog(context,
                      featureName: context.l10n.featureMuhurthamCalendar),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!unlocked) ...[
                    const Icon(Icons.lock, size: 13),
                    const SizedBox(width: 4),
                  ],
                  Text(context.l10n.viewCalendar),
                ],
              ),
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

    final String subtitle;
    if (wedding.isFixed) {
      final days = wedding.daysRemaining;
      subtitle = days == null
          ? 'Plan the wedding together with both families'
          : days > 0
              ? '$days days to go — keep the preparation moving!'
              : days == 0
                  ? 'The wedding is today! 🎊'
                  : 'Congratulations on your wedding! 🎉';
    } else if (wedding.confirmedBy(myUid)) {
      subtitle = 'Waiting for $partnerName to confirm Marriage Fixed';
    } else {
      subtitle = '$partnerName confirmed — tap to confirm Marriage Fixed';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
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
              borderRadius: BorderRadius.circular(14),
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
                          const Flexible(
                            child: Text('Wedding Workspace',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
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
    final completion = computeProfileCompletion(profile);
    final cards = <Widget>[];

    // 💖 Profile Completion — hidden once the profile reaches 100%.
    if (completion.percent < 100) {
      cards.add(_notifCard(
        emoji: '💖',
        title: 'Profile Completion',
        subtitle: '${completion.percent}% complete · Complete your profile',
        accent: AppColors.primary,
        onTap: () => context.push('/complete-profile'),
      ));
    }

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
              title: 'Married',
              subtitle: 'Profile left matchmaking · Tap to undo',
              accent: AppColors.success,
              onTap: () => _confirmUndoMarried(context, profile),
            )
          : _notifCard(
              emoji: '💍',
              title: 'Found Your Life Partner?',
              subtitle: 'Mark your profile as married',
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
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
              ],
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
              const Text('💍 Found your life partner?',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins')),
              const SizedBox(height: 6),
              Text('Congratulations! Tell us how you found them.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              const SizedBox(height: 16),
              _marriedSourceTile(
                ctx,
                emoji: '❤️',
                title: 'Yes — through this app',
                subtitle: 'We matched on Jothida Matrimony',
                value: 'app',
              ),
              const SizedBox(height: 10),
              _marriedSourceTile(
                ctx,
                emoji: '🌸',
                title: 'Yes — through another source',
                subtitle: 'Found outside the app',
                value: 'other',
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Skip — not yet',
                      style: TextStyle(color: Colors.grey)),
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
        title: const Text('Confirm — Mark as Married?'),
        content: const Text(
            'Your profile will be marked as Married and will leave the '
            'matchmaking pool (it will no longer appear in Matches).\n\n'
            'You can undo this anytime from the Home page if plans change.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(accountControllerProvider.notifier)
        .markMarried(profile, via: via);
    ref.invalidate(newProfilesProvider);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: const Text(
          '🎉 Congratulations! Your profile is now marked as Married.'),
      // One-tap UNDO right from the confirmation — accidental confirms are
      // reversed instantly (the card's "Tap to undo" stays available after).
      action: SnackBarAction(
        label: 'UNDO',
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
        title: const Text('Undo married status?'),
        content: const Text(
            'Your profile will return to normal and appear in matchmaking '
            'again, exactly as before.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep as Married')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Undo'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(accountControllerProvider.notifier).unmarkMarried(profile);
    ref.invalidate(newProfilesProvider);
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(
        content: Text('Your profile is back in matchmaking.')));
  }

  // ── New Profiles (newly joined members) ─────────────────────────────────────

  Widget _buildNewProfiles(
      BuildContext context, AsyncValue<List<ProfileModel>> async) {
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
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
            context, '🆕', context.l10n.newProfiles, profiles);
      },
    );
  }

  Widget _horizontalMatchSection(BuildContext context, String emoji,
      String title, List<ProfileModel> profiles) {
    final preview = profiles.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, emoji, title,
            onViewAll: () => ref.read(homeTabIndexProvider.notifier).state = 1),
        const SizedBox(height: 12),
        SizedBox(
          height: 234,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: preview.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) =>
                SizedBox(width: 162, child: _MatchCard(profile: preview[i])),
          ),
        ),
      ],
    );
  }

  // ── Recent Interests ───────────────────────────────────────────────────────

  Widget _buildRecentInterests(BuildContext context) {
    final received =
        [...(ref.watch(receivedInterestsProvider).valueOrNull ?? const [])]
          ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
    final recent = received.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, '💌', 'Recent Interests',
            onViewAll: recent.isEmpty
                ? null
                : () => ref.read(homeTabIndexProvider.notifier).state =
                    kInterestsTabIndex),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _emptyBox('No interests received yet.'),
          )
        else
          SizedBox(
            height: 196,
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

  // ── Shared bits ────────────────────────────────────────────────────────────

  Widget _sectionHeader(BuildContext context, String emoji, String title,
      {VoidCallback? onViewAll}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text('$emoji  $title',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16.5,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold)),
          ),
          if (onViewAll != null)
            GestureDetector(
              onTap: onViewAll,
              child: const Row(
                children: [
                  Text('View All',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  SizedBox(width: 2),
                  Icon(Icons.arrow_forward_ios,
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
        borderRadius: BorderRadius.circular(16),
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

// ── Banner Data Model ─────────────────────────────────────────────────────────

class _BannerData {
  final String assetPath;
  final String headline;
  final String subtitle;
  final String cta;
  const _BannerData({
    required this.assetPath,
    required this.headline,
    required this.subtitle,
    required this.cta,
  });
}

// ── Banner Slide Widget ───────────────────────────────────────────────────────

class _BannerSlide extends StatelessWidget {
  final _BannerData data;
  const _BannerSlide({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                data.assetPath,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackBanner(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackBanner() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF8B0000), Color(0xFF6B0000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border:
                    Border.all(color: AppColors.gold.withOpacity(0.3), width: 1),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 120, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  data.headline,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 22,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  data.subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    data.cta,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: Center(
              child: Icon(
                Icons.favorite,
                size: 80,
                color: AppColors.gold.withOpacity(0.4),
              ),
            ),
          ),
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
            // Photo expands to fill the remaining height. A simple ⭐ highlight
            // badge (top-left) marks suitable/relevant profiles — no rating.
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  profile.photos.isNotEmpty
                      ? Image.network(
                          profile.photos.first,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: ProfileHighlightBadge(profile: profile, compact: true),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${profile.name}, ${profile.age}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontFamily: 'Poppins'),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    profile.education.isEmpty ? 'N/A' : profile.education,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          profile.city.isEmpty ? 'N/A' : profile.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 10.5),
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

  Widget _placeholder() => Container(
        color: Colors.grey[200],
        child: const Icon(Icons.person, size: 48, color: Colors.grey),
      );
}

// ── Recent Interest Card ──────────────────────────────────────────────────────

/// A compact card for a received interest. Resolves the sender's profile and
/// shows their photo, name·age and a tap target to view the full profile.
class _RecentInterestCard extends ConsumerWidget {
  final InterestModel interest;
  const _RecentInterestCard({required this.interest});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final senderAsync = ref.watch(profileByIdProvider(interest.senderProfileId));
    final p = senderAsync.valueOrNull;
    final photo = (p?.photos.isNotEmpty ?? false) ? p!.photos.first : null;
    final name = p == null
        ? 'New interest'
        : '${p.name}${p.age > 0 ? ', ${p.age}' : ''}';

    return GestureDetector(
      onTap: p == null ? null : () => context.push('/profile/${p.id}'),
      child: Container(
        width: 140,
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
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  photo != null
                      ? Image.network(photo,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder())
                      : _placeholder(),
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
                        interest.isAccepted ? 'Matched' : 'Interested',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    fontFamily: 'Poppins'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: Colors.grey[200],
        child: const Icon(Icons.person, size: 40, color: Colors.grey),
      );
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
