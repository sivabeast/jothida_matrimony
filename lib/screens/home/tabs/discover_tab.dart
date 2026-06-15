import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/compatibility.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/profile_model.dart';
import '../../../providers/interest_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/horoscope_match_badge.dart';

/// The Matches experience — a premium "matrimony profile book".
///
/// One full-screen profile at a time. Users turn pages with a horizontal swipe
/// (book-like), browse a profile's photos with the inner gallery, and act on a
/// match with Interested / Message / Horoscope Match / View Full Profile.
///
/// Opposite-gender matching is resolved automatically from the signed-in user's
/// gender (Male → Female, Female → Male) — there is no manual toggle.
class DiscoverTab extends ConsumerStatefulWidget {
  const DiscoverTab({super.key});

  @override
  ConsumerState<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<DiscoverTab> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  // Profiles the user has expressed interest in during this session (so the
  // heart can flip to "Interested ✓" immediately).
  final Set<String> _interestSent = {};

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

  /// Load (or reload) the matches feed. The ONLY filter is gender (opposite
  /// gender) — no age / caste / religion / district / horoscope filtering.
  Future<void> _load() async {
    await ref.read(discoverProvider.notifier).load();
    if (!mounted) return;
    setState(() => _currentIndex = 0);
    if (_pageController.hasClients) _pageController.jumpToPage(0);
  }

