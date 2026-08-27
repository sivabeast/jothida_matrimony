import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/profile_status.dart';
import '../../models/aadhaar_details.dart';
import '../../models/astrologer_request_model.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/matrimony_photo.dart';
import '../../models/profile_model.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/export/download_saved_dialog.dart';
import '../../widgets/export/profile_form_export.dart';
import '../../core/services/horoscope_calculation_service.dart';
import '../../widgets/common/horoscope_documents_view.dart';
import '../../widgets/common/network_photo.dart';

/// Live counts of a user's Horoscope Analysis + Appointment bookings.
final _userRequestsProvider = StreamProvider.autoDispose
    .family<List<AstrologerRequestModel>, String>((ref, uid) {
  return ref.read(astrologerServiceProvider).watchRequestsByUser(uid);
});

/// The member's gated `aadhaar/{uid}` record, readable by admins only.
///
/// Aadhaar verification is an admin MODERATION action, not a profile field, so
/// it lives on this page next to Verify / Suspend / Delete rather than inside
/// the profile form (the profile form is the member's own wizard now — §13).
final _userAadhaarProvider =
    FutureProvider.autoDispose.family<AadhaarDetails?, String>((ref, uid) async {
  try {
    return await ref.read(firestoreServiceProvider).getAadhaar(uid);
  } catch (e) {
    debugPrint('[UserDetails] aadhaar read skipped: $e');
    return null;
  }
});

/// Admin → Users → View Details (§6).
///
/// Shows EVERY detail the member entered — account, basic details, location,
/// education & career, community, horoscope, lifestyle, partner
/// preferences, contact and privacy — plus their activity, with Edit
/// (suspend/activate) and Delete (account + data) actions.
///
/// The profile comes from [adminProfileByUserIdProvider], a Firestore SNAPSHOT
/// stream, so the moment the member edits anything in the app this page
/// re-renders with the new value — no refresh, no stale data.
class UserDetailsScreen extends ConsumerWidget {
  final String uid;
  const UserDetailsScreen({super.key, required this.uid});

