import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_provider.dart';

/// Read-only horoscope view for an **accepted** match.
///
/// Reached from Interests → Accepted → "Horoscope". It loads the other
/// member's public (approved & active) profile via [profileByUserIdProvider] —
/// the same query used by "View Profile", so both members of a mutually
/// accepted interest can view each other's horoscope. The horoscope ships
/// inside the public profile document, so no premium access, connection unlock
/// or compatibility gate is involved.
class MemberHoroscopeScreen extends ConsumerWidget {
  final String userId;
  const MemberHoroscopeScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileByUserIdProvider(userId));

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Horoscope Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: profileAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => const _Unavailable(),
        data: (profile) {
          if (profile == null) return const _Unavailable();
          final h = profile.horoscope;

          // "Unavailable" = no horoscope-specific data on file. The birth date
          // always exists on a profile, so it doesn't count towards this check.
          final hasAny = [
            h.rasi,
            h.nakshatra,
            h.lagnam,
            h.dosham,
            h.dasaBalance,
            h.yogam,
            h.karanam,
            h.sunSign,
            h.moonSign,
            h.birthTime,
            h.birthPlace,
          ].any((v) => v.trim().isNotEmpty);
          if (!hasAny) return const _Unavailable();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeaderCard(profile: profile),
              const SizedBox(height: 16),
              _Section(title: 'Birth Details', rows: [
                _Row('Birth Date', _fmtDate(profile.dateOfBirth)),
                _Row('Birth Time', h.birthTime),
                _Row('Birth Place', h.birthPlace),
              ]),
              const SizedBox(height: 12),
              _Section(title: 'Horoscope', rows: [
                _Row('Rasi (Moon Sign)', h.rasi),
                _Row('Nakshatra (Star)', h.nakshatra),
                _Row('Lagnam (Ascendant)', h.lagnam),
                _Row('Dosham', h.dosham),
                _Row('Dasa Balance', h.dasaBalance),
                _Row('Yogam', h.yogam),
                _Row('Karanam', h.karanam),
                _Row('Sun Sign', h.sunSign),
                _Row('Moon Sign', h.moonSign),
              ]),
            ],
          );
        },
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
}

/// A label/value pair (value falls back to "—" when empty).
class _Row {
  final String label;
  final String value;
  const _Row(this.label, this.value);
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined,
                size: 64, color: AppColors.primary.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text(
              'Horoscope details not available.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final ProfileModel profile;
  const _HeaderCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final h = profile.horoscope;
    final rasi = h.rasi.trim().isEmpty ? '—' : h.rasi;
    final star = h.nakshatra.trim().isEmpty ? '—' : h.nakshatra;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(Icons.auto_awesome, color: AppColors.gold, size: 40),
          const SizedBox(height: 8),
          Text(profile.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('$rasi  •  $star',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Row> rows;
  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
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
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          const Divider(height: 16),
          for (final r in rows) _ValueRow(label: r.label, value: r.value),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String label;
  final String value;
  const _ValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(label,
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ),
          Expanded(
            flex: 6,
            child: Text(value.trim().isEmpty ? '—' : value,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
