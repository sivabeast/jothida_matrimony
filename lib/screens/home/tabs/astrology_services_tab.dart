import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../horoscope/horoscope_matching_screen.dart';

/// The Home "Astrology" tab.
///
/// The app no longer has an astrologer marketplace — users never choose an
/// astrologer. Instead this tab is the entry point to the single internal
/// astrology service: it lists the user's accepted matches (horoscope unlocked)
/// and lets them send any pairing for a Match Analysis, plus a shortcut to track
/// requests in "My Match Analysis".
class AstrologyServicesTab extends ConsumerWidget {
  const AstrologyServicesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppColors.scaffoldBg,
      child: Column(
        children: [
          _header(context),
          const Expanded(child: AcceptedMatchesView()),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Horoscope Compatibility',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 17),
              ),
            ),
            TextButton.icon(
              onPressed: () => context.push('/my-analysis'),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('My Reports'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
      );
}
