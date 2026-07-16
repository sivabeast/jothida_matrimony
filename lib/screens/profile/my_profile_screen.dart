import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/network_photo.dart';

/// The signed-in member's own contact record (access-gated `contacts/{uid}`;
/// the owner can always read their own).
final myContactProvider = FutureProvider.autoDispose<ContactDetails?>((ref) async {
  final profile = ref.watch(myProfileProvider).valueOrNull;
  if (profile == null) return null;
  try {
    return await ref.read(firestoreServiceProvider).getContact(profile.userId);
  } catch (_) {
    return null; // gated / offline — the section simply shows no rows
  }
});

/// **My Profile** — the member's complete profile organised into the same
/// categories as profile creation, each with its own Edit action that opens
/// ONLY that section (never the full wizard from step 1). Saving a section
/// updates just that category; the live profile stream refreshes the page
/// instantly.
class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final contact = ref.watch(myContactProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: profileAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => _empty(context),
        data: (p) => p == null ? _empty(context) : _body(context, p, contact),
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text('No profile found. Create your profile first.'),
          ],
        ),
      );

  Widget _body(BuildContext context, ProfileModel p, ContactDetails? contact) {
    final pp = p.partnerPreferences;
    final h = p.horoscope;

    String s(Object? v) => (v == null) ? '' : v.toString().trim();
    String yn(bool v) => v ? 'Yes' : 'No';

    // Edit route for a wizard section (step index in the creation flow).
    void editStep(int step) =>
        context.push('/profile/${p.id}/edit-section/$step');

    final location = [p.city, p.district, p.state, p.country]
        .map(s)
        .where((v) => v.isNotEmpty)
        .join(', ');
    final prefLocation = [pp.city, pp.district, pp.state]
        .map(s)
        .where((v) => v.isNotEmpty)
        .join(', ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _header(p),
        const SizedBox(height: 6),

        _SectionCard(
          icon: Icons.badge_outlined,
          title: 'Basic Details',
          onEdit: () => editStep(0),
          rows: [
            ['Profile For', s(p.profileCreatedFor)],
            ['Name', s(p.fullName)],
            ['Gender', s(p.gender)],
            ['Age', p.age > 0 ? '${p.age} yrs' : ''],
            ['Height', s(p.height)],
            ['Weight', s(p.weight).isEmpty ? '' : '${s(p.weight)} kg'],
            ['Marital Status', s(p.maritalStatus)],
            ['Physical Status', s(p.physicalStatus)],
            if (p.childrenCount > 0) ...[
              ['Children', '${p.childrenCount}'],
              ['Children Living Status', s(p.childrenLivingStatus)],
            ],
          ],
        ),
        _SectionCard(
          icon: Icons.location_on_outlined,
          title: 'Location',
          onEdit: () => editStep(1),
          rows: [
            ['Location', location],
            ['Native Place', s(p.nativePlace)],
            ['Citizenship', s(p.citizenship)],
          ],
        ),
        _SectionCard(
          icon: Icons.work_outline,
          title: 'Career',
          onEdit: () => editStep(2),
          rows: [
            ['Education', s(p.education)],
            ['Occupation', s(p.occupation)],
            ['Course / Degree', s(p.courseDegree)],
            ['Employment Type', s(p.employmentType)],
            ['Annual Income', s(p.annualIncome)],
          ],
        ),
        _SectionCard(
          icon: Icons.diversity_3_outlined,
          title: 'Community',
          onEdit: () => editStep(3),
          rows: [
            ['Religion', s(p.religion)],
            ['Caste', s(p.caste)],
            ['Sub Caste', s(p.subCaste)],
            ['Mother Tongue', s(p.motherTongue)],
            ['Gothram', s(p.gothram)],
            ['Kuladeivam', s(p.kuladeivam)],
          ],
        ),
        _SectionCard(
          icon: Icons.auto_awesome_outlined,
          title: 'Horoscope',
          onEdit: () => editStep(4),
          rows: [
            ['Rasi', s(h.rasi)],
            ['Nakshatra', s(h.nakshatra)],
            ['Lagnam', s(h.lagnam)],
            ['Birth Time', s(h.birthTime)],
            ['Birth Place', s(h.birthPlace)],
          ],
        ),
        _SectionCard(
          icon: Icons.tune,
          title: 'Partner Preferences',
          onEdit: () => context.push('/partner-preferences'),
          rows: [
            ['Age', '${pp.minAge} – ${pp.maxAge} yrs'],
            ['Height', '${pp.minHeight} – ${pp.maxHeight}'],
            ['Caste', s(pp.caste)],
            ['Education', pp.education.join(', ')],
            ['Profession', pp.occupation.join(', ')],
            ['Location', prefLocation],
            ['Income', s(pp.income)],
            ['Marital Status', s(pp.maritalStatus)],
            ['Mother Tongue', s(pp.motherTongue)],
            ['Horoscope Match Required', yn(pp.horoscopeMatchRequired)],
          ],
        ),
        _SectionCard(
          icon: Icons.photo_camera_outlined,
          title: 'Photos',
          onEdit: () => editStep(6),
          rows: const [],
          child: p.photos.isEmpty
              ? Text('No photo added yet.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 96,
                    height: 116,
                    child: NetworkPhoto(
                        url: p.photos.first,
                        fit: BoxFit.cover,
                        fallbackIcon: Icons.person),
                  ),
                ),
        ),
        _SectionCard(
          icon: Icons.picture_as_pdf_outlined,
          title: 'Upload Horoscope',
          onEdit: () => editStep(7),
          rows: [
            [
              'Horoscope PDF',
              (h.horoscopePdfUrl ?? '').isNotEmpty ? 'Attached' : 'Not added',
            ],
          ],
        ),
        _SectionCard(
          icon: Icons.call_outlined,
          title: 'Contact',
          onEdit: () => editStep(8),
          rows: [
            ['Contact Person', s(contact?.contactPersonName)],
            ['Relationship', s(contact?.relationship)],
            ['Mobile', s(contact?.mobileNumber)],
            ['WhatsApp', s(contact?.whatsappNumber)],
          ],
        ),
      ],
    );
  }

  /// Top header — photo, name, quick facts.
  Widget _header(ProfileModel p) {
    final facts = [
      if (p.age > 0) '${p.age} yrs',
      if (p.height.trim().isNotEmpty) p.height,
      if ((p.caste ?? '').trim().isNotEmpty) p.caste!,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 64,
              height: 64,
              child: p.photos.isEmpty
                  ? Container(
                      color: Colors.white24,
                      child: const Icon(Icons.person,
                          color: Colors.white, size: 34))
                  : NetworkPhoto(
                      url: p.photos.first,
                      fit: BoxFit.cover,
                      fallbackIcon: Icons.person),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold)),
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(facts,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12.5)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One profile category: title + Edit action + label/value rows (empty values
/// are hidden). [child] renders custom content (e.g. the photo thumbnail).
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onEdit;
  final List<List<String>> rows;
  final Widget? child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.onEdit,
    required this.rows,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final visible = rows.where((r) => r[1].trim().isNotEmpty).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold)),
              ),
              // The category's own Edit action — opens ONLY this section.
              IconButton(
                tooltip: 'Edit $title',
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined,
                    size: 19, color: AppColors.primary),
              ),
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: 6),
            child!,
          ],
          if (visible.isEmpty && child == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Not added yet — tap ✎ to fill this in.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12.5)),
            )
          else
            ...visible.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(r[0],
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 13)),
                      ),
                      Expanded(
                        flex: 6,
                        child: Text(r[1],
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
