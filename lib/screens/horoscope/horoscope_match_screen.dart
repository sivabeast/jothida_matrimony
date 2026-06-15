import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/porutham_match.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_provider.dart';

/// Horoscope Match Result page (Interests → Accepted → "Horoscope").
///
/// Compares the logged-in member's horoscope with an accepted member's
/// horoscope and shows ONLY the compatibility analysis (10 Thirumana
/// Poruthams, overall match %, star rating and recommendation). The raw
/// horoscope fields of the other member are never displayed here — privacy is
/// preserved; only derived compatibility is shown.
class HoroscopeMatchScreen extends ConsumerWidget {
  final String userId; // UID of the accepted member
  const HoroscopeMatchScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meAsync = ref.watch(myProfileProvider);
    final otherAsync = ref.watch(profileByUserIdProvider(userId));

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Horoscope Match'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Builder(builder: (_) {
        if (meAsync.isLoading || otherAsync.isLoading) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        final me = meAsync.valueOrNull;
        final other = otherAsync.valueOrNull;
        if (me == null) {
          return const _Message(
            icon: Icons.person_off_outlined,
            text: 'Complete your own horoscope to see a match result.',
          );
        }
        if (other == null) {
          return const _Message(
            icon: Icons.auto_awesome_outlined,
            text: 'Match result is unavailable for this member.',
          );
        }
        final result = computePorutham(me, other);
        if (result == null) {
          return const _Message(
            icon: Icons.auto_awesome_outlined,
            text:
                'Not enough horoscope data to calculate compatibility for this pair.',
          );
        }
        return _ResultView(result: result, other: other);
      }),
    );
  }
}

class _ResultView extends StatelessWidget {
  final PoruthamMatchResult result;
  final ProfileModel other;
  const _ResultView({required this.result, required this.other});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ScoreCard(result: result, otherName: other.name),
        const SizedBox(height: 16),
        _PoruthamGroup(
          title: 'Matching Poruthams',
          items: result.matching,
          matched: true,
        ),
        if (result.nonMatching.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PoruthamGroup(
            title: 'Needs Attention',
            items: result.nonMatching,
            matched: false,
          ),
        ],
        const SizedBox(height: 16),
        _RecommendationCard(result: result),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'This is an automated compatibility estimate based on both members\' '
            'birth-star details. For a final decision, please consult a '
            'qualified astrologer.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final PoruthamMatchResult result;
  final String otherName;
  const _ScoreCard({required this.result, required this.otherName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text('Compatibility with $otherName',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 14),
          Text(result.category.emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(height: 6),
          // Category label only — no percentage, no score.
          Text(result.category.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          // A count of matched poruthams (e.g. "8 of 10") — not a percentage.
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${result.matchedCount} of ${result.totalCount} poruthams matched',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _PoruthamGroup extends StatelessWidget {
  final String title;
  final List<PoruthamResult> items;
  final bool matched;
  const _PoruthamGroup(
      {required this.title, required this.items, required this.matched});

  @override
  Widget build(BuildContext context) {
    final color = matched ? AppColors.success : AppColors.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(matched ? Icons.check_circle : Icons.error_outline,
                  color: color, size: 18),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      fontSize: 15,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
          const Divider(height: 16),
          for (final p in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(matched ? Icons.check : Icons.close,
                      color: color, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.name,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w500)),
                  ),
                  Text(p.note,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final PoruthamMatchResult result;
  const _RecommendationCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, color: AppColors.primary, size: 18),
              SizedBox(width: 6),
              Text('Recommendation',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 8),
          Text(result.recommendation,
              style: const TextStyle(fontSize: 13.5, height: 1.4)),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Message({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.primary.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
