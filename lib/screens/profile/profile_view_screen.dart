import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/interest_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/contact_reveal_card.dart';
import '../../widgets/common/gradient_button.dart';

class ProfileViewScreen extends ConsumerStatefulWidget {
  /// Open by profile-document id — used from Discover / Matches, where the id
  /// comes straight from the loaded profile and is reliable.
  final String? profileId;

  /// Open by the profile owner's USER id (UID) — preferred from accepted
  /// interests, where the UID (senderId / receiverId) is the dependable key and
  /// a stored profile-document id may be stale or missing.
  final String? userId;

  const ProfileViewScreen({super.key, this.profileId, this.userId})
      : assert(profileId != null || userId != null,
            'Provide either a profileId or a userId');

  @override
  ConsumerState<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends ConsumerState<ProfileViewScreen> {
  int _photoIndex = 0;

  /// Guards the one-time view-count increment for this screen instance.
  bool _viewCounted = false;

  /// Records a single profile view per screen-open, and never when the owner
  /// views their own profile. This previously lived inside build(), so it fired
  /// on every rebuild (photo swipes, scrolls, parent rebuilds) and also counted
  /// self-views — which silently inflated viewCount into the hundreds.
  void _recordViewOnce(ProfileModel profile) {
    if (_viewCounted) return;
    final myUid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
    if (myUid != null && myUid == profile.userId) return; // skip self-views
    _viewCounted = true;
    // Best-effort: a non-owner view-count write may be denied by Firestore
    // rules — swallow it so it can NEVER surface as a "couldn't load" error.
    ref
        .read(profileRepositoryProvider)
        .incrementViewCount(profile.id)
        .catchError((_) {});
  }

  Future<void> _sendInterest(ProfileModel profile) async {
    final userId = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
    if (userId == null) return;
    final myProfile = await ref.read(profileRepositoryProvider).getProfileByUserId(userId);
    if (myProfile == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Create your profile first to send interest')));
      }
      return;
    }
    await ref.read(interestNotifierProvider.notifier).sendInterest(
          senderId: userId,
          receiverId: profile.userId,
          senderProfileId: myProfile.id,
          receiverProfileId: profile.id,
        );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Interest sent successfully!')));
    }
  }

  void _reportProfile(ProfileModel profile) {
    context.push('/report/${profile.id}');
  }

  void _showContact(ProfileModel profile) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ContactRevealCard(
                otherUserId: profile.userId,
                otherName: profile.name,
                contact: profile.contact),
          ],
        ),
      ),
    );
  }

  /// Status-aware bottom action. Source of truth is the real Firestore interest
  /// status, so an accepted interest never shows "Send Interest" again.
  Widget _interestAction(ProfileModel profile) {
    final accepted = ref.watch(isInterestAcceptedProvider(profile.id));
    final alreadySent =
        ref.watch(hasSentInterestToProfileProvider(profile.id));

    if (accepted) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 18),
                SizedBox(width: 8),
                Text('Interest accepted',
                    style: TextStyle(
                        color: Colors.green, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              // Interest is accepted → contact is unlocked. Reveal it straight
              // from the (readable) profile document — no connection/gated read.
              onPressed: () => _showContact(profile),
              icon: const Icon(Icons.call),
              label: const Text('View Contact'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      );
    }

    if (alreadySent) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.check_circle),
          label: const Text('Interest Sent'),
          style: ElevatedButton.styleFrom(
            disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
            disabledForegroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: GradientButton(
        onPressed: () => _sendInterest(profile),
        text: 'Send Interest',
      ),
    );
  }

  /// Re-fetch whichever lookup this screen was opened with.
  void _reloadProfile() {
    if (widget.userId != null) {
      ref.invalidate(profileByUserIdProvider(widget.userId!));
    } else {
      ref.invalidate(profileByIdProvider(widget.profileId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prefer the UID lookup when opened from an accepted interest; otherwise use
    // the profile-document id. Both yield AsyncValue<ProfileModel?>.
    final profileAsync = widget.userId != null
        ? ref.watch(profileByUserIdProvider(widget.userId!))
        : ref.watch(profileByIdProvider(widget.profileId!));

    return Scaffold(
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Couldn\'t load this profile right now. Please try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _reloadProfile,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary)),
                ),
              ],
            ),
          ),
        ),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Profile not found'));
          }
          // Record a single view after this frame — never mutate a provider
          // during build. The guard inside _recordViewOnce ensures exactly one
          // increment per screen-open and skips the owner's own visits.
          if (!_viewCounted) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _recordViewOnce(profile));
          }
          return _buildProfileView(profile);
        },
      ),
    );
  }

  Widget _buildProfileView(ProfileModel profile) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => _reportProfile(profile),
              tooltip: 'Report',
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                profile.photos.isNotEmpty
                    ? Image.network(profile.photos[_photoIndex], fit: BoxFit.cover)
                    : Container(
                        color: AppColors.primary.withOpacity(0.3),
                        child: const Icon(Icons.person, size: 100, color: Colors.white)),
                // Photo dots
                if (profile.photos.length > 1)
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        profile.photos.length,
                        (i) => GestureDetector(
                          onTap: () => setState(() => _photoIndex = i),
                          child: Container(
                            width: _photoIndex == i ? 20 : 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: _photoIndex == i ? Colors.white : Colors.white54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile.name, style: AppTextStyles.heading1),
                        Text(
                          '${profile.age} yrs • ${profile.city}',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    if (profile.horoscopeDetails.isAstrologerVerified)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green[200]!),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, color: Colors.green, size: 14),
                            SizedBox(width: 4),
                            Text('Verified', style: TextStyle(color: Colors.green, fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (profile.about.isNotEmpty) ...[
                  Text('About', style: AppTextStyles.heading3),
                  const SizedBox(height: 8),
                  Text(profile.about, style: AppTextStyles.bodyMedium),
                  const SizedBox(height: 20),
                ],
                _buildInfoSection('Personal Details', [
                  _InfoItem(Icons.cake_outlined, 'Age', '${profile.age} years'),
                  _InfoItem(Icons.school_outlined, 'Education', profile.education),
                  _InfoItem(Icons.work_outline, 'Occupation', profile.occupation),
                  _InfoItem(Icons.church_outlined, 'Religion', profile.religion),
                  _InfoItem(Icons.people_outline, 'Caste', profile.caste ?? 'Not specified'),
                  _InfoItem(Icons.wc, 'Marital Status', profile.maritalStatus),
                ]),
                const SizedBox(height: 20),
                _buildInfoSection('Horoscope', [
                  _InfoItem(Icons.stars, 'Rasi', profile.horoscopeDetails.rasi),
                  _InfoItem(Icons.star_border, 'Nakshatra', profile.horoscopeDetails.nakshatra),
                  _InfoItem(Icons.wb_twilight, 'Lagnam', profile.horoscopeDetails.lagnam),
                  _InfoItem(Icons.place_outlined, 'Birth Place', profile.horoscopeDetails.birthPlace),
                ]),
                const SizedBox(height: 32),
                // Status-aware action: accepted → View Contact (never "Send
                // Interest" again); pending → "Interest Sent"; otherwise the
                // Send Interest button.
                _interestAction(profile),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection(String title, List<_InfoItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.heading3),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: items
                .where((item) => item.value.isNotEmpty)
                .map((item) => ListTile(
                      dense: true,
                      leading: Icon(item.icon, size: 20, color: AppColors.primary),
                      title: Text(item.label,
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: Text(item.value,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;

  const _InfoItem(this.icon, this.label, this.value);
}
