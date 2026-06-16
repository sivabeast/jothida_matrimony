import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/phone_utils.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_provider.dart';

/// Shows a matched user's contact details (phone / WhatsApp).
///
/// Once an interest is mutually accepted, the caller passes the accepted user's
/// [contact] (read straight from their already-loaded, readable profile
/// document). That is the source of truth — no dependency on the gated
/// `contacts/{uid}` collection, a `connections` document, or Firestore rules
/// being deployed. If no embedded contact is supplied, it falls back to the
/// gated collection and finally to a friendly locked state — so it's safe to
/// drop anywhere.
class ContactRevealCard extends ConsumerWidget {
  final String otherUserId;
  final String otherName;

  /// The accepted user's contact, taken from their profile document. When this
  /// has a number, contact is shown immediately (the interest is already
  /// accepted, so it is unlocked).
  final ContactDetails? contact;

  const ContactRevealCard({
    super.key,
    required this.otherUserId,
    required this.otherName,
    this.contact,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1) Preferred: the contact embedded in the readable profile document.
    final pMobile = contact?.mobileNumber.trim() ?? '';
    final pWhatsapp = contact?.whatsappNumber?.trim() ?? '';
    if (pMobile.isNotEmpty || pWhatsapp.isNotEmpty) {
      return _shell(child: _revealed(pMobile, pWhatsapp));
    }

    // 2) Fallback: the gated contacts/{uid} collection (legacy storage).
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
        error: (_, __) => _locked(),
        data: (c) {
          final mobile = c?.mobileNumber ?? '';
          final whatsapp = c?.whatsappNumber ?? '';
          if (c == null || (mobile.isEmpty && whatsapp.isEmpty)) {
            return _locked();
          }
          return _revealed(mobile, whatsapp);
        },
      ),
    );
  }

  // ── revealed (unlocked) state ───────────────────────────────────────────
  Widget _revealed(String mobile, String whatsapp) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(unlocked: true),
          const SizedBox(height: 12),
          // Matched user's name — shown above the phone number. Falls back to
          // "Not Available" when the profile has no name.
          _infoRow(
            icon: Icons.person_outline,
            label: 'Name',
            value: otherName.trim().isNotEmpty ? otherName.trim() : 'Not Available',
          ),
          const SizedBox(height: 8),
          if (mobile.isNotEmpty)
            _contactRow(
              icon: Icons.call,
              label: mobile,
              actionLabel: 'Call',
              onTap: () => _launch(phoneCallUri(mobile)),
            ),
          if (whatsapp.isNotEmpty) ...[
            const SizedBox(height: 8),
            _contactRow(
              icon: Icons.chat,
              label: whatsapp,
              actionLabel: 'WhatsApp',
              onTap: () => _launch(whatsappUri(whatsapp)),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'You matched with $otherName — you can now connect directly.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      );

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

  /// A non-actionable detail row (label + value), used for the matched user's
  /// name. Matches the spacing/iconography of [_contactRow] but has no trailing
  /// action button.
  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
  }) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
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

  Future<void> _launch(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
