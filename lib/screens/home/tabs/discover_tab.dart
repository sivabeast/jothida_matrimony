import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/master_location_model.dart';
import '../../../models/profile_model.dart';
import '../../../providers/interest_provider.dart';
import '../../../providers/master_location_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/horoscope_match_badge.dart';
import '../../../widgets/common/searchable_field.dart';

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
    setState(() {
      _filters = result;
      _currentIndex = 0;
    });
    await ref.read(discoverProvider.notifier).applyFilters(result);
    if (mounted && _pageController.hasClients) _pageController.jumpToPage(0);
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
                    onAccept: (interestId) =>
                        _acceptInterest(profiles[i], interestId),
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
  final ValueChanged<String> onAccept;

  const _MatchProfilePage({
    required this.profile,
    required this.interestSent,
    required this.onInterest,
    required this.onAccept,
  });

  /// Open the full Profile Details screen for this match.
  void _openProfile(BuildContext context) =>
      context.push('/profile/${profile.id}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = [profile.city, profile.state]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');

    // Live relationship status (Firestore), with an instant local override so
    // the button flips to "Interest Sent" the moment it's tapped.
    var status = ref.watch(interestStatusForProfileProvider(profile.id));
    if (status == InterestUiStatus.none && interestSent) {
      status = InterestUiStatus.sent;
    }

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
            // Tapping anywhere on the photo/details area opens the full
            // profile. The action bar below handles its own taps.
            Expanded(
              flex: 9,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openProfile(context),
                child: Column(
                  children: [
                    // ── Photo gallery + identity overlay + match badge ─────
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
                          // 10-porutham compatibility CATEGORY badge (no
                          // percentage). Informational only.
                          Positioned(
                            top: 14,
                            right: 14,
                            child: IgnorePointer(
                              child: HoroscopeMatchBadge(target: profile),
                            ),
                          ),
                          // "Tap to view" affordance.
                          Positioned(
                            top: 14,
                            left: 14,
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.visibility_outlined,
                                        size: 14, color: Colors.white),
                                    SizedBox(width: 5),
                                    Text('Tap to view profile',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Scrollable details ─────────────────────────────────
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                  ],
                ),
              ),
            ),
            // ── Action bar ───────────────────────────────────────────────
            _actionBar(context, ref, status),
          ],
        ),
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

  Widget _actionBar(BuildContext context, WidgetRef ref, InterestUiStatus status) =>
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Expanded(child: _interestButton(context, ref, status)),
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

  /// Status-aware left action. The relationship status is the source of truth,
  /// so once an interest exists (sent / accepted / rejected) the plain "Send
  /// Interest" button is never shown again.
  Widget _interestButton(
      BuildContext context, WidgetRef ref, InterestUiStatus status) {
    switch (status) {
      case InterestUiStatus.accepted:
        return _statusButton(
          icon: Icons.check_circle,
          label: 'Matched',
          background: AppColors.success,
        );
      case InterestUiStatus.sent:
        return _statusButton(
          icon: Icons.hourglass_top,
          label: 'Interest Sent',
          background: Colors.grey.shade500,
        );
      case InterestUiStatus.rejected:
        return _statusButton(
          icon: Icons.cancel,
          label: 'Rejected',
          background: Colors.grey.shade600,
        );
      case InterestUiStatus.receivedPending:
        // They're interested in us — accept it in place to become a match.
        final pending =
            ref.watch(pendingReceivedInterestFromProfileProvider(profile.id));
        return ElevatedButton.icon(
          onPressed:
              pending == null ? null : () => onAccept(pending.id),
          icon: const Icon(Icons.favorite, size: 20),
          label: const Text('Accept Interest'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      case InterestUiStatus.none:
        return ElevatedButton.icon(
          onPressed: onInterest,
          icon: const Icon(Icons.favorite, size: 20),
          label: const Text('Interest'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
    }
  }

  /// A disabled, status-coloured button (Matched / Interest Sent / Rejected).
  Widget _statusButton({
    required IconData icon,
    required String label,
    required Color background,
  }) =>
      ElevatedButton.icon(
        onPressed: null,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          disabledBackgroundColor: background,
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  void _reset() {
    setState(() {
      _minAge = _maxAge = null;
      _state = _district = _city = null;
      _religion = _caste = _education = _occupation = null;
      _maritalStatus = _rasi = _nakshatra = _matchQuality = null;
    });
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
                  _dropdown('Match Quality', _matchQualities, _matchQuality,
                      (v) => setState(() => _matchQuality = v)),
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
