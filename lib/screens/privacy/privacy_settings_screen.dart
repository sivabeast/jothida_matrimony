import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/firestore_write.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/profile/contact_sharing_selector.dart';

/// Privacy Settings — exactly FOUR switches (§15/§16):
/// Hide Phone Number · Hide Salary · Hide Horoscope Details · Hide Profile
/// Photo. The retired options (Hide Address, Hide Family Details, Hide
/// Additional Photos) are gone: no address is collected, family details are
/// not hideable and additional photos no longer exist.
///
/// All four default to HIDDEN and STAY hidden (§17): accepting an interest
/// never reveals them, and nothing in the app asks the member to unhide (§18).
/// Only this screen changes them.
///
/// The values live on the PUBLIC profile document so a viewer can honour them
/// without reading the owner's private account record; the legacy
/// `users/{uid}.privacySettings` copy is kept in sync for the admin panel and
/// the website.
class PrivacySettingsScreen extends ConsumerStatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  ConsumerState<PrivacySettingsScreen> createState() => _PrivacyState();
}

class _PrivacyState extends ConsumerState<PrivacySettingsScreen> {
  /// Local, unsaved edits. Null until the profile has loaded, so the switches
  /// never flash the wrong state.
  Map<String, bool>? _draft;
  bool _saving = false;

  Map<String, bool> _effective(ProfileModel? profile) =>
      _draft ?? profile?.privacySettings ?? ProfilePrivacy.defaults;

  void _set(String key, bool value, ProfileModel? profile) {
    final next = Map<String, bool>.from(_effective(profile));
    next[key] = value;
    setState(() => _draft = next);
  }

  Future<void> _save(ProfileModel profile) async {
    setState(() => _saving = true);
    final settings = _effective(profile);
    try {
      // Server-side enforcement: the service moves every newly-hidden value
      // into the member's private documents and blanks it on the documents
      // other members can read (and restores it when a switch is turned off).
      // The switches themselves are stored exactly as chosen.
      await commitWrite(ref
          .read(firestoreServiceProvider)
          .updateProfile(profile.id, {'privacySettings': settings}),
          timeout: const Duration(seconds: 20));
      // Chat threads cache each participant's photo for the other member to
      // read — a hidden photo must leave that cache too.
      final hidesPhoto =
          ProfilePrivacy.isHidden(settings, ProfilePrivacy.photo);
      if (hidesPhoto != profile.hidesPhoto) {
        try {
          await ref.read(chatServiceProvider).syncParticipantIdentity(
                uid: profile.userId,
                name: profile.fullName,
                photoUrl: hidesPhoto ? '' : (profile.profilePhotoUrl ?? ''),
              );
        } catch (_) {/* cache only — the profile is already saved */}
      }
      // Mirror onto the account document so the admin panel / website read the
      // same values. Best-effort: the profile document is the source of truth.
      final uid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
      if (uid != null) {
        try {
          await ref
              .read(firestoreServiceProvider)
              .updateUser(uid, {'privacySettings': settings});
        } catch (_) {/* non-fatal — profile doc already saved */}
      }
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _draft = null; // fall back to the freshly-saved profile values
      });
      _snack(context.l10n.privacySettingsSaved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(context.l10n.privacySettingsSaveFailed);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  /// Sets contact sharing to PUBLIC or PRIVATE on the user's profile doc.
  ///
  ///  * PUBLIC  — chat and contact details open without an interest.
  ///  * PRIVATE — an interest must be sent AND accepted first.
  ///
  /// Either way the field switches above still apply: a hidden phone number
  /// stays hidden. The security rules read this same value (through the
  /// `contacts/{uid}.profileId` pointer the service maintains), so the choice
  /// is enforced server-side, not just in the UI.
  Future<void> _setContactPrivacy(String profileId, bool public) async {
    final l10n = context.l10n;
    try {
      await commitWrite(ref.read(firestoreServiceProvider).updateProfile(
          profileId, {
        'contactPrivacy': public ? ContactSharing.public : ContactSharing.private
      }));
      if (mounted) {
        _snack(public ? l10n.contactPublicNote : l10n.contactPrivateNote);
      }
    } catch (_) {
      if (mounted) _snack(l10n.privacySettingsSaveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final settings = _effective(profile);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.privacySettings),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: (_saving || profile == null) ? null : () => _save(profile),
            child: Text(l10n.save,
                style: TextStyle(
                    color: (_saving || profile == null)
                        ? Colors.white54
                        : Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(l10n.privacyIntro,
                style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(height: 16),
          // ── The ONLY four privacy options (§16) ──────────────────────────
          _PrivacyTile(
            icon: Icons.phone_outlined,
            title: l10n.hidePhoneNumber,
            subtitle: l10n.hidePhoneNumberDesc,
            value: ProfilePrivacy.isHidden(settings, ProfilePrivacy.phone),
            onChanged: (v) => _set(ProfilePrivacy.phone, v, profile),
          ),
          _PrivacyTile(
            icon: Icons.payments_outlined,
            title: l10n.hideSalaryTitle,
            subtitle: l10n.hideSalaryDesc,
            value: ProfilePrivacy.isHidden(settings, ProfilePrivacy.salary),
            onChanged: (v) => _set(ProfilePrivacy.salary, v, profile),
          ),
          _PrivacyTile(
            icon: Icons.auto_awesome_outlined,
            title: l10n.hideHoroscopeTitle,
            subtitle: l10n.hideHoroscopeDesc,
            value: ProfilePrivacy.isHidden(settings, ProfilePrivacy.horoscope),
            onChanged: (v) => _set(ProfilePrivacy.horoscope, v, profile),
          ),
          _PrivacyTile(
            icon: Icons.photo_camera_outlined,
            title: l10n.hideProfilePhotoTitle,
            subtitle: l10n.hideProfilePhotoDesc,
            value: ProfilePrivacy.isHidden(settings, ProfilePrivacy.photo),
            onChanged: (v) => _set(ProfilePrivacy.photo, v, profile),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 18, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.privacyDefaultNote,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // ── Contact sharing — an explicit PUBLIC / PRIVATE choice, the same
          // two cards as the profile wizard's Contact step. Saved on tap.
          Card(
            margin: EdgeInsets.zero,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.contactSharingQuestion,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 10),
                  ContactSharingSelector(
                    value: (profile?.isContactPublic ?? false)
                        ? ContactSharing.public
                        : ContactSharing.private,
                    onChanged: profile == null
                        ? null
                        : (v) => _setContactPrivacy(
                            profile.id, v == ContactSharing.public),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PrivacyTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        secondary: Icon(icon, color: AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
