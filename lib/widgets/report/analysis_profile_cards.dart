import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_provider.dart';
import '../common/fullscreen_photo_viewer.dart';
import '../common/horoscope_documents_view.dart';
import '../common/network_photo.dart';

/// The REVIEW block an astrologer / admin sees ABOVE the compatibility report
/// form: one premium card per side (Groom, then Bride) carrying that member's
/// complete submitted profile — photo, name, age, horoscope, family,
/// education, job, location, personality and every uploaded horoscope
/// document.
///
/// Nothing here is editable and nothing is fetched that the report form did
/// not already need: it reads the same `profiles/{id}` documents the request
/// points at. For an EXTERNAL report (the second person is not a member) the
/// manually-entered details on the request are shown instead, so the reviewer
/// still sees both sides before deciding.
class AnalysisProfileCards extends ConsumerWidget {
  final AstrologerRequestModel request;

  const AnalysisProfileCards({super.key, required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (request.isExternalReport) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeading(context),
          const SizedBox(height: 10),
          _ExternalPartyCard(
            title: 'Requester',
            icon: Icons.person_outline,
            details: request.externalRequester,
          ),
          const SizedBox(height: 12),
          _ExternalPartyCard(
            title: 'Other Party',
            icon: Icons.person_outline,
            details: request.externalOther,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeading(context),
        const SizedBox(height: 10),
        _ProfileReviewCard(
          title: 'மணமகன் (Groom)',
          icon: Icons.male,
          accent: AppColors.info,
          profileId: request.groomProfileId,
          fallbackName: request.groomName ?? '',
        ),
        const SizedBox(height: 12),
        _ProfileReviewCard(
          title: 'மணமகள் (Bride)',
          icon: Icons.female,
          accent: const Color(0xFFC2185B),
          profileId: request.brideProfileId,
          fallbackName: request.brideName ?? '',
        ),
      ],
    );
  }

  Widget _sectionHeading(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            const Icon(Icons.fact_check_outlined,
                size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Review Both Profiles',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                  const SizedBox(height: 2),
                  Text(
                      'Full submitted details for both sides. Fill in the '
                      'report below once you have reviewed them.',
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: Colors.grey[700])),
                ],
              ),
            ),
          ],
        ),
      );
}

