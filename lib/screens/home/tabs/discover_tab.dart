import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/profile_model.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/requests_provider.dart';
import '../../../widgets/home/profile_completion_card.dart';

/// Discover feed: recommended matches filtered automatically by the user's
/// own gender (Male → Female profiles, Female → Male profiles). The gender
/// filter is applied at the database-query level — there is no manual
/// Brides/Grooms toggle.
class DiscoverTab extends ConsumerStatefulWidget {
  const DiscoverTab({super.key});

  @override
  ConsumerState<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<DiscoverTab> {
  // Active filters
  RangeValues _ageRange = const RangeValues(21, 40);
  String _city = '';
  String _education = '';
  String _occupation = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(_applyFilters);
  }

  void _applyFilters() {
    // Opposite-gender matching, resolved from the signed-in user's gender.
    final matchGender = ref.read(matchGenderProvider);
    ref.read(discoverProvider.notifier).load(gender: matchGender, filters: {
      'minAge': _ageRange.start.round(),
      'maxAge': _ageRange.end.round(),
      'city': _city,
      'education': _education,
      'occupation': _occupation,
    });
  }

  bool get _hasActiveFilters =>
      _city.isNotEmpty ||
      _education.isNotEmpty ||
      _occupation.isNotEmpty ||
      _ageRange.start != 21 ||
      _ageRange.end != 40;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(discoverProvider);
    // Re-query when the user's gender becomes known (e.g. profile loads).
    ref.listen<String>(matchGenderProvider, (prev, next) {
      if (prev != next) _applyFilters();
    });

    return Column(
      children: [
        _filterBar(),
        Expanded(
          child: Builder(builder: (_) {
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.profiles.isEmpty) return _buildEmptyState();
            return RefreshIndicator(
              onRefresh: () async => _applyFilters(),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                // +1 → profile-completion nudge on top of the feed.
                itemCount: state.profiles.length + 1,
                itemBuilder: (_, i) => i == 0
                    ? const ProfileCompletionCard()
                    : _ProfileCard(profile: state.profiles[i - 1]),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _filterBar() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.white,
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text('Recommended Matches',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 15)),
                    const SizedBox(width: 10),
                    if (_hasActiveFilters)
                      _activeChip(
                          'Age ${_ageRange.start.round()}-${_ageRange.end.round()}'),
                    if (_city.isNotEmpty) _activeChip(_city),
                    if (_education.isNotEmpty) _activeChip(_education),
                    if (_occupation.isNotEmpty) _activeChip(_occupation),
                  ],
                ),
              ),
            ),
            IconButton(
              onPressed: _openFilterSheet,
              icon: const Icon(Icons.tune, color: AppColors.primary),
              tooltip: 'Filters',
            ),
          ],
        ),
      );

  Widget _activeChip(String label) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Chip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          backgroundColor: AppColors.primary.withOpacity(0.1),
          visualDensity: VisualDensity.compact,
          side: BorderSide.none,
        ),
      );

  void _openFilterSheet() {
    var age = _ageRange;
    final cityCtl = TextEditingController(text: _city);
    final eduCtl = TextEditingController(text: _education);
    final occCtl = TextEditingController(text: _occupation);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Filter Profiles',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('Age: ${age.start.round()} - ${age.end.round()} yrs',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              RangeSlider(
                values: age,
                min: 18,
                max: 60,
                divisions: 42,
                activeColor: AppColors.primary,
                labels: RangeLabels('${age.start.round()}', '${age.end.round()}'),
                onChanged: (v) => setSheet(() => age = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: cityCtl,
                decoration: const InputDecoration(
                    labelText: 'Location / City',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: eduCtl,
                decoration: const InputDecoration(
                    labelText: 'Education',
                    prefixIcon: Icon(Icons.school_outlined),
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: occCtl,
                decoration: const InputDecoration(
                    labelText: 'Occupation',
                    prefixIcon: Icon(Icons.work_outline),
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _ageRange = const RangeValues(21, 40);
                          _city = '';
                          _education = '';
                          _occupation = '';
                        });
                        Navigator.pop(ctx);
                        _applyFilters();
                      },
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _ageRange = age;
                          _city = cityCtl.text.trim();
                          _education = eduCtl.text.trim();
                          _occupation = occCtl.text.trim();
                        });
                        Navigator.pop(ctx);
                        _applyFilters();
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ProfileCompletionCard(),
          const SizedBox(height: 100),
          Icon(Icons.search_off, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Center(
              child: Text('No profiles found', style: TextStyle(fontSize: 18))),
          const SizedBox(height: 8),
          const Center(
              child: Text('Try adjusting your filters',
                  style: TextStyle(color: Colors.grey))),
        ],
      );
}

/// Premium horizontal profile card: full-height photo on the left, identity
/// details + highlighted profession & salary on the right, with View Profile
/// and Interest actions.
class _ProfileCard extends ConsumerWidget {
  final ProfileModel profile;
  const _ProfileCard({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sent = ref.watch(hasSentInterestProvider(profile.id));

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shadowColor: AppColors.shadow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/profile/${profile.id}'),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Left: photo fills the full card height ──
              SizedBox(
                width: 128,
                child: profile.photos.isNotEmpty
                    ? Image.network(
                        profile.photos.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholderImage(),
                      )
                    : _placeholderImage(),
              ),
              // ── Right: identity + highlighted professional info ──
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${profile.name}, ${profile.age}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 17,
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      _detailLine(
                          Icons.location_on_outlined, '${profile.city}, ${profile.state}'),
                      const SizedBox(height: 3),
                      _detailLine(Icons.school_outlined, profile.education),
                      const SizedBox(height: 10),
                      // Profession & salary — the primary highlights.
                      _highlightLine(Icons.work_outline,
                          profile.occupation.isEmpty ? 'Profession not specified' : profile.occupation),
                      const SizedBox(height: 6),
                      _highlightLine(
                          Icons.payments_outlined,
                          profile.annualIncome.isEmpty
                              ? 'Salary not specified'
                              : '${profile.annualIncome} per annum'),
                      const SizedBox(height: 14),
                      // ── Actions: View Profile · Interest ──
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  context.push('/profile/${profile.id}'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(
                                    color: AppColors.primary, width: 1.2),
                                minimumSize: const Size.fromHeight(40),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('View Profile',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: sent
                                  ? null
                                  : () {
                                      ref
                                          .read(requestsProvider.notifier)
                                          .sendInterest(profile.id);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text(
                                            'Interest sent to ${profile.name}'),
                                        duration: const Duration(seconds: 2),
                                      ));
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    AppColors.primary.withOpacity(0.45),
                                disabledForegroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(40),
                                padding: EdgeInsets.zero,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: Text(sent ? 'Interest Sent ✓' : 'Interest',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Secondary detail row (location, education).
  Widget _detailLine(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 5),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[700], fontSize: 12.5)),
          ),
        ],
      );

  /// Prominent professional detail row (profession, salary).
  Widget _highlightLine(IconData icon, String text) => Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );

  Widget _placeholderImage() => Container(
        color: Colors.grey[200],
        child: const Icon(Icons.person, size: 64, color: Colors.grey),
      );
}