  // ── Actions ─────────────────────────────────────────────────────────────
  Future<void> _sendInterest(ProfileModel profile) async {
    final me = ref.read(myProfileProvider).valueOrNull;
    if (me == null) {
      _snack('Create your profile first to send interest');
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

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(discoverProvider);
    final profiles = state.profiles;
    final total = profiles.length;

    return Column(
      children: [
        _topBar(total),
        Expanded(
          child: Builder(builder: (_) {
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (profiles.isEmpty) return _emptyState(state.error != null);

            return Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  itemCount: total,
                  onPageChanged: (i) {
                    setState(() => _currentIndex = i);
                    // Prefetch the next page as the user nears the end.
                    if (i >= total - 3) {
                      ref.read(discoverProvider.notifier).loadMore();
                    }
                  },
                  itemBuilder: (_, i) => _MatchProfilePage(
                    profile: profiles[i],
                    interestSent: _interestSent.contains(profiles[i].id),
                    onInterest: () => _sendInterest(profiles[i]),
                  ),
                ),
                // Subtle left/right swipe affordances.
                if (_currentIndex > 0)
                  _edgeHint(Alignment.centerLeft, Icons.chevron_left),
                if (_currentIndex < total - 1)
                  _edgeHint(Alignment.centerRight, Icons.chevron_right),
              ],
            );
          }),
        ),
      ],
    );
  }

  // ── Top bar: title · "X of N" · filter ──────────────────────────────────
  Widget _topBar(int total) {
    final position = total == 0 ? 0 : (_currentIndex + 1).clamp(1, total);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
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
              child: Text('$position of $total',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
          const Spacer(),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _edgeHint(Alignment alignment, IconData icon) => Align(
        alignment: alignment,
        child: IgnorePointer(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white.withOpacity(0.9), size: 26),
          ),
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

/// A single full-screen match — the "page" in the profile book.
class _MatchProfilePage extends ConsumerWidget {
  final ProfileModel profile;
  final bool interestSent;
  final VoidCallback onInterest;

  const _MatchProfilePage({
    required this.profile,
    required this.interestSent,
    required this.onInterest,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myProfileProvider).valueOrNull;
    final matchPercent = computeCompatibility(me, profile).matchPercent;
    final location = [profile.city, profile.state]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 14),
          ],
        ),
        child: Column(
          children: [
            // ── Photo gallery + identity overlay + match badge ───────────
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _PhotoGallery(photos: profile.photos),
                  // Scrim so the name is always legible.
                  IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.center,
                          colors: [
                            Colors.black.withOpacity(0.65),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Identity overlay.
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: IgnorePointer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${profile.name} | ${profile.age}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.bold)),
                          if (location.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on,
                                    size: 15, color: Colors.white70),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(location,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13.5)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Partner match percentage badge.
                  Positioned(
                    top: 14,
                    right: 14,
                    child: IgnorePointer(child: _matchBadge(matchPercent)),
                  ),
                  // Informational nakshatra "Horoscope Match" badge (never
                  // hides the profile — only shown when compatible).
                  Positioned(
                    top: 16,
                    left: 14,
                    child: IgnorePointer(
                      child: HoroscopeMatchBadge(
                          targetNakshatra: profile.horoscope.nakshatra),
                    ),
                  ),
                ],
              ),
            ),
            // ── Scrollable details (vertical scroll; horizontal swipe pages)
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Education + highlighted Occupation & Salary (key
                    // matching factors).
                    _careerEducation(),
                    const SizedBox(height: 12),
                    _quickFacts(),
                    if (profile.about.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _sectionLabel('About Me'),
                      const SizedBox(height: 4),
                      Text(profile.about,
                          style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: Colors.grey[800])),
                    ],
                  ],
                ),
              ),
            ),
            // ── Action bar ───────────────────────────────────────────────
            _actionBar(context),
          ],
        ),
      ),
    );
  }

  Widget _matchBadge(int percent) {
    final color = percent >= 80
        ? AppColors.success
        : percent >= 65
            ? AppColors.gold
            : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$percent%',
              style: TextStyle(
                  color: color, fontSize: 17, fontWeight: FontWeight.bold)),
          Text('Match',
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// Education shown clearly, with Occupation + Annual Salary highlighted side
  /// by side — these are the most important matching factors.
  Widget _careerEducation() {
    final hasOcc = profile.occupation.trim().isNotEmpty;
    final hasSalary = profile.annualIncome.trim().isNotEmpty;
    final hasEdu = profile.education.trim().isNotEmpty;
    if (!hasOcc && !hasSalary && !hasEdu) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasEdu) ...[
          Row(
            children: [
              const Icon(Icons.school_outlined,
                  size: 17, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(profile.education,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (hasOcc || hasSalary) const SizedBox(height: 10),
        ],
        if (hasOcc || hasSalary)
          Row(
            children: [
              if (hasOcc)
                Expanded(
                  child: _highlightTile(Icons.work_outline, 'Occupation',
                      profile.occupation, AppColors.primary),
                ),
              if (hasOcc && hasSalary) const SizedBox(width: 10),
              if (hasSalary)
                Expanded(
                  child: _highlightTile(Icons.payments_outlined,
                      'Annual Salary', profile.annualIncome, AppColors.success),
                ),
            ],
          ),
      ],
    );
  }

  Widget _highlightTile(IconData icon, String label, String value, Color color) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 5),
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _quickFacts() {
    final facts = <_Fact>[
      if (profile.height.trim().isNotEmpty)
        _Fact(Icons.height, profile.height),
      if (profile.religion.trim().isNotEmpty)
        _Fact(Icons.spa_outlined, profile.religion),
      if ((profile.caste ?? '').trim().isNotEmpty)
        _Fact(Icons.groups_outlined, profile.caste!),
    ];
    if (facts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in facts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(f.icon, size: 15, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(f.value,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary));

  Widget _actionBar(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: interestSent ? null : onInterest,
                icon: Icon(
                    interestSent ? Icons.check_circle : Icons.favorite_border,
                    size: 20),
                label: Text(interestSent ? 'Interest Sent' : 'Interest'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
                  disabledForegroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.push('/match/${profile.id}'),
                icon: const Icon(Icons.auto_awesome, size: 20),
                label: const Text('Horoscope'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      );
}

class _Fact {
  final IconData icon;
  final String value;
  const _Fact(this.icon, this.value);
}

/// Swipeable photo gallery with a page-dots indicator. Horizontal swipes here
/// change the photo; swipes on the details area below change the match.
class _PhotoGallery extends StatefulWidget {
  final List<String> photos;
  const _PhotoGallery({required this.photos});

  @override
  State<_PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<_PhotoGallery> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    if (photos.isEmpty) return _placeholder();

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: photos.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => Image.network(
            photos[i],
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(),
            loadingBuilder: (ctx, child, progress) => progress == null
                ? child
                : Container(
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator())),
          ),
        ),
        if (photos.length > 1)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                photos.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _index
                        ? Colors.white
                        : Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _placeholder() => Container(
        color: Colors.grey[200],
        child: const Center(
            child: Icon(Icons.person, size: 96, color: Colors.grey)),
      );
}