/// One member's complete profile, in a collapsible premium card (expanded by
/// default so the reviewer sees everything without a tap).
class _ProfileReviewCard extends ConsumerWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final String? profileId;
  final String fallbackName;

  const _ProfileReviewCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.profileId,
    required this.fallbackName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = (profileId ?? '').trim();
    final async = id.isEmpty ? null : ref.watch(profileByIdProvider(id));
    final profile = async?.valueOrNull;

    return _card(
      accent: accent,
      header: _header(profile),
      child: async == null
          ? _note('No profile is linked to this side of the request.')
          : async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => _note(
                  'Could not load this profile. Check your connection and '
                  'reopen the request.'),
              data: (p) => p == null
                  ? _note('This profile is no longer available.')
                  : _details(context, p),
            ),
    );
  }

  Widget _header(ProfileModel? p) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                if ((p?.fullName ?? fallbackName).trim().isNotEmpty)
                  Text(
                    (p?.fullName.trim().isNotEmpty ?? false)
                        ? p!.fullName
                        : fallbackName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: Colors.white70),
                  ),
              ],
            ),
          ),
        ],
      );

  Widget _details(BuildContext context, ProfileModel p) {
    final h = p.horoscope;
    final f = p.family;
    final l = p.lifestyle;
    final location = [p.city, p.district, p.state, p.country]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Identity strip: photo + headline facts ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: (p.profilePhotoUrl ?? '').isEmpty
                  ? null
                  : () =>
                      FullScreenPhotoViewer.open(context, p.profilePhotoUrl!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: NetworkPhoto(
                    url: p.profilePhotoUrl ?? '', width: 84, height: 84),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.fullName,
                      style: const TextStyle(
                          fontSize: 15.5,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700)),
                  if (p.fullNameTamil.trim().isNotEmpty &&
                      p.fullNameTamil.trim() != p.fullName.trim())
                    Text(p.fullNameTamil,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700])),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (p.age > 0) _chip('${p.age} yrs'),
                      if (p.gender.trim().isNotEmpty) _chip(p.gender),
                      if (p.height.trim().isNotEmpty) _chip(p.height),
                      if (p.maritalStatus.trim().isNotEmpty)
                        _chip(p.maritalStatus),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // ── Every submitted section ──
        _group('Basic Details', [
          ('Date of Birth', _date(p.dateOfBirth)),
          ('Age', p.age > 0 ? '${p.age}' : ''),
          ('Height', p.height),
          ('Weight', p.weight),
          ('Marital Status', p.maritalStatus),
          ('Children', p.childrenCount > 0 ? '${p.childrenCount}' : ''),
          ('Physical Status', p.physicalStatus),
          ('Mother Tongue', p.motherTongue),
          ('Profile Created For', p.profileCreatedFor),
        ]),
        _group('Location', [
          ('City', p.city),
          ('District', p.district),
          ('State', p.state),
          ('Country', p.country),
          ('Native Place', p.nativePlace ?? ''),
          ('Citizenship', p.citizenship ?? ''),
          ('Full Location', location),
        ]),
        _group('Religious Details', [
          ('Religion', p.religion),
          ('Caste', p.caste ?? ''),
          ('Sub Caste', p.subCaste ?? ''),
          ('Gothram', p.gothram),
          ('Kuladeivam', p.kuladeivam),
        ]),
        _group('Education & Job', [
          ('Education Level', p.educationLevel),
          ('Education', p.education),
          ('Course / Degree', p.courseDegree ?? ''),
          ('College', p.collegeName ?? ''),
          ('Employment Status', p.employmentStatus),
          ('Employment Type', p.employmentType),
          ('Occupation', p.occupation),
          ('Company', p.companyName ?? ''),
          ('Work Location', p.workLocation ?? ''),
          ('Annual Income', p.annualIncome),
        ]),
        _group('Horoscope', [
          ('Rasi', h.rasi),
          ('Nakshatra', h.nakshatra),
          ('Lagnam', h.lagnam),
          ('Birth Place', h.birthPlace),
          ('Birth Time', h.birthTime),
          ('Moon Sign', h.moonSign),
          ('Sun Sign', h.sunSign),
          ('Dasa Balance', h.dasaBalance),
          ('Yogam', h.yogam),
          ('Karanam', h.karanam),
          ('Chevvai Dosham', h.dosham),
          ('Rahu / Kethu Dosham', h.rahuKethuDosham),
          ('Kalasarpa Dosham', h.kalasarpaDosham),
        ]),
        _group('Family Details', [
          ('Father', f.fatherName),
          ('Father Occupation', f.fatherOccupation),
          ('Mother', f.motherName),
          ('Mother Occupation', f.motherOccupation),
          ('Brothers', f.brothersCount > 0 ? '${f.brothersCount}' : ''),
          ('Married Brothers',
              f.marriedBrothers > 0 ? '${f.marriedBrothers}' : ''),
          ('Sisters', f.sistersCount > 0 ? '${f.sistersCount}' : ''),
          ('Married Sisters',
              f.marriedSisters > 0 ? '${f.marriedSisters}' : ''),
          ('Family Type', f.familyType),
          ('Family Status', f.familyStatus),
        ]),
        _group('Personality & Lifestyle', [
          ('Eating Habit', l.eatingHabit),
          ('Smoking Habit', l.smokingHabit),
          ('Drinking Habit', l.drinkingHabit),
          ('Hobbies', l.hobbies),
          ('Interests', l.interests),
          ('Languages Known', l.languagesKnown.join(', ')),
        ]),
        if (p.about.trim().isNotEmpty) _paragraph('About', p.about),
        if (f.aboutFamily.trim().isNotEmpty)
          _paragraph('About the Family', f.aboutFamily),

        // ── Uploaded horoscope documents ──
        if (h.horoscopeImages.isNotEmpty || h.allPdfUrls.isNotEmpty) ...[
          const SizedBox(height: 14),
          HoroscopeDocumentsView.fromHoroscope(h,
              title: 'Horoscope Documents', thumbnailSize: 76),
        ],
      ],
    );
  }

  // ── Small building blocks ────────────────────────────────────────────────

  static String _date(DateTime d) => DateFormat('dd MMM yyyy').format(d);

  /// One titled group. Rows with an empty value are dropped, and a group whose
  /// rows are ALL empty disappears entirely — no rows of dashes.
  Widget _group(String title, List<(String, String)> rows) {
    final visible =
        rows.where((r) => r.$2.trim().isNotEmpty).toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: accent)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Colors.grey[200]),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(visible[i].$1,
                              style: TextStyle(
                                  fontSize: 11.5, color: Colors.grey[600])),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 5,
                          child: Text(visible[i].$2,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paragraph(String title, String body) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: accent)),
            const SizedBox(height: 6),
            Text(body,
                style: const TextStyle(fontSize: 12.5, height: 1.45)),
          ],
        ),
      );

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: accent)),
      );

  Widget _note(String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: Colors.grey[500]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
            ),
          ],
        ),
      );
}

/// External (non-member) party card — renders whatever the requester typed in
/// at booking time, in the same visual language as the member cards.
class _ExternalPartyCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Map<String, dynamic> details;

  const _ExternalPartyCard({
    required this.title,
    required this.icon,
    required this.details,
  });

  static const List<(String, String)> _fields = [
    ('name', 'Name'),
    ('gender', 'Gender'),
    ('age', 'Age'),
    ('dob', 'Date of Birth'),
    ('tob', 'Time of Birth'),
    ('place', 'Birth Place'),
    ('nakshatra', 'Nakshatra'),
    ('rasi', 'Rasi'),
  ];

  String _v(String key) => (details[key] ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final images = [_v('horoscopeImageUrl')].where((s) => s.isNotEmpty).toList();
    final pdfs = [_v('horoscopePdfUrl')].where((s) => s.isNotEmpty).toList();
    final rows = _fields
        .map((f) => (f.$2, _v(f.$1)))
        .where((r) => r.$2.isNotEmpty)
        .toList();

    return _card(
      accent: AppColors.primary,
      header: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$title (not a member)',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.isEmpty)
            Text('No details were provided.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[700]))
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: Colors.grey[200]),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text(rows[i].$1,
                                style: TextStyle(
                                    fontSize: 11.5, color: Colors.grey[600])),
                          ),
                          Expanded(
                            flex: 5,
                            child: Text(rows[i].$2,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (images.isNotEmpty || pdfs.isNotEmpty) ...[
            const SizedBox(height: 14),
            HoroscopeDocumentsView(
              imageUrls: images,
              pdfUrls: pdfs,
              title: 'Horoscope Documents',
              thumbnailSize: 76,
            ),
          ],
        ],
      ),
    );
  }
}

/// The shared premium shell: a coloured title bar over a white body.
Widget _card({
  required Color accent,
  required Widget header,
  required Widget child,
}) =>
    Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: accent,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: header,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            child: child,
          ),
        ],
      ),
    );
