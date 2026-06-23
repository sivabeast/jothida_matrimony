import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_model.dart';
import '../../../providers/astrologer_provider.dart';
import '../../../providers/navigation_provider.dart';
import '../../../providers/profile_provider.dart';

/// Astrologer Directory — the "Astrologer" tab.
///
/// A dedicated marketplace that shows ONLY astrologers: a search bar (by name
/// or location), a filter sheet (location / rating / experience / language) and
/// horizontally-scrolling sections. Tapping a card opens the full astrologer
/// profile directly — there is no pricing, booking or detail popup.
class AstrologyServicesTab extends ConsumerStatefulWidget {
  const AstrologyServicesTab({super.key});

  @override
  ConsumerState<AstrologyServicesTab> createState() =>
      _AstrologyServicesTabState();
}

class _AstrologyServicesTabState extends ConsumerState<AstrologyServicesTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  AstroFilters _filters = const AstroFilters();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesSearch(Astrologer a) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return a.name.toLowerCase().contains(q) ||
        a.location.toLowerCase().contains(q);
  }

  void _clearAll() {
    setState(() {
      _query = '';
      _searchCtrl.clear();
      _filters = const AstroFilters();
    });
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<AstroFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FilterSheet(initial: _filters),
    );
    if (result != null) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    final astrosAsync = ref.watch(astrologersProvider);
    final myCity = ref.watch(myProfileProvider).valueOrNull?.city ?? '';

    return Container(
      color: AppColors.scaffoldBg,
      child: Column(
        children: [
          _searchBar(),
          _consultBanner(),
          Expanded(
            child: astrosAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => _stateMessage(
                  Icons.error_outline, 'Could not load astrologers', '$e'),
              data: (all) {
                if (all.isEmpty) {
                  return _stateMessage(
                    Icons.person_search_outlined,
                    'No astrologers yet',
                    'Astrologers will appear here once they sign up.',
                  );
                }
                final searching =
                    _query.trim().isNotEmpty || _filters.isActive;
                final matched = all
                    .where((a) => _matchesSearch(a) && _filters.matches(a))
                    .toList();
                // Listing & search default: available astrologers first.
                return searching
                    ? _resultsList(availableFirst(matched))
                    : _sections(all, myCity);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Shows the match the user came here to consult about (set by a "Consult
  /// Astrologer" button). Tapping an astrologer then books for this pairing.
  Widget _consultBanner() {
    final consult = ref.watch(consultMatchProvider);
    if (consult == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Consultation for your match with ${consult.partnerName}. '
              'Pick an astrologer below to book.',
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Clear',
            onPressed: () =>
                ref.read(consultMatchProvider.notifier).state = null,
          ),
        ],
      ),
    );
  }

  Widget _stateMessage(IconData icon, String title, String subtitle) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: AppColors.primary.withOpacity(0.4)),
              const SizedBox(height: 16),
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      );

  // ── Search + filter bar ────────────────────────────────────────────────────

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search astrologer...',
                prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          _query = '';
                          _searchCtrl.clear();
                        }),
                      ),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _openFilters,
            child: Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.tune, color: Colors.white),
                  if (_filters.isActive)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppColors.primary, width: 1.5),
                        ),
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

  // ── Horizontal sections (default view) ──────────────────────────────────────

  Widget _sections(List<Astrologer> all, String myCity) {
    // ── Section 1: Nearby — user's city + adjacent cities (available first) ──
    final nearby = availableFirst(_nearbyAstrologers(all, myCity));
    // ── Section 2: Top Rated — rating DESC, then review count DESC ──
    final topRated = [...all]
      ..sort((a, b) {
        final byRating = b.rating.compareTo(a.rating);
        return byRating != 0 ? byRating : b.reviewCount.compareTo(a.reviewCount);
      });

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // ── Section 1: Nearby ──────────────────────────────────────────────
        _sectionHeader(myCity.isEmpty
            ? '📍 Nearby Astrologers'
            : '📍 Nearby Astrologers · $myCity'),
        if (nearby.isEmpty)
          _inlineHint(myCity.isEmpty
              ? 'Set your location in your profile to see astrologers near you.'
              : 'No astrologers near $myCity yet.')
        else
          _horizontalRow(nearby),
        // ── Section 2: Top Rated ───────────────────────────────────────────
        _sectionHeader('⭐ Top Rated Astrologers'),
        _horizontalRow(topRated),
        // ── Section 3: All Astrologers (grid, available first) ─────────────
        _sectionHeader('🔮 All Astrologers'),
        _allGrid(availableFirst(all)),
      ],
    );
  }

  /// Astrologers in the user's city plus a small set of adjacent cities.
  List<Astrologer> _nearbyAstrologers(List<Astrologer> all, String myCity) {
    if (myCity.trim().isEmpty) return const [];
    final key = myCity.trim().toLowerCase();
    final near = <String>{key, ..._nearbyCities[key] ?? const []};
    return all
        .where((a) => near.contains(a.location.trim().toLowerCase()))
        .toList();
  }

  /// Lightweight adjacency map for common Tamil Nadu cities. Unknown cities
  /// simply fall back to an exact city match (handled above).
  static const Map<String, List<String>> _nearbyCities = {
    'chennai': ['kanchipuram', 'chengalpattu', 'tiruvallur', 'vellore'],
    'madurai': ['dindigul', 'virudhunagar', 'sivaganga', 'theni'],
    'coimbatore': ['tirupur', 'erode', 'pollachi'],
    'trichy': ['tiruchirappalli', 'thanjavur', 'karur', 'pudukkottai'],
    'tiruchirappalli': ['trichy', 'thanjavur', 'karur', 'pudukkottai'],
    'salem': ['namakkal', 'erode', 'dharmapuri'],
  };

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Text(
          title,
          style: const TextStyle(
              fontSize: 16,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.bold,
              color: AppColors.primary),
        ),
      );

  Widget _inlineHint(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.location_off_outlined,
                  size: 18, color: Colors.grey[400]),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12.5)),
              ),
            ],
          ),
        ),
      );

  Widget _horizontalRow(List<Astrologer> list) {
    return SizedBox(
      height: 232,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: list.length,
        itemBuilder: (_, i) => _AstrologerCard(
          astrologer: list[i],
          onTap: () => _openProfile(list[i]),
        ),
      ),
    );
  }

  /// Section 3 — every astrologer in a 2-column vertical grid.
  Widget _allGrid(List<Astrologer> list) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 232,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => _AstrologerGridCard(
        astrologer: list[i],
        onTap: () => _openProfile(list[i]),
      ),
    );
  }

  // ── Search / filter results (vertical list) ─────────────────────────────────

  Widget _resultsList(List<Astrologer> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${list.length} astrologer${list.length == 1 ? '' : 's'} found',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
              ),
              TextButton.icon(
                onPressed: _clearAll,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Clear'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? _emptyState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _AstrologerRow(
                    astrologer: list[i],
                    onTap: () => _openProfile(list[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off,
                  size: 64, color: AppColors.primary.withOpacity(0.4)),
              const SizedBox(height: 16),
              const Text('No astrologers found',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Try adjusting your search or filters.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _clearAll,
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary)),
                child: const Text('Clear search & filters'),
              ),
            ],
          ),
        ),
      );

  /// Card tap → open the full astrologer profile directly (no popup / sheet).
  void _openProfile(Astrologer a) => context.push('/astrologer/${a.id}');
}