  String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(allUsersProvider).valueOrNull ?? const [];
    UserModel? user;
    for (final u in users) {
      if (u.uid == uid) {
        user = u;
        break;
      }
    }
    // LIVE profile + contact — a member's edit lands here immediately (§6).
    final profile = ref.watch(adminProfileByUserIdProvider(uid)).valueOrNull;
    final contact = ref.watch(adminContactByUserIdProvider(uid)).valueOrNull;
    final requests =
        ref.watch(_userRequestsProvider(uid)).valueOrNull ?? const [];
    final analysisCount =
        requests.where((r) => r.type == AstrologerRequestType.matching).length;
    final apptCount = requests.where((r) => r.hasAppointment).length;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('User Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (user != null) _exportMenu(context, ref, user, profile, contact),
        ],
      ),
      body: user == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // §8 — a proper, large profile view: full-width photo with
                // the identifying details at a glance, instead of a small
                // avatar above a flat list of rows.
                _HeroProfileCard(
                    photoUrl: _photo(profile, user),
                    name: profile?.fullName ?? user.displayName ?? 'User',
                    profile: profile),
                const SizedBox(height: 14),
                _card([
                  _sectionTitle('Login Information'),
                  const SizedBox(height: 8),
                  _row('User ID', user.uid),
                  _row('Authentication Method',
                      _authMethod(user.loginProvider)),
                  _row(
                      'Registered Mobile',
                      (user.phone ?? '').trim().isEmpty
                          ? '—'
                          : user.phone!.trim()),
                  _row(
                      'Registered Email',
                      (user.email ?? '').trim().isEmpty
                          ? '—'
                          : user.email!.trim()),
                  _row('Role', user.role),
                  _row('Account Status',
                      user.isBlocked ? 'Suspended' : 'Active'),
                  _row('Profile Completed',
                      user.isProfileComplete ? 'Yes' : 'No'),
                  _row('Preferred Language', user.preferredLanguage ?? '—'),
                  _row('Created Date', _date(user.createdAt)),
                  _row('Last Login', _date(user.lastLoginAt)),
                ]),
                const SizedBox(height: 14),
                if (profile == null)
                  _card([
                    _sectionTitle('Profile'),
                    const SizedBox(height: 8),
                    const Text(
                        'This account has not created a matrimony profile yet.',
                        style: TextStyle(fontSize: 13)),
                  ])
                else ...[
                  ..._profileCards(profile, contact),
                  const SizedBox(height: 14),
                  // The verification BADGE decision (spec 13/14) - separate
                  // from the Aadhaar document check below it, and reversible.
                  _ProfileVerificationCard(profile: profile),
                  const SizedBox(height: 14),
                  _moderationActionsCard(context, ref, profile),
                  const SizedBox(height: 14),
                  _AadhaarVerificationCard(uid: uid, profileId: profile.id),
                ],
                const SizedBox(height: 14),
                _card([
                  _sectionTitle('Activity'),
                  const SizedBox(height: 8),
                  _row('Horoscope Analysis Requests', '$analysisCount'),
                  _row('Appointments Booked', '$apptCount'),
                  _row('Profile Views', '${profile?.viewCount ?? 0}'),
                  _row('Interests Received', '${profile?.interestCount ?? 0}'),
                  _row('Reports Against', '${profile?.reportCount ?? 0}'),
                ]),
                const SizedBox(height: 18),
                // Full profile editor — edits flow LIVE to the user app.
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        context.push('/admin/user/${user!.uid}/edit'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Profile'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _toggleStatus(context, ref, user!),
                        icon: Icon(user.isBlocked
                            ? Icons.lock_open_outlined
                            : Icons.block_outlined),
                        label: Text(user.isBlocked ? 'Activate' : 'Suspend'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _delete(context, ref, user!),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete User'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  /// EVERY field the member entered, grouped exactly like the profile wizard
  /// (§6). Empty values render as "—" rather than being hidden, so an admin can
  /// tell "not filled in" apart from "section missing".
  List<Widget> _profileCards(ProfileModel p, ContactDetails? contact) {
    final h = p.horoscope;
    final pp = p.partnerPreferences;
    final ls = p.lifestyle;
    String s(Object? v) {
      final t = (v ?? '').toString().trim();
      return t.isEmpty ? '—' : t;
    }

    String n(int v) => v > 0 ? '$v' : '—';
    String yn(bool v) => v ? 'Yes' : 'No';

    return [
      _card([
        _sectionTitle('Basic Details'),
        const SizedBox(height: 8),
        _row('Profile Created For', s(p.profileCreatedFor)),
        _row('Name', s(p.fullName)),
        // Both names are recorded on every profile (§14).
        _row('Name (Tamil)', s(p.fullNameTamil)),
        _row('Gender', s(p.gender)),
        _row('Date of Birth', _date(p.dateOfBirth)),
        _row('Age', n(p.age)),
        _row('Height', s(p.height)),
        _row('Weight', s(p.weight)),
        _row('Marital Status', s(p.maritalStatus)),
        _row('Physical Status', s(p.physicalStatus)),
        _row('Children', n(p.childrenCount)),
        _row('Children Living Status', s(p.childrenLivingStatus)),
        _row('Mother Tongue', s(p.motherTongue)),
        _row('About Me', s(p.aboutMe)),
      ]),
      const SizedBox(height: 14),
      _card([
        _sectionTitle('Location'),
        const SizedBox(height: 8),
        _row('Country', s(p.country)),
        _row('State', s(p.state)),
        _row('District', s(p.district)),
        _row('City', s(p.city)),
        _row('Native Place', s(p.nativePlace)),
        _row('Citizenship', s(p.citizenship)),
      ]),
      const SizedBox(height: 14),
      _card([
        _sectionTitle('Education & Career'),
        const SizedBox(height: 8),
        _row('Education Level', s(p.effectiveEducationLevel)),
        _row('Course / Degree', s(p.education)),
        _row('All Qualifications', s(p.allDegrees.join(', '))),
        // Occupation is free text now — the Employment Status and Profession
        // Type fields were removed from the profile structure (§9), so they
        // are no longer shown here either.
        _row('Occupation', s(p.occupation)),
        _row('Annual Income', s(p.annualIncome)),
      ]),
      const SizedBox(height: 14),
      _card([
        _sectionTitle('Community'),
        const SizedBox(height: 8),
        _row('Religion', s(p.religion)),
        _row('Caste', s(p.caste)),
        _row('Sub Caste', s(p.subCaste)),
        _row('Gothram', s(p.gothram)),
        _row('Kuladeivam', s(p.kuladeivam)),
      ]),
      const SizedBox(height: 14),
      _card([
        _sectionTitle('Horoscope'),
        const SizedBox(height: 8),
        _row('Rasi', s(h.rasi)),
        _row('Nakshatra', s(h.nakshatra)),
        _row('Lagnam', s(h.lagnam)),
        _row('Birth Time', s(HoroscopeCalculationService.formatBirthTimeForDisplay(h.birthTime))),
        _row('Birth Place', s(h.birthPlace)),
        _row('Chevvai Dosham', s(h.dosham)),
        _row('Rahu / Kethu Dosham', s(h.rahuKethuDosham)),
        _row('Kalasarpa Dosham', s(h.kalasarpaDosham)),
        _row('Dasa Balance', s(h.dasaBalance)),
        const SizedBox(height: 6),
        // The actual uploaded horoscope images / PDFs, not just a count —
        // an admin needs to SEE them (§8). Same viewer the member and the
        // astrologer use, so behaviour is identical everywhere.
        HoroscopeDocumentsView(
          imageUrls: h.horoscopeImages,
          pdfUrls: h.allPdfUrls,
          title: 'Horoscope Documents',
        ),
      ]),
      const SizedBox(height: 14),
      _card([
        _sectionTitle('Lifestyle'),
        const SizedBox(height: 8),
        _row('Eating Habit', s(ls.eatingHabit)),
        _row('Smoking', s(ls.smokingHabit)),
        _row('Drinking', s(ls.drinkingHabit)),
        _row('Hobbies', s(ls.hobbies)),
        _row('Interests', s(ls.interests)),
        _row('Languages Known', s(ls.languagesKnown.join(', '))),
      ]),
      const SizedBox(height: 14),
      _card([
        _sectionTitle('Partner Preferences'),
        const SizedBox(height: 8),
        _row('Age Range', '${pp.minAge} – ${pp.maxAge}'),
        _row('Age Chosen By Member', yn(pp.agePreferenceSet)),
        _row('Height Range', '${pp.minHeight} – ${pp.maxHeight}'),
        _row('Education', s(pp.education.join(', '))),
        _row('Occupation', s(pp.occupation.join(', '))),
        _row('Religion', s(pp.religion)),
        _row('Caste', s(pp.caste)),
        _row('Sub Caste', s(pp.subCaste)),
        _row('Marital Status', s(pp.maritalStatus)),
        _row('Mother Tongue', s(pp.motherTongue)),
        _row('Physical Status', s(pp.physicalStatus)),
        _row('Income', s(pp.income)),
        _row('Location', s([pp.city, pp.district, pp.state, pp.country]
            .where((v) => (v ?? '').trim().isNotEmpty)
            .join(', '))),
        _row('Rasi', s(pp.rasi)),
        _row('Nakshatra', s(pp.nakshatra)),
        _row('Chevvai Dosham', s(pp.chevvaiDosham)),
      ]),
      const SizedBox(height: 14),
      _card([
        _sectionTitle('Contact'),
        const SizedBox(height: 8),
        _row('Contact Person', s(contact?.contactPersonName)),
        _row('Relationship', s(contact?.relationship)),
        _row('Mobile', s(contact?.mobileNumber)),
        _row('WhatsApp', s(contact?.whatsappNumber)),
        _row('Email', s(contact?.email)),
        _row('Contact Sharing', p.isContactPublic ? 'Public' : 'Private'),
      ]),
      const SizedBox(height: 14),
      _card([
        _sectionTitle('Privacy (member controlled)'),
        const SizedBox(height: 8),
        _row('Hide Phone Number', yn(p.hidesPhone)),
        _row('Hide Salary', yn(p.hidesSalary)),
        _row('Hide Horoscope Details', yn(p.hidesHoroscope)),
        _row('Hide Profile Photo', yn(p.hidesPhoto)),
      ]),
      const SizedBox(height: 14),
      _card([
        _sectionTitle('Moderation'),
        const SizedBox(height: 8),
        _row('Verification Status', profileStatusLabel(p.status)),
        _row('Active', yn(p.isActive)),
        _row('Aadhaar Verified', yn(p.isVerified)),
        _row('Featured', yn(p.isFeatured)),
        _row('Married', yn(p.isMarried)),
        _row('Test / Dummy Profile', yn(p.isDummy)),
        _row('Profile Created', _date(p.createdAt)),
        _row('Last Updated', _date(p.updatedAt)),
      ]),
    ];
  }

  /// AppBar export action (§13). With no profile there is nothing to export,
  /// so the button explains that instead of opening the format menu.
  Widget _exportMenu(BuildContext context, WidgetRef ref, UserModel user,
      ProfileModel? profile, ContactDetails? contact) {
    if (profile == null) {
      return IconButton(
        icon: const Icon(Icons.download_outlined),
        tooltip: 'Export profile',
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('This account has not created a matrimony '
                  'profile yet, so there is nothing to export.')),
        ),
      );
    }
    return PopupMenuButton<String>(
      icon: const Icon(Icons.download_outlined),
      tooltip: 'Export profile',
      onSelected: (v) =>
          _export(context, ref, user, profile, contact, asPdf: v == 'pdf'),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'pdf',
          child: Row(children: [
            Icon(Icons.picture_as_pdf_outlined,
                size: 20, color: AppColors.primary),
            SizedBox(width: 10),
            Text('Export as PDF'),
          ]),
        ),
        PopupMenuItem(
          value: 'images',
          child: Row(children: [
            Icon(Icons.image_outlined, size: 20, color: AppColors.primary),
            SizedBox(width: 10),
            Text('Export as Images'),
          ]),
        ),
      ],
    );
  }

  /// Runs the branded A4 capture (visible "preparing" screen) and hands the
  /// result to the system share sheet as a PDF or as PNG page images. The
  /// admin download is the complete record — nothing redacted — laid out as
  /// the printed Jothida Matrimony registration form.
  Future<void> _export(BuildContext context, WidgetRef ref, UserModel user,
      ProfileModel profile, ContactDetails? contact,
      {required bool asPdf}) async {
    final messenger = ScaffoldMessenger.of(context);
    // Stamped into every page footer: who generated this export.
    final adminEmail =
        ref.read(currentUserProvider).valueOrNull?.email?.trim() ?? '';
    final options = ProfileFormExportOptions.admin(adminEmail: adminEmail);
    final base = profileExportBaseName(profile);
    final l10n = context.l10n;
    // Written straight to the device (Downloads / Pictures) — no share sheet.
    final result = asPdf
        ? await exportProfileFormPdf(context,
            profile: profile,
            user: user,
            contact: contact,
            options: options,
            fileName: '$base.pdf')
        : await exportProfileFormImages(context,
            profile: profile,
            user: user,
            contact: contact,
            options: options,
            baseName: base);
    if (result == null) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.downloadProfileFailed)));
      return;
    }
    if (context.mounted) {
      await showDownloadSavedDialog(context, result: result);
    }
  }

  /// The member's MATRIMONY photo. A Google account picture is never shown
  /// here — the admin view sees exactly the image the member uploaded, or the
  /// placeholder when they have not uploaded one (§6/§17).
  String _photo(ProfileModel? profile, UserModel user) =>
      matrimonyPhotoUrl(profile?.profilePhotoUrl, user.photoUrl);

  /// Human-readable login method (§ Login Information).
  String _authMethod(String? provider) {
    final p = (provider ?? '').trim().toLowerCase();
    if (p.isEmpty) return '—';
    if (p == 'google.com' || p == 'google') return 'Google';
    if (p == 'password') return 'Phone/Email + Password';
    return provider!.trim();
  }

  /// Status-aware verification actions — Verify / Reject a pending profile,
  /// re-verify a rejected one; verified profiles point the admin at the
  /// account-level Suspend/Activate button instead.
  Widget _moderationActionsCard(
      BuildContext context, WidgetRef ref, ProfileModel p) {
    final status = p.status.trim().toLowerCase();
    return _card([
      _sectionTitle('Profile Verification'),
      const SizedBox(height: 12),
      if (status == 'pending')
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _approveProfile(context, ref, p),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Verify'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _rejectProfile(context, ref, p),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    minimumSize: const Size.fromHeight(46)),
              ),
            ),
          ],
        )
      else if (status == 'rejected')
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _approveProfile(context, ref, p),
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Verify'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46)),
          ),
        )
      else if (status == 'approved')
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 18, color: AppColors.info),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This profile is verified. To take it off the platform, use '
                'the Suspend button below — Activate restores access.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
              ),
            ),
          ],
        )
      else
        Text('No verification action available for status '
            '"${profileStatusLabel(p.status)}".',
            style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
    ]);
  }

  Future<void> _approveProfile(
      BuildContext context, WidgetRef ref, ProfileModel p) async {
    final messenger = ScaffoldMessenger.of(context);
    // Pass BOTH ids so the member receives the "Profile Verified" push.
    await ref
        .read(adminActionsProvider.notifier)
        .approveProfile(p.id, userId: p.userId);
    final st = ref.read(adminActionsProvider);
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not verify profile. Please try again.'
          : 'Profile verified — the member has been notified.'),
      backgroundColor: st.hasError ? AppColors.error : AppColors.success,
    ));
  }

  Future<void> _rejectProfile(
      BuildContext context, WidgetRef ref, ProfileModel p) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Reject Profile'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Reason for rejection (required)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, controller.text.trim()),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white),
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );
    if (reason == null || reason.isEmpty) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(adminActionsProvider.notifier)
        .rejectProfile(p.id, reason, userId: p.userId);
    final st = ref.read(adminActionsProvider);
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not reject profile. Please try again.'
          : 'Profile rejected.'),
      backgroundColor: st.hasError ? AppColors.error : AppColors.warning,
    ));
  }

  Future<void> _toggleStatus(
      BuildContext context, WidgetRef ref, UserModel user) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(adminActionsProvider.notifier);
    if (user.isBlocked) {
      await notifier.unblockUser(user.uid);
    } else {
      await notifier.blockUser(user.uid);
    }
    ref.invalidate(allUsersProvider);
    messenger.showSnackBar(SnackBar(
        content: Text(user.isBlocked ? 'User activated.' : 'User suspended.')));
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, UserModel user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete user?'),
        content: const Text(
            'This permanently removes the user account and their profile data. '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    await ref.read(adminActionsProvider.notifier).deleteUser(user.uid);
    final st = ref.read(adminActionsProvider);
    ref.invalidate(allUsersProvider);
    messenger.showSnackBar(SnackBar(
        content: Text(st.hasError ? 'Could not delete user.' : 'User deleted.')));
    if (!st.hasError) router.pop();
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontSize: 15,
          fontFamily: 'Poppins',
          fontWeight: FontWeight.bold,
          color: AppColors.primary));

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 150,
                child: Text(k,
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey[700]))),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}


