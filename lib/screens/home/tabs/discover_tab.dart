import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/profile_model.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/requests_provider.dart';

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
  String _gender = 'Female';

  @override
  void initState() {
    super.initState();
    Future.microtask(_applyFilters);
  }

  void _applyFilters() {
    ref.read(discoverProvider.notifier).load(gender: _gender, filters: {
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
                itemCount: state.profiles.length,
                itemBuilder: (_, i) => _ProfileCard(profile: state.profiles[i]),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _filterBar() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Colors.white,
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _genderToggle(),
                    const SizedBox(width: 8),
                    if (_hasActiveFilters)
                      _activeChip('Age ${_ageRange.start.round()}-${_ageRange.end.round()}'),
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

  Widget _genderToggle() => SegmentedButton<String>(
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: 'Female', label: Text('Brides')),
          ButtonSegment(value: 'Male', label: Text('Grooms')),
        ],
        selected: {_gender},
        onSelectionChanged: (s) {
          setState(() => _gender = s.first);
          _applyFilters();
        },
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
        children: [
          const SizedBox(height: 120),
          Icon(Icons.search_off, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Center(child: Text('No profiles found', style: TextStyle(fontSize: 18))),
          const SizedBox(height: 8),
          const Center(
              child: Text('Try adjusting your filters',
                  style: TextStyle(color: Colors.grey))),
        ],
      );
}

class _ProfileCard extends ConsumerWidget {
  final ProfileModel profile;
  const _ProfileCard({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sent = ref.watch(hasSentInterestProvider(profile.id));

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Tapping opens a basic profile view (compatibility stays gated until
        // a mutual match — see Match Details).
        onTap: () => context.push('/profile/${profile.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top: square photo (left) + key info (right) ──
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    height: 150,
                    child: profile.photos.isNotEmpty
                        ? Image.network(profile.photos.first,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholderImage())
                        : _placeholderImage(),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${profile.name}, ${profile.age}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          _iconLine(Icons.location_on,
                              '${profile.city}, ${profile.state}'),
                          _iconLine(Icons.school, profile.education),
                          _iconLine(Icons.work_outline, profile.occupation),
                          _iconLine(Icons.spa_outlined, profile.religion),
                          if (profile.about.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Expanded(
                              child: Text(profile.about,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 12)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Bottom: Send Interest ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: sent
                    ? OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Interest Sent'),
                      )
                    : ElevatedButton.icon(
                        onPressed: () {
                          ref
                              .read(requestsProvider.notifier)
                              .sendInterest(profile.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Interest sent to ${profile.name}'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.favorite, size: 18),
                        label: const Text('Send Interest'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(42),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconLine(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            Icon(icon, size: 13, color: Colors.grey[500]),
            const SizedBox(width: 4),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[700], fontSize: 12.5)),
            ),
          ],
        ),
      );

  Widget _placeholderImage() => Container(
        color: Colors.grey[200],
        child: const Icon(Icons.person, size: 64, color: Colors.grey),
      );
}