// ─────────────────────────────────────────────────────────────────────────────
// Filters
// ─────────────────────────────────────────────────────────────────────────────

class AstroFilters {
  final String? location;
  final double? minRating;
  final int? minExperience;
  final String? language;

  const AstroFilters({
    this.location,
    this.minRating,
    this.minExperience,
    this.language,
  });

  bool get isActive =>
      location != null ||
      minRating != null ||
      minExperience != null ||
      language != null;

  bool matches(Astrologer a) {
    if (location != null && a.location != location) return false;
    if (minRating != null && a.rating < minRating!) return false;
    if (minExperience != null && a.experienceYears < minExperience!) {
      return false;
    }
    if (language != null && !a.languages.contains(language)) return false;
    return true;
  }
}

class _FilterSheet extends StatefulWidget {
  final AstroFilters initial;
  const _FilterSheet({required this.initial});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _loc = widget.initial.location;
  late double? _rating = widget.initial.minRating;
  late int? _exp = widget.initial.minExperience;
  late String? _lang = widget.initial.language;

  static const _locations = ['Chennai', 'Coimbatore', 'Madurai', 'Trichy', 'Salem'];
  static const _languages = ['Tamil', 'English', 'Telugu', 'Malayalam'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Filter Astrologers',
                style: TextStyle(
                    fontSize: 18,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _group<String>('📍 Location', [for (final l in _locations) (l, l)],
                _loc, (v) => setState(() => _loc = v)),
            _group<double>(
                '⭐ Rating',
                const [('4+ Stars', 4.0), ('4.5+ Stars', 4.5)],
                _rating,
                (v) => setState(() => _rating = v)),
            _group<int>('🕒 Experience', const [
              ('1+ Years', 1),
              ('5+ Years', 5),
              ('10+ Years', 10),
              ('15+ Years', 15),
            ], _exp, (v) => setState(() => _exp = v)),
            _group<String>('🌐 Language', [for (final l in _languages) (l, l)],
                _lang, (v) => setState(() => _lang = v)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _loc = null;
                      _rating = null;
                      _exp = null;
                      _lang = null;
                    }),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      side: BorderSide(color: Colors.grey[400]!),
                    ),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      AstroFilters(
                        location: _loc,
                        minRating: _rating,
                        minExperience: _exp,
                        language: _lang,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Apply Filters'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _group<T>(String title, List<(String, T)> opts, T? selected,
      ValueChanged<T?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: opts.map((o) {
            final sel = selected == o.$2;
            return ChoiceChip(
              label: Text(o.$1),
              selected: sel,
              showCheckmark: false,
              selectedColor: AppColors.primary.withOpacity(0.12),
              backgroundColor: Colors.grey[100],
              side:
                  BorderSide(color: sel ? AppColors.primary : Colors.grey[300]!),
              labelStyle: TextStyle(
                color: sel ? AppColors.primary : Colors.black87,
                fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
              onSelected: (_) => onChanged(sel ? null : o.$2),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared image helper
// ─────────────────────────────────────────────────────────────────────────────

Widget _astroImage(String url,
    {required double width, required double height, double radius = 12}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: Image.network(
      url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: width,
        height: height,
        color: AppColors.primary.withOpacity(0.08),
        child: const Icon(Icons.person, color: AppColors.primary, size: 40),
      ),
      loadingBuilder: (ctx, child, progress) => progress == null
          ? child
          : Container(
              width: width,
              height: height,
              color: AppColors.primary.withOpacity(0.05),
              child: const Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ),
    ),
  );
}

/// Full-bleed card top image. The photo fills the ENTIRE top section width
/// edge-to-edge (`BoxFit.cover`) and is top-aligned so faces (usually in the
/// upper half) are never cut off. Used by the listing cards (Top Rated + All
/// Astrologers).
Widget _cardTopImage(String url, double height) {
  Widget fallback(IconData icon) => Container(
        height: height,
        width: double.infinity,
        color: AppColors.primary.withOpacity(0.06),
        alignment: Alignment.center,
        child: Icon(icon, color: AppColors.primary, size: 46),
      );

  return ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
    child: Container(
      height: height,
      width: double.infinity,
      color: AppColors.primary.withOpacity(0.06),
      child: Image.network(
        url,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        errorBuilder: (_, __, ___) => fallback(Icons.person),
        loadingBuilder: (ctx, child, progress) => progress == null
            ? child
            : Container(
                height: height,
                width: double.infinity,
                alignment: Alignment.center,
                child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Status badge — green "Verified" pill shown ONLY for admin-approved
// astrologers. Pending / unverified astrologers get NO badge at all.
// ─────────────────────────────────────────────────────────────────────────────

/// Small social-media style verified tick for the image corner. A green
/// [Icons.verified] on a white ring — NOT a "Verified" pill/badge. Renders
/// nothing when the astrologer is not verified.
Widget _verifiedTick(bool verified, {double size = 18}) {
  if (!verified) return const SizedBox.shrink();
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 3),
      ],
    ),
    child: Icon(Icons.verified, color: AppColors.success, size: size),
  );
}

/// 🟢 Available / 🔴 Unavailable status line shown directly under the name.
Widget _availabilityLine(bool available, {double fontSize = 11.5}) {
  final color = available ? AppColors.success : AppColors.error;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, size: fontSize - 2.5, color: color),
      const SizedBox(width: 5),
      Text(available ? 'Available' : 'Unavailable',
          style: TextStyle(
              fontSize: fontSize, fontWeight: FontWeight.w600, color: color)),
    ],
  );
}

/// One tight metadata line (icon + ellipsised text) used on the directory
/// cards: location, experience, specialization.
Widget _metaLine(IconData icon, String text, {Color? color, double top = 3}) {
  final c = color ?? Colors.grey[700];
  return Padding(
    padding: EdgeInsets.only(top: top),
    child: Row(
      children: [
        Icon(icon, size: 12.5, color: color ?? Colors.grey[500]),
        const SizedBox(width: 4),
        Expanded(
          child: Text(text.isEmpty ? '—' : text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: c)),
        ),
      ],
    ),
  );
}

