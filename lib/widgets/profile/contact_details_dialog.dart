import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/utils/value_l10n.dart';
import '../../models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/interest_provider.dart';
import '../../providers/service_providers.dart';

/// The Contact Details popup (spec §2). The View Profile page never renders
/// contact fields inline — this dialog is the ONLY place they appear, and it
/// enforces the three access rules itself:
///   1. mutual interest accepted            → show contact details;
///   2. owner set Contact Visibility=Public → show even without acceptance;
///   3. otherwise                           → a privacy message, nothing else.
///
/// The data is ALWAYS a fresh read of `contacts/{userId}` — the record the
/// member (or an admin) last saved — never the copy embedded in the profile
/// doc and never a session-cached provider value, so an admin-side edit shows
/// up on the very next open (spec: no old/cached data).
Future<void> showContactDetailsDialog(
  BuildContext context, {
  required ProfileModel profile,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ContactDetailsDialog(profile: profile),
  );
}

class _ContactDetailsDialog extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _ContactDetailsDialog({required this.profile});

  @override
  ConsumerState<_ContactDetailsDialog> createState() =>
      _ContactDetailsDialogState();
}

class _ContactDetailsDialogState extends ConsumerState<_ContactDetailsDialog> {
  /// A new future per open (and per retry) — never a cached value.
  late Future<ContactDetails?> _fetch;

  @override
  void initState() {
    super.initState();
    _fetch = _load();
  }

  /// Fresh read of `contacts/{userId}`.
  ///
  /// A denied read on a MATCHED pair means the `connections/{pair}` doc the
  /// rule checks was never written (the accept-time write is best-effort and
  /// silently skips when rules are mid-deploy). Backfill it from the accepted
  /// interest and retry once, so a real match is never permanently locked out.
  Future<ContactDetails?> _load() async {
    final repo = ref.read(profileRepositoryProvider);
    try {
      return await repo.getContact(widget.profile.userId);
    } catch (e) {
      if (!'$e'.contains('permission-denied')) rethrow;
      final accepted =
          ref.read(acceptedInterestForProfileProvider(widget.profile.id));
      if (accepted == null) rethrow;
      await ref
          .read(interestNotifierProvider.notifier)
          .ensureConnection(accepted);
      return repo.getContact(widget.profile.userId);
    }
  }

  bool get _isOwner {
    final uid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
    return uid != null && uid == widget.profile.userId;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profile = widget.profile;
    final accepted =
        ref.watch(interestStatusForProfileProvider(profile.id)) ==
            InterestUiStatus.accepted;

    // Privacy decision — evaluated BEFORE any data is rendered.
    final hiddenByOwner = !_isOwner && profile.hidesPhone;
    final allowed = _isOwner || accepted || profile.isContactPublic;

    Widget body;
    if (hiddenByOwner) {
      body = _privacyMessage(l10n.contactHiddenByOwnerMessage);
    } else if (!allowed) {
      body = _privacyMessage(l10n.contactPrivateMessage);
    } else {
      body = FutureBuilder<ContactDetails?>(
        future: _fetch,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
            );
          }
          if (snap.hasError) {
            // A denied read means the connection unlock hasn't propagated —
            // privacy message, not a technical error (spec: friendly only).
            final msg = '${snap.error}';
            if (msg.contains('permission-denied')) {
              return _privacyMessage(l10n.contactPrivateMessage);
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _privacyMessage(l10n.couldNotLoadContact,
                    icon: Icons.cloud_off_rounded),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () => setState(() => _fetch = _load()),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l10n.retry),
                ),
              ],
            );
          }
          final contact = snap.data;
          // "Not provided" only when the record carries NOTHING — a member who
          // saved an email or a WhatsApp number but no mobile still has
          // contact details worth showing.
          final hasAny = contact != null &&
              [
                contact.contactPersonName,
                contact.mobileNumber,
                contact.whatsappNumber ?? '',
                contact.email,
              ].any((v) => v.trim().isNotEmpty);
          if (!hasAny) {
            return _privacyMessage(l10n.contactNotProvided,
                icon: Icons.info_outline);
          }
          return _contactBody(contact);
        },
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.contact_phone_outlined,
                      size: 28, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(l10n.contactDetails,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 17,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(profile.displayName(context.isTamil),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
                const SizedBox(height: 14),
                body,
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
                  child: Text(MaterialLocalizations.of(context).closeButtonLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Rule-3 / hidden / empty presentation: one soft card, no hints of data.
  Widget _privacyMessage(String message, {IconData icon = Icons.lock_outline}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: Colors.grey[500]),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.45, color: Colors.grey[700])),
        ],
      ),
    );
  }

  Widget _contactBody(ContactDetails contact) {
    final l10n = context.l10n;
    final mobile = contact.mobileNumber.trim();
    final whatsapp = (contact.whatsappNumber ?? '').trim();
    // Filter empty fields FIRST so dividers only sit between visible rows.
    final rows = <(IconData, String, String)>[
      (Icons.person_outline, l10n.contactPersonName, contact.contactPersonName),
      (
        Icons.family_restroom,
        l10n.relationship,
        context.localizeValue(contact.relationship)
      ),
      (Icons.call_outlined, l10n.mobileNumber, mobile),
      (Icons.chat_outlined, l10n.whatsappNumber, whatsapp),
      (Icons.email_outlined, l10n.email, contact.email),
    ].where((r) => r.$3.trim().isNotEmpty).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                _row(rows[i].$1, rows[i].$2, rows[i].$3,
                    last: i == rows.length - 1),
            ],
          ),
        ),
        // Each action appears only when its number exists, so no button ever
        // dials or messages an empty number.
        if (mobile.isNotEmpty || whatsapp.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              if (mobile.isNotEmpty)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _launch(phoneCallUri(mobile)),
                    icon: const Icon(Icons.call, size: 18),
                    label: Text(l10n.call),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              if (mobile.isNotEmpty && whatsapp.isNotEmpty)
                const SizedBox(width: 10),
              if (whatsapp.isNotEmpty)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _launch(whatsappUri(whatsapp)),
                    icon: const Icon(Icons.chat, size: 18),
                    label: Text(l10n.whatsapp),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _row(IconData icon, String label, String value, {bool last = false}) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12, height: 1.25, color: Colors.grey[600])),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Text(value,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                        fontSize: 13, height: 1.3, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        if (!last) Divider(height: 1, color: Colors.grey[200]),
      ],
    );
  }

  Future<void> _launch(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
