import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/porutham_match.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/interest_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/requests_provider.dart';
import '../../widgets/common/contact_reveal_card.dart';
import '../../widgets/common/horoscope_match_badge.dart' show categoryColor;
import '../astrologer/connect_astrologer_sheet.dart';

/// Compares the logged-in user with a selected [profileId] and shows the
/// traditional 10-Porutham marriage compatibility — which poruthams matched and
/// the final category. NO percentage / score is shown anywhere.
class MatchDetailsScreen extends ConsumerStatefulWidget {
  final String profileId;
  const MatchDetailsScreen({super.key, required this.profileId});

  @override
  ConsumerState<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends ConsumerState<MatchDetailsScreen> {
  @override
  Widget build(BuildContext context) {
    final otherAsync = ref.watch(profileByIdProvider(widget.profileId));
    final me = ref.watch(myProfileProvider).valueOrNull;
    // Unlocked when the two users have a mutually-accepted interest.
    final isMatched = ref.watch(isInterestAcceptedProvider(widget.profileId)) ||
        ref.watch(isMatchedProvider(widget.profileId));

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Match Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: !isMatched
          ? _lockedView(context)
          : otherAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Couldn\'t load this profile right now. Please try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
              data: (other) {
                if (other == null) {
                  return const Center(child: Text('Profile not found'));
                }
                final result = me == null ? null : computePorutham(me, other);
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _header(me, other, result),
                    const SizedBox(height: 20),
                    if (result == null)
                      _card(
                        title: 'Marriage Compatibility (Porutham)',
                        child: const Text(
                          'Not enough horoscope data to calculate the poruthams '
                          'for this pair. Add birth-star details to both profiles.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      )
                    else ...[
                      _poruthamCard(result),
                      const SizedBox(height: 16),
                      _recommendationCard(result),
                    ],
                    const SizedBox(height: 16),
                    // Contact details — unlocked after a mutually-accepted interest.
                    ContactRevealCard(
                      otherUserId: other.userId,
                      otherName: other.name,
                      contact: other.contact,
                    ),
                    const SizedBox(height: 16),
                    // Family Tree of the matched member — this whole view is
                    // already gated behind `isMatched`, so it's only reachable
                    // for an accepted match.
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            context.push('/family-tree-user/${other.userId}'),
                        icon: const Icon(Icons.account_tree_outlined),
                        label: const Text('🌳 Family Details'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _connectAstrologerCard(),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
    );
  }

  // Shown when the two users have not yet mutually accepted.
  Widget _lockedView(BuildContext context) {
    final other = ref.watch(profileByIdProvider(widget.profileId)).valueOrNull;
    final alreadySent =
        ref.watch(hasSentInterestToProfileProvider(widget.profileId)) ||
            ref.watch(hasSentInterestProvider(widget.profileId));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline,
                  size: 54, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text('Compatibility is locked',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              'Porutham results and horoscope compatibility unlock only after '
              '${other?.name ?? 'this person'} accepts your interest.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: alreadySent ? null : () => _sendInterest(other),
                icon: Icon(alreadySent ? Icons.check_circle : Icons.favorite,
                    size: 18),
                label: Text(alreadySent ? 'Interest Sent' : 'Send Interest'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Back to Discover'),
            ),
          ],
        ),
      ),
    );
  }

  /// Sends an interest via the REAL Firestore flow.
  Future<void> _sendInterest(ProfileModel? other) async {
    final me = ref.read(myProfileProvider).valueOrNull;
    if (me == null || other == null) {
      _showSnack('Create your profile first to send interest');
      return;
    }
    try {
      await ref.read(interestNotifierProvider.notifier).sendInterest(
            senderId: me.userId,
            receiverId: other.userId,
            senderProfileId: me.id,
            receiverProfileId: other.id,
          );
      if (mounted) _showSnack('Interest sent');
    } catch (_) {
      if (mounted) _showSnack('Could not send interest. Please try again.');
    }
  }

  void _showSnack(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // ── Header: [ photo ]  [ category ]  [ photo ] ─────────────────────────────
  Widget _header(
      ProfileModel? me, ProfileModel other, PoruthamMatchResult? result) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _squareProfile(
                me?.photos.isNotEmpty == true ? me!.photos.first : null,
                me?.name ?? 'You'),
          ),
          _categoryCenter(result),
          Expanded(
            child: _squareProfile(
                other.photos.isNotEmpty ? other.photos.first : null,
                other.name),
          ),
        ],
      ),
    );
  }

  Widget _squareProfile(String? url, String name) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 64,
              height: 64,
              child: url != null
                  ? Image.network(url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _photoFallback())
                  : _photoFallback(),
            ),
          ),
          const SizedBox(height: 6),
          Text(name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ],
      );

  Widget _photoFallback() => Container(
        color: Colors.white,
        child: const Icon(Icons.person, size: 34, color: AppColors.primary),
      );

  /// Center of the header — the compatibility CATEGORY (emoji + label), no %.
  Widget _categoryCenter(PoruthamMatchResult? result) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: 96,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(result?.category.emoji ?? '❔',
                  style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 4),
              Text(result?.category.label ?? 'Not available',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              if (result != null) ...[
                const SizedBox(height: 2),
                Text('${result.matchedCount}/${result.totalCount} matched',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 10.5)),
              ],
            ],
          ),
        ),
      );

  // ── Porutham list (✓ / ✗) — no percentage, no progress bar ────────────────
  Widget _poruthamCard(PoruthamMatchResult r) {
    return _card(
      title: 'Marriage Compatibility (Porutham)',
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
                '${r.matchedCount} of ${r.totalCount} poruthams matched',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          const SizedBox(height: 12),
          ...r.poruthams.map((p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(p.matched ? Icons.check_circle : Icons.cancel,
                        size: 18,
                        color:
                            p.matched ? AppColors.success : AppColors.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(p.name)),
                    Text(p.matched ? 'Matched' : 'Not matched',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: p.matched
                                ? AppColors.success
                                : AppColors.error)),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ── Final category + recommendation ───────────────────────────────────────
  Widget _recommendationCard(PoruthamMatchResult r) {
    final color = categoryColor(r.category);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(r.category.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(r.category.label,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Text(r.recommendation,
              style: const TextStyle(fontSize: 13.5, height: 1.4)),
        ],
      ),
    );
  }

  // ── Connect Astrologer CTA ─────────────────────────────────────────────────
  Widget _connectAstrologerCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [AppColors.gold.withOpacity(0.18), AppColors.background]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          const Icon(Icons.auto_awesome, color: AppColors.goldDark, size: 30),
          const SizedBox(height: 8),
          const Text('Want an expert opinion?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Connect with a verified astrologer for a detailed porutham & horoscope analysis.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => showConnectAstrologerSheet(context),
              icon: const Icon(Icons.person_search),
              label: const Text('Connect Astrologer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
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

  Widget _card({required String title, required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}
