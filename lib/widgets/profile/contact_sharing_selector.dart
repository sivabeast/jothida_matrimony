import 'package:flutter/material.dart';

import '../../core/utils/l10n_ext.dart';

/// The two contact-sharing states, as stored in `profiles/{id}.contactPrivacy`.
class ContactSharing {
  ContactSharing._();

  /// Other members must send an interest, and it must be ACCEPTED, before chat
  /// or contact details open. The default.
  static const String private = 'private';

  /// Chat and contact details open without an interest. Field privacy still
  /// applies — "Hide Phone Number" keeps the numbers hidden either way.
  static const String public = 'public';
}

/// The Private / Public contact-sharing choice — the SAME two option cards the
/// profile wizard's Contact step has always shown, shared so Privacy Settings
/// presents the choice identically instead of as an on/off switch.
class ContactSharingSelector extends StatelessWidget {
  /// [ContactSharing.private] or [ContactSharing.public].
  final String value;
  final ValueChanged<String>? onChanged;

  const ContactSharingSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _option(
          context,
          option: ContactSharing.private,
          icon: Icons.lock_outline,
          title: l10n.contactPrivateTitle,
          subtitle: l10n.contactPrivateDesc,
        ),
        const SizedBox(height: 10),
        _option(
          context,
          option: ContactSharing.public,
          icon: Icons.public,
          title: l10n.contactPublicTitle,
          subtitle: l10n.contactPublicDesc,
        ),
      ],
    );
  }

  Widget _option(
    BuildContext context, {
    required String option,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = value == option;
    const maroon = Color(0xFF800020);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onChanged == null || selected ? null : () => onChanged!(option),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? maroon.withValues(alpha: 0.06) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? maroon : Colors.grey.shade300,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? maroon : Colors.grey[600], size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: selected ? maroon : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? maroon : Colors.grey[400],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
