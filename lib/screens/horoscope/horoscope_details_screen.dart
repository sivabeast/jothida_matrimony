import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_provider.dart';

/// Horoscope Details — shows the signed-in user's horoscope (rasi, nakshatra,
/// lagnam, dasa, etc.) read from [myProfileProvider].
///
/// Registered at `/horoscope`. Reachable from Profile → "Horoscope Details"
/// and from the Home dashboard "Horoscope Match" quick action.
class HoroscopeDetailsScreen extends ConsumerWidget {
  const HoroscopeDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[HoroscopeDetailsScreen] build — route /horoscope opened');
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Horoscope Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: profileAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => _Message(
          icon: Icons.error_outline,
          title: 'Could not load horoscope',
          subtitle: '$e',
        ),
        data: (profile) {
          if (profile == null) {
            return _Message(
              icon: Icons.auto_awesome_outlined,
              title: 'No horoscope yet',
              subtitle:
                  'Complete your profile to generate your horoscope details.',
              actionLabel: 'Create Profile',
              onAction: () => context.push('/profile/create'),
            );
          }
          final h = profile.horoscope;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeaderCard(profile: profile),
              const SizedBox(height: 16),
              _Section(title: 'Birth Details', fields: [
                _Field('Date of Birth', _formatDate(profile.dateOfBirth)),
                _Field('Birth Time', h.birthTime),
                _Field('Birth Place', h.birthPlace),
              ]),
              const SizedBox(height: 12),
              _Section(title: 'Horoscope', fields: [
                _Field('Rasi (Moon Sign)', h.rasi),
                _Field('Nakshatra (Star)', h.nakshatra),
                _Field('Lagnam (Ascendant)', h.lagnam),
                _Field('Dasa Balance', h.dasaBalance),
                _Field('Yogam', h.yogam),
                _Field('Karanam', h.karanam),
                _Field('Sun Sign', h.sunSign),
                _Field('Moon Sign', h.moonSign),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/profile/${profile.id}/edit'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Horoscope'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
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
          Text(
            profile.name,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text('$rasi  •  $star',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              h.badgeText,
              style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field {
  final String label;
  final String value;
  const _Field(this.label, this.value);
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Field> fields;
  const _Section({required this.title, required this.fields});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
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
          const SizedBox(height: 8),
          ...fields.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        flex: 5,
                        child: Text(f.label,
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 13))),
                    Expanded(
                      flex: 6,
                      child: Text(
                        f.value.trim().isEmpty ? '—' : f.value,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

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
            Text(title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600])),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
