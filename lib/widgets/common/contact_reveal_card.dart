import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
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
///
/// PRIVACY (§16–§18): when the owner keeps "Hide Phone Number" on — which is
/// the DEFAULT — [hiddenByOwner] short-circuits everything and the card simply
/// states that the number is private. Accepting an interest never changes
/// that, and the card never offers a way to reveal it.
class ContactRevealCard extends ConsumerWidget {
  final String otherUserId;
  final String otherName;

  /// The accepted user's contact, taken from their profile document. When this
  /// has a number, contact is shown immediately (the interest is already
  /// accepted, so it is unlocked).
  final ContactDetails? contact;

  /// The owner keeps their phone number private (§17).
  final bool hiddenByOwner;

  const ContactRevealCard({
    super.key,
    required this.otherUserId,
    required this.otherName,
    this.contact,
    this.hiddenByOwner = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 0) The owner's privacy switch wins over everything else.
    if (hiddenByOwner) {
      return _shell(child: _private(context));
    }

    // 1) Preferred: the contact embedded in the readable profile document.
    final pMobile = contact?.mobileNumber.trim() ?? '';
    final pWhatsapp = contact?.whatsappNumber?.trim() ?? '';
    if (pMobile.isNotEmpty || pWhatsapp.isNotEmpty) {
      return _shell(child: _revealed(context, pMobile, pWhatsapp));
    }

    // 2) Fallback: the gated contacts/{uid} collection (legacy storage).
    if (otherUserId.isEmpty) return _shell(child: _locked(context));
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
        error: (_, __) => _locked(context),
        data: (c) {
          final mobile = c?.mobileNumber ?? '';
          final whatsapp = c?.whatsappNumber ?? '';
          if (c == null || (mobile.isEmpty && whatsapp.isEmpty)) {
            return _locked(context);
          }
          return _revealed(context, mobile, whatsapp);
        },
      ),
    );
  }

  // ── revealed (unlocked) state ───────────────────────────────────────────
  Widget _revealed(BuildContext context, String mobile, String whatsapp) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, unlocked: true),
        const SizedBox(height: 12),
        // Matched user's name — shown above the phone number.
        _infoRow(
          icon: Icons.person_outline,
          label: l10n.name,
          value: otherName.trim().isNotEmpty
              ? otherName.trim()
              : l10n.notAvailable,
        ),
        const SizedBox(height: 8),
        if (mobile.isNotEmpty)
          _contactRow(
            icon: Icons.call,
            label: mobile,
            actionLabel: l10n.callAction,
            onTap: () => _launch(phoneCallUri(mobile)),
          ),
        if (whatsapp.isNotEmpty) ...[
          const SizedBox(height: 8),
          _contactRow(
            icon: Icons.chat,
            label: whatsapp,
            actionLabel: l10n.whatsapp,
            onTap: () => _launch(whatsappUri(whatsapp)),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          l10n.youMatchedConnectNow(otherName),
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
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

  Widget _title(BuildContext context, {required bool unlocked}) => Row(
        children: [
          Icon(unlocked ? Icons.lock_open : Icons.lock_outline,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            unlocked
                ? context.l10n.contactDetailsTitle
                : context.l10n.contactLockedTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      );

  Widget _locked(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(context, unlocked: false),
          const SizedBox(height: 8),
          Text(
            context.l10n.contactUnlocksAfterAccept,
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
        ],
      );

  /// The owner chose to keep their number private — a settled state, not a
  /// "not yet" one, so it never suggests the number could be unlocked.
  Widget _private(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(context, unlocked: false),
          const SizedBox(height: 8),
          Text(
            context.l10n.contactHiddenByMember,
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
