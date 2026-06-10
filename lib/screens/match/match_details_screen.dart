import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/compatibility.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_provider.dart';
import '../../providers/requests_provider.dart';
import '../astrologer/connect_astrologer_sheet.dart';

/// Compares the logged-in user with a selected [profileId] and shows a full
/// marriage-compatibility experience (match %, 10 poruthams, category summary).
class MatchDetailsScreen extends ConsumerStatefulWidget {
  final String profileId;
  const MatchDetailsScreen({super.key, required this.profileId});

  @override
  ConsumerState<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends ConsumerState<MatchDetailsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _percentAnim;
  CompatibilityResult? _result;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _percentAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final otherAsync = ref.watch(profileByIdProvider(widget.profileId));
    final me = ref.watch(myProfileProvider).valueOrNull;
    final isMatched = ref.watch(isMatchedProvider(widget.profileId));

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Match Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      // Compatibility analysis is gated until both users mutually connect.
      body: !isMatched
          ? _lockedView(context)
          : otherAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (other) {
          if (other == null) {
            return const Center(child: Text('Profile not found'));
          }
          _result ??= computeCompatibility(me, other);
          _controller.forward();
          final r = _result!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _header(me, other, r),
              const SizedBox(height: 20),
              _poruthamCard(r),
              const SizedBox(height: 16),
              _categoryCard(r),
              const SizedBox(height: 16),
              _strengthsCard(r),
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
    final alreadySent = ref.watch(hasSentInterestProvider(widget.profileId));
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
              child: const Icon(Icons.lock_outline, size: 54, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text('Compatibility is locked',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              'Match analysis, porutham results and horoscope compatibility unlock '
              'only after ${other?.name ?? 'this person'} accepts your interest.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: alreadySent
                    ? null
                    : () {
                        ref
                            .read(requestsProvider.notifier)
                            .sendInterest(widget.profileId);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Interest sent')),
                        );
                      },
                icon: Icon(alreadySent ? Icons.check : Icons.favorite, size: 18),
                label: Text(alreadySent ? 'Interest Sent' : 'Send Interest'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  // ── Compact header: [ photo ]  [ % ]  [ photo ] in a single short row ───
  Widget _header(ProfileModel? me, ProfileModel other, CompatibilityResult r) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
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
          _scoreCenter(r),
          Expanded(
            child: _squareProfile(
                other.photos.isNotEmpty ? other.photos.first : null, other.name),
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
                  ? Image.network(url, fit: BoxFit.cover,
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
                  color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      );

  Widget _photoFallback() => Container(
        color: Colors.white,
        child: const Icon(Icons.person, size: 34, color: AppColors.primary),
      );

  Widget _scoreCenter(CompatibilityResult r) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: AnimatedBuilder(
          animation: _percentAnim,
          builder: (_, __) {
            final value = (_percentAnim.value * r.matchPercent).round();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 74,
                  height: 74,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 74,
                        height: 74,
                        child: CircularProgressIndicator(
                          value: _percentAnim.value * r.matchPercent / 100,
                          strokeWidth: 6,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$value%',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold)),
                          const Text('Match',
                              style: TextStyle(color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(r.verdict,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.gold,
                        fontWeight: FontWeight.w600,
                        fontSize: 11)),
              ],
            );
          },
        ),
      );

  // ── Porutham summary ───────────────────────────────────────────────────
  Widget _poruthamCard(CompatibilityResult r) {
    return _card(
      title: 'Marriage Compatibility (Porutham)',
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${r.matchedPoruthams} / ${r.totalPoruthams} Poruthams matched',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text('Score ${r.matchPercent}%',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: r.matchedPoruthams / r.totalPoruthams,
              minHeight: 10,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation(AppColors.success),
            ),
          ),
          const SizedBox(height: 14),
          ...r.poruthams.map((p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(p.matched ? Icons.check_circle : Icons.cancel,
                        size: 18,
                        color: p.matched ? AppColors.success : Colors.grey[400]),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${p.name} Porutham')),
                    Text(p.note,
                        style: TextStyle(
                            fontSize: 12,
                            color: p.matched ? AppColors.success : Colors.grey)),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ── Category breakdown ─────────────────────────────────────────────────
  Widget _categoryCard(CompatibilityResult r) {
    return _card(
      title: 'Compatibility Summary',
      child: Column(
        children: r.categories
            .map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Icon(c.icon, size: 20, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(c.label,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text('${c.score}%',
                                    style: TextStyle(
                                        color: c.isStrong
                                            ? AppColors.success
                                            : AppColors.warning,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 3),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: c.score / 100,
                                minHeight: 6,
                                backgroundColor: Colors.grey[200],
                                valueColor: AlwaysStoppedAnimation(
                                    c.isStrong ? AppColors.success : AppColors.warning),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(c.detail,
                                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  // ── Strengths & concerns ───────────────────────────────────────────────
  Widget _strengthsCard(CompatibilityResult r) {
    return _card(
      title: 'Why this is a good match',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...r.strengths.map((s) => _bullet(s, Icons.check_circle, AppColors.success)),
          if (r.concerns.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Points to discuss',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ...r.concerns.map((s) => _bullet(s, Icons.info_outline, AppColors.warning)),
          ],
        ],
      ),
    );
  }

  Widget _bullet(String text, IconData icon, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );

  // ── Connect Astrologer CTA ─────────────────────────────────────────────
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}
