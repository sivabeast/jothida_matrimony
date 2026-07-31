import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/profile_model.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/service_providers.dart';

/// Live counts of a user's Horoscope Analysis + Appointment bookings.
final _userRequestsProvider = StreamProvider.autoDispose
    .family<List<AstrologerRequestModel>, String>((ref, uid) {
  return ref.read(astrologerServiceProvider).watchRequestsByUser(uid);
});

/// Admin → Users → View Details (§6).
///
/// Shows EVERY detail the member entered — account, basic details, location,
/// education & career, community, horoscope, family, lifestyle, partner
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
      ),
      body: user == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _card([
                  Center(
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      backgroundImage: _photo(profile, user).isNotEmpty
                          ? NetworkImage(_photo(profile, user))
                          : null,
                      child: _photo(profile, user).isEmpty
                          ? const Icon(Icons.person,
                              color: AppColors.primary, size: 40)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                        profile?.fullName ?? user.displayName ?? 'User',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  const Divider(height: 24),
                  _sectionTitle('Account'),
                  const SizedBox(height: 8),
                  _row('User ID', user.uid),
                  _row('Sign-in Email', user.email ?? '—'),
                  _row('Sign-in Provider', user.loginProvider ?? '—'),
                  _row('Role', user.role),
                  _row('Account Status',
                      user.isBlocked ? 'Suspended' : 'Active'),
                  _row('Profile Completed',
                      user.isProfileComplete ? 'Yes' : 'No'),
                  _row('Preferred Language', user.preferredLanguage ?? '—'),
                  _row('Registered', _date(user.createdAt)),
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
                else
                  ..._profileCards(profile, contact),
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
    final f = p.family;
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
        _row('Education', s(p.education)),
        _row('Course / Degree', s(p.courseDegree)),
        _row('College', s(p.collegeName)),
        _row('Occupation', s(p.occupation)),
        _row('Employment Type', s(p.employmentType)),
        _row('Company', s(p.companyName)),
        _row('Work Location', s(p.workLocation)),
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
        _row('Birth Time', s(h.birthTime)),
        _row('Birth Place', s(h.birthPlace)),
        _row('Chevvai Dosham', s(h.dosham)),
        _row('Rahu / Kethu Dosham', s(h.rahuKethuDosham)),
        _row('Kalasarpa Dosham', s(h.kalasarpaDosham)),
        _row('Dasa Balance', s(h.dasaBalance)),
        _row('Documents',
            '${h.horoscopeImages.length} image(s), ${h.allPdfUrls.length} PDF(s)'),
      ]),
      const SizedBox(height: 14),
      _card([
        _sectionTitle('Family'),
        const SizedBox(height: 8),
        _row('Father', s(f.fatherName)),
        _row("Father's Occupation", s(f.fatherOccupation)),
        _row('Mother', s(f.motherName)),
        _row("Mother's Occupation", s(f.motherOccupation)),
        _row('Brothers', '${f.brothersCount} (${f.marriedBrothers} married)'),
        _row('Sisters', '${f.sistersCount} (${f.marriedSisters} married)'),
        _row('Family Type', s(f.familyType)),
        _row('Family Status', s(f.familyStatus)),
        _row('About Family', s(f.aboutFamily)),
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
        _row('Horoscope Match Required', yn(pp.horoscopeMatchRequired)),
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
        _row('Profile Status', s(p.status)),
        _row('Active', yn(p.isActive)),
        _row('Verified', yn(p.isVerified)),
        _row('Featured', yn(p.isFeatured)),
        _row('Married', yn(p.isMarried)),
        _row('Test / Dummy Profile', yn(p.isDummy)),
        _row('Profile Created', _date(p.createdAt)),
        _row('Last Updated', _date(p.updatedAt)),
      ]),
    ];
  }

  String _photo(ProfileModel? profile, UserModel user) {
    final p = profile?.profilePhotoUrl ?? '';
    if (p.isNotEmpty) return p;
    return user.photoUrl ?? '';
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
