import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/locale_provider.dart';

/// Language selection — shown on first launch (no language chosen yet) and
/// reachable from Settings to switch any time. The prompt is intentionally
/// bilingual since the user hasn't picked a language yet.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider)?.languageCode;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      // Use the Material Navigator (present in both MaterialApp and
      // MaterialApp.router). go_router's context.canPop() would assert on first
      // launch where the screen is shown outside the router.
      appBar: Navigator.of(context).canPop()
          ? AppBar(
              title: const Text('Language / மொழி'),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.translate, size: 64, color: AppColors.primary),
              const SizedBox(height: 16),
              const Text(
                'Choose your language\nஉங்கள் மொழியைத் தேர்ந்தெடுக்கவும்',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              _LanguageTile(
                title: 'English',
                subtitle: 'English',
                selected: current == 'en',
                onTap: () => _choose(context, ref, const Locale('en')),
              ),
              const SizedBox(height: 14),
              _LanguageTile(
                title: 'தமிழ்',
                subtitle: 'Tamil',
                selected: current == 'ta',
                onTap: () => _choose(context, ref, const Locale('ta')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref, Locale locale) async {
    await ref.read(localeProvider.notifier).setLocale(locale);
    if (!context.mounted) return;
    // From Settings → pop back. On first launch the app root rebuilds into the
    // router automatically once a locale is set, so no navigation is needed.
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }
}

class _LanguageTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.withOpacity(0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(subtitle,
                      style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.primary : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
