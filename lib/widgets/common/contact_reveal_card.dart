import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/profile_provider.dart';

/// Shows a matched user's contact details (phone / WhatsApp).
///
/// Contact details live in the access-gated `contacts/{userId}` collection and
/// unlock ONLY after a mutually-accepted interest. If they are still locked
/// (the Firestore read is denied) or unavailable, a friendly locked state is
/// shown instead of the numbers — so this widget is safe to drop into any
/// profile/match screen.
class ContactRevealCard extends ConsumerWidget {
  final String otherUserId;
  final String otherName;

  const ContactRevealCard({
    super.key,
    required this.otherUserId,
    required this.otherName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No user id (e.g. demo data) → nothing to unlock.
    if (otherUserId.isEmpty) return _shell(child: _locked());

    final contactAsync = ref.watch(contactByUserIdProvider(otherUserId));
    return _shell(
      child: contactAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        // A denied read (still locked) lands here — show the locked state, not
        // a raw error.
        error: (_, __) => _locked(),
        data: (c) {
          final mobile = c?.mobileNumber ?? '';
          final whatsapp = c?.whatsappNumber ?? '';
          if (c == null || (mobile.isEmpty && whatsapp.isEmpty)) {
            return _locked();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(unlocked: true),
              const SizedBox(height: 12),
              if (mobile.isNotEmpty)
                _contactRow(
                  icon: Icons.call,
                  label: mobile,
                  actionLabel: 'Call',
                  onTap: () => _launch('tel:$mobile'),
                ),
              if (whatsapp.isNotEmpty) ...[
                const SizedBox(height: 8),
                _contactRow(
                  icon: Icons.chat,
                  label: whatsapp,
                  actionLabel: 'WhatsApp',
                  onTap: () =>
                      _launch('https://wa.me/${_digits(whatsapp)}'),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'You matched with $otherName — you can now connect directly.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── pieces ────────────────────────────────────────────────────────────────
  Widget _shell({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: child,
      );

  Widget _title({required bool unlocked}) => Row(
        children: [
          Icon(unlocked ? Icons.lock_open : Icons.lock_outline,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            unlocked ? 'Contact details' : 'Contact locked',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      );

  Widget _locked() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(unlocked: false),
          const SizedBox(height: 8),
          Text(
            'Contact details unlock once your interest is mutually accepted.',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
        ],
      );

  Widget _contactRow({
    required IconData icon,
    required String label,
    required String actionLabel,
    required VoidCallback onTap,
  }) =>
      Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          TextButton(onPressed: onTap, child: Text(actionLabel)),
        ],
      );

  String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
