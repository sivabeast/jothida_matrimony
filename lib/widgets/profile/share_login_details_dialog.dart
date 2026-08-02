import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/phone_utils.dart';
import '../../providers/app_update_provider.dart';

/// Play Store listing for the app, included in the hand-over message so the
/// member can install it straight from the WhatsApp text.
///
/// The ADMIN-configured store URL (App Update Settings) wins when one is set —
/// that is the single place the store link is maintained. This constant is only
/// the fallback, built from the real applicationId.
const String kDefaultPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.jothida.jothida_matrimony';

/// Shown to the admin right after a member's profile + login have been created.
///
/// It displays the credentials once, offers a copy action, and — the point of
/// the screen — a **Share Login Details** button that opens WhatsApp with a
/// ready-made, professional message addressed to the member's own number.
Future<void> showShareLoginDetailsDialog(
  BuildContext context, {
  required String memberName,
  required String mobile,
  required String email,
  required String password,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ShareLoginDetailsDialog(
      memberName: memberName,
      mobile: mobile,
      email: email,
      password: password,
    ),
  );
}

class _ShareLoginDetailsDialog extends ConsumerWidget {
  final String memberName;
  final String mobile;
  final String email;
  final String password;

  const _ShareLoginDetailsDialog({
    required this.memberName,
    required this.mobile,
    required this.email,
    required this.password,
  });

  /// The hand-over message. Greeting, both login identifiers (e-mail only when
  /// the member actually has one), the password, the Play Store link and short
  /// sign-in instructions.
  String _message(String storeUrl) {
    final name = memberName.trim().isEmpty ? 'there' : memberName.trim();
    final buffer = StringBuffer()
      ..writeln('Namaskaram $name,')
      ..writeln()
      ..writeln('Your Jothida Matrimony profile has been created. '
          'Here are your login details:')
      ..writeln()
      ..writeln('Mobile Number: +91 $mobile');
    if (email.trim().isNotEmpty) {
      buffer.writeln('Email: ${email.trim()}');
    }
    buffer
      ..writeln('Password: $password')
      ..writeln()
      ..writeln('How to sign in:')
      ..writeln('1. Install the app: $storeUrl')
      ..writeln('2. Open the app and tap Login.')
      ..writeln('3. Enter your mobile number'
          '${email.trim().isNotEmpty ? ' or email' : ''} and the password above.')
      ..writeln()
      ..writeln('Please change your password after your first login and keep '
          'these details private.')
      ..writeln()
      ..writeln('Warm regards,')
      ..write('Jothida Matrimony');
    return buffer.toString();
  }

  Future<void> _shareOnWhatsApp(BuildContext context, String storeUrl) async {
    final messenger = ScaffoldMessenger.of(context);
    // Addressed to the member's own number so the admin does not have to pick a
    // contact; wa.me requires digits only, with the country code.
    final uri = Uri.parse(
        '${whatsappUri(mobile)}?text=${Uri.encodeComponent(_message(storeUrl))}');
    try {
      final opened =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Could not open WhatsApp on this device.')));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not open WhatsApp: $e')));
    }
  }

  Future<void> _copy(BuildContext context, String storeUrl) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _message(storeUrl)));
    messenger.showSnackBar(
        const SnackBar(content: Text('Login details copied.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final configured =
        ref.watch(appUpdateConfigProvider).valueOrNull?.playStoreUrl.trim() ?? '';
    final storeUrl = configured.isEmpty ? kDefaultPlayStoreUrl : configured;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.verified_user_outlined,
              color: AppColors.success, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l10n.loginCredentials,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.profileCreatedForMember,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(l10n.mobileNumber, '+91 $mobile'),
                  if (email.trim().isNotEmpty) _row(l10n.email, email.trim()),
                  _row(l10n.password, password),
                ],
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton.icon(
          onPressed: () => _copy(context, storeUrl),
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy'),
          style: TextButton.styleFrom(foregroundColor: Colors.grey),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.done),
            ),
            const SizedBox(width: 4),
            ElevatedButton.icon(
              onPressed: () => _shareOnWhatsApp(context, storeUrl),
              icon: const Icon(Icons.chat, size: 18),
              label: Text(l10n.shareLoginDetails,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ),
            Expanded(
              flex: 6,
              child: SelectableText(
                value,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}