/// §8 — the large profile header on the admin's user page: a full-width photo
/// with the member's name, age and location over it, so an admin opening a
/// profile sees WHO it is immediately rather than reading it out of a table.
class _HeroProfileCard extends StatelessWidget {
  final String photoUrl;
  final String name;
  final ProfileModel? profile;

  const _HeroProfileCard({
    required this.photoUrl,
    required this.name,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final location = p == null
        ? ''
        : [p.city, p.district, p.state]
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .join(', ');
    final line2 = [
      if (p != null && p.age > 0) '${p.age} yrs',
      if (p != null && p.education.trim().isNotEmpty) p.education.trim(),
      if (p != null && p.occupation.trim().isNotEmpty) p.occupation.trim(),
    ].join('  ·  ');

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: NetworkPhoto(url: photoUrl, fallbackIconSize: 72),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 20,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold)),
                if (line2.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(line2,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                ],
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 15, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(location,
                            maxLines: 2,
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[700])),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// Admin -> **Profile Verification** (spec §13/§14).
///
/// The single control behind the green tick members see beside a name. Two
/// things make it deliberately different from every other admin toggle:
///
///  * It is REVERSIBLE. "Revoke Verification" is a first-class action, not an
///    undo — an admin may verify and revoke as often as the facts require.
///  * Revoking touches NOTHING else. The account is not deleted, disabled,
///    blocked or hidden; the profile stays exactly where it was and only the
///    badge disappears. Because that is easy to mistake for a heavier action,
///    the revoke path asks for confirmation first.
class _ProfileVerificationCard extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _ProfileVerificationCard({required this.profile});