/// Shared, compact content column for a directory card: name, availability,
/// rating, location, experience, specialization — tight professional spacing,
/// sized to content (no blank space).
Widget _cardContent(Astrologer a) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(a.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
                fontFamily: 'Poppins')),
        const SizedBox(height: 3),
        _availabilityLine(a.isAvailable),
        const SizedBox(height: 3),
        Row(
          children: [
            const Icon(Icons.star, color: AppColors.gold, size: 13),
            const SizedBox(width: 3),
            Text(a.rating.toStringAsFixed(1),
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 11.5)),
            const SizedBox(width: 3),
            Text('(${a.reviewCount})',
                style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          ],
        ),
        _metaLine(Icons.location_on_outlined, a.location),
        _metaLine(
            Icons.work_history_outlined,
            a.experienceYears > 0
                ? '${a.experienceYears} yrs experience'
                : 'Experience N/A'),
        _metaLine(Icons.auto_awesome,
            a.specializations.isEmpty ? 'Astrologer' : a.specializations.first,
            color: AppColors.primary),
      ],
    );

// ─────────────────────────────────────────────────────────────────────────────
// Astrologer card (horizontal sections)
// ─────────────────────────────────────────────────────────────────────────────

class _AstrologerCard extends StatelessWidget {
  final Astrologer astrologer;
  final VoidCallback onTap;
  const _AstrologerCard({required this.astrologer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = astrologer;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 168,
        margin: const EdgeInsets.only(right: 12, top: 2, bottom: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                // Compact image; small verified tick only — no badges.
                _cardTopImage(a.photoUrl, 104),
                Positioned(top: 8, right: 8, child: _verifiedTick(a.verified)),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: _cardContent(a),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Astrologer grid card (All Astrologers — 2 per row)
// ─────────────────────────────────────────────────────────────────────────────

class _AstrologerGridCard extends StatelessWidget {
  final Astrologer astrologer;
  final VoidCallback onTap;
  const _AstrologerGridCard({required this.astrologer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = astrologer;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                // Compact image; small verified tick only — no badges.
                _cardTopImage(a.photoUrl, 104),
                Positioned(top: 8, right: 8, child: _verifiedTick(a.verified)),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: _cardContent(a),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Astrologer row (search / filter results)
// ─────────────────────────────────────────────────────────────────────────────

class _AstrologerRow extends StatelessWidget {
  final Astrologer astrologer;
  final VoidCallback onTap;
  const _AstrologerRow({required this.astrologer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = astrologer;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _astroImage(a.photoUrl, width: 78, height: 78, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                fontFamily: 'Poppins')),
                      ),
                      if (a.verified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified,
                            color: AppColors.success, size: 15),
                      ],
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.star,
                                color: AppColors.gold, size: 12),
                            const SizedBox(width: 2),
                            Text(a.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text('${a.location}  •  (${a.reviewCount} ratings)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  const SizedBox(height: 6),
                  _availabilityLine(a.isAvailable, fontSize: 12),
                  const SizedBox(height: 4),
                  Text(
                    a.specializations.isEmpty
                        ? 'Astrologer'
                        : a.specializations.first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.primary),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.work_history_outlined,
                          size: 13, color: Colors.grey[600]),
                      const SizedBox(width: 3),
                      Text('${a.experienceYears} yrs experience',
                          style:
                              TextStyle(color: Colors.grey[700], fontSize: 12)),
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
}