  @override
  ConsumerState<_ProfileVerificationCard> createState() =>
      _ProfileVerificationCardState();
}

class _ProfileVerificationCardState
    extends ConsumerState<_ProfileVerificationCard> {
  bool _busy = false;

  /// Mirrors the write locally so the card flips immediately, before the
  /// profile stream round-trips.
  bool? _local;

  bool get _verified => _local ?? widget.profile.isProfileVerified;

  Future<void> _set(bool verified) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);

    // Revoking is the destructive-looking direction — confirm it, and say
    // plainly what does NOT happen, so nobody avoids the action out of fear.
    if (!verified) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Revoke verification?'),
          content: const Text(
              'The green Verified badge will be removed from this profile '
              'immediately.\n\nThe account is NOT deleted or disabled — the '
              'member keeps their profile and can be verified again at any '
              'time.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Revoke'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(firestoreServiceProvider).setProfileVerified(
            profileId: widget.profile.id,
            verified: verified,
            adminUid:
                ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ?? '',
          );
      if (!mounted) return;
      setState(() => _local = verified);
      messenger.showSnackBar(SnackBar(
        backgroundColor: verified ? AppColors.success : null,
        content: Text(verified
            ? 'Profile verified — the green badge is now shown.'
            : 'Verification revoked. The account is unchanged.'),
      ));
    } catch (e) {
      debugPrint('[UserDetails] profile verification failed: $e');
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not update the verification. Please try again.'),
          backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verified = _verified;
    final at = widget.profile.profileVerifiedAt;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(
              child: Text('Profile Verification',
                  style: TextStyle(
                      fontSize: 15,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (verified ? AppColors.success : Colors.grey)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(verified ? Icons.verified : Icons.remove_circle_outline,
                    size: 13,
                    color: verified ? AppColors.success : Colors.grey),
                const SizedBox(width: 4),
                Text(verified ? 'VERIFIED' : 'NOT VERIFIED',
                    style: TextStyle(
                        color: verified ? AppColors.success : Colors.grey[700],
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold)),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
              verified
                  ? 'This member shows the green Verified tick beside their name.'
                  : 'This member has no Verified badge.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
          if (at != null) ...[
            const SizedBox(height: 4),
            Text('Last changed ${_stamp(at)}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey[500])),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _busy
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4)),
                    ),
                  )
                : verified
                    ? OutlinedButton.icon(
                        onPressed: () => _set(false),
                        icon: const Icon(Icons.gpp_bad_outlined, size: 18),
                        label: const Text('Revoke Verification'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          minimumSize: const Size.fromHeight(44),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: () => _set(true),
                        icon: const Icon(Icons.verified_outlined, size: 18),
                        label: const Text('Verify Profile'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  static String _stamp(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.year}';
}

/// Admin Aadhaar review: the submitted number (masked) plus the front/back
/// images, and the switch that marks the member verified — which is what
/// stamps the public "Verified" badge on their profile.
///
/// This used to sit inside the admin-only profile editor. That editor is gone
/// (admins now open the member's own profile wizard, §13/§15), so the action
/// moved here, where the rest of the admin-only moderation lives.
class _AadhaarVerificationCard extends ConsumerWidget {
  final String uid;
  final String profileId;
  const _AadhaarVerificationCard(
      {required this.uid, required this.profileId});

  Future<void> _setVerified(
      BuildContext context, WidgetRef ref, bool verified) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(firestoreServiceProvider).setAadhaarVerified(
          userId: uid, profileId: profileId, verified: verified);
      ref.invalidate(_userAadhaarProvider(uid));
      messenger.showSnackBar(SnackBar(
          content: Text(verified
              ? 'Aadhaar verified — the profile now shows the Verified badge.'
              : 'Aadhaar verification removed.')));
    } catch (e) {
      debugPrint('[UserDetails] verification update failed: $e');
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not update the verification. Please try again.'),
          backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(_userAadhaarProvider(uid)).valueOrNull;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Aadhaar Verification',
              style: TextStyle(
                  fontSize: 15,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          const SizedBox(height: 12),
          if (a == null || !a.isSubmitted)
            Text('The user has not submitted Aadhaar details yet.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13))
          else ...[
            Row(children: [
              Expanded(
                child: Text('Aadhaar Number: ${a.masked}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (a.verified ? AppColors.success : AppColors.warning)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(a.verified ? 'VERIFIED' : 'PENDING',
                    style: TextStyle(
                        color:
                            a.verified ? AppColors.success : AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _image('Front', a.frontUrl)),
              const SizedBox(width: 10),
              Expanded(child: _image('Back', a.backUrl)),
            ]),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aadhaar Verified',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text(
                  'Verifying also shows the "Verified" badge on the profile.',
                  style: TextStyle(fontSize: 12)),
              value: a.verified,
              activeThumbColor: AppColors.success,
              onChanged: (v) => _setVerified(context, ref, v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _image(String label, String url) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Container(
            height: 110,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: url.isEmpty
                ? const Center(
                    child: Icon(Icons.image_not_supported_outlined,
                        color: Colors.grey))
                : NetworkPhoto(url: url, fit: BoxFit.cover),
          ),
        ],
      );
}
