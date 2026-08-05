import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/compatibility_report_model.dart';
import '../../models/profile_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/astrology_team_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/external_party_card.dart';
import '../../widgets/common/horoscope_documents_view.dart';
import '../../widgets/common/network_photo.dart';
import 'compatibility_report_screen.dart';

/// ONE Horoscope Report Request, opened from the Requests module (spec §2/§3).
///
/// Admin and Employee open the SAME page and see the same layout — the only
/// difference is which live stream the request is resolved from, because an
/// employee may not read the admin-wide request collection:
///
///   • Groom Details      — full profile of side A
///   • Bride Details      — full profile of side B
///   • Horoscope Details  — both sides' horoscope fields + uploaded documents
///   • Fill Report        — opens the structured Marriage Compatibility Report
///     (View Report once it has been submitted)
///
/// Astrology appointments never reach this page: both source streams are
/// filtered to [AstrologerRequestModel.isReportRequest] (spec §4).
class ReportRequestDetailPage extends ConsumerWidget {
  final String requestId;

  /// Snapshot passed by the list that opened this page — used for the first
  /// paint only; the live stream always wins once it resolves.
  final AstrologerRequestModel? initial;

  /// Resolve from the admin-wide stream ([allReportRequestsProvider]) instead
  /// of the signed-in employee's assigned stream.
  final bool admin;

  const ReportRequestDetailPage({
    super.key,
    required this.requestId,
    this.initial,
    this.admin = false,
  });

  AstrologerRequestModel? _resolve(WidgetRef ref) {
    final list = (admin
            ? ref.watch(allReportRequestsProvider)
            : ref.watch(myAssignedReportRequestsProvider))
        .valueOrNull;
    for (final r in list ?? const <AstrologerRequestModel>[]) {
      if (r.id == requestId) return r;
    }
    return initial;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = _resolve(ref);

    if (r == null) {
      return Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: _appBar(),
        body: const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: _appBar(),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _RequestHeader(request: r),
          const SizedBox(height: 14),
          if (r.isExternalReport) ...[
            // External report — the second person is not a registered member,
            // so both sides come from the entered details instead of profiles.
            ExternalPartyCard(
                title: 'Groom Details',
                icon: Icons.person,
                data: r.externalRequester),
            const SizedBox(height: 12),
            ExternalPartyCard(
                title: 'Bride Details',
                icon: Icons.person_add_alt_1,
                data: r.externalOther),
          ] else ...[
            _PersonCard(
              title: 'Groom Details',
              icon: Icons.male,
              profileId: r.groomProfileId ?? '',
              nameFallback: r.groomName ?? '',
            ),
            const SizedBox(height: 12),
            _PersonCard(
              title: 'Bride Details',
              icon: Icons.female,
              profileId: r.brideProfileId ?? '',
              nameFallback: r.brideName ?? '',
            ),
            const SizedBox(height: 12),
            _HoroscopeDetailsCard(request: r),
          ],
          const SizedBox(height: 14),
          _FillReportCard(request: r),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar() => AppBar(
        title: const Text('Report Request'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      );
}

// ── Header ───────────────────────────────────────────────────────────────────

class _RequestHeader extends StatelessWidget {
  final AstrologerRequestModel request;
  const _RequestHeader({required this.request});

  static String _dateTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}'
        ' · ${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final r = request;
    final completed = r.status == AstrologerRequestStatus.completed;
    final color = completed ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Request ${r.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(completed ? 'COMPLETED' : 'PENDING',
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Requested by ${r.userName}',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('Requested on ${_dateTime(r.createdAt)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          if (r.isAssigned) ...[
            const SizedBox(height: 2),
            Text('Assigned to ${r.astrologerName.isEmpty ? r.astrologerEmail : r.astrologerName}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
          if (r.message.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Note: ${r.message}',
                style: TextStyle(fontSize: 13, color: Colors.grey[800])),
          ],
        ],
      ),
    );
  }
}

// ── Groom / Bride details ────────────────────────────────────────────────────

/// Full profile details of one side. Horoscope fields are deliberately NOT
/// repeated here — they get their own combined section below.
class _PersonCard extends ConsumerWidget {
  final String title;
  final IconData icon;
  final String profileId;
  final String nameFallback;

  const _PersonCard({
    required this.title,
    required this.icon,
    required this.profileId,
    required this.nameFallback,
  });

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static int _age(DateTime dob) {
    final now = DateTime.now();
    var a = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      a--;
    }
    return a;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = profileId.isEmpty
        ? const AsyncValue<ProfileModel?>.data(null)
        : ref.watch(profileByIdProvider(profileId));
    return _card(
      child: async.when(
        loading: () => const SizedBox(
            height: 90,
            child: Center(
                child: CircularProgressIndicator(color: AppColors.primary))),
        error: (_, __) => _body(context, null),
        data: (p) => _body(context, p),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
          ],
        ),
        child: child,
      );

  Widget _body(BuildContext context, ProfileModel? p) {
    final name = p?.fullName.trim().isNotEmpty == true
        ? p!.fullName
        : (nameFallback.trim().isEmpty ? '—' : nameFallback);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: NetworkPhoto(
                  url: p?.profilePhotoUrl ?? '', width: 54, height: 54),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(title,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(name,
                      maxLines: 2,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        kvRow('Date of Birth', p == null ? '—' : _date(p.dateOfBirth)),
        kvRow('Age', p == null ? '—' : '${_age(p.dateOfBirth)}'),
        kvRow('Time of Birth', p?.horoscope.birthTime ?? ''),
        kvRow('Place of Birth', p?.horoscope.birthPlace ?? ''),
        kvRow('Gender', p?.gender ?? ''),
        kvRow('Marital Status', p?.maritalStatus ?? ''),
        kvRow('Education', p?.education ?? ''),
        kvRow('Occupation', p?.occupation ?? ''),
        kvRow('Religion / Caste',
            [p?.religion ?? '', p?.caste ?? ''].where((s) => s.trim().isNotEmpty).join(' · ')),
        kvRow('Location',
            [p?.city ?? '', p?.state ?? ''].where((s) => s.trim().isNotEmpty).join(', ')),
      ],
    );
  }
}

/// Shared "label · value" row (also used by the horoscope section). Empty
/// values render as an em dash so the layout never collapses.
Widget kvRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 118,
              child: Text(label,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600]))),
          Expanded(
            child: Text(value.trim().isEmpty ? '—' : value.trim(),
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

// ── Horoscope details ────────────────────────────────────────────────────────

/// Both sides' horoscope fields and their uploaded horoscope documents, so the
/// whole report can be prepared without leaving the page.
class _HoroscopeDetailsCard extends ConsumerWidget {
  final AstrologerRequestModel request;
  const _HoroscopeDetailsCard({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.auto_awesome_outlined,
                  size: 20, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Horoscope Details',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          _side(ref, context,
              label: 'Groom',
              profileId: request.groomProfileId ?? '',
              fallback: request.groomName ?? ''),
          const SizedBox(height: 8),
          const Divider(height: 18),
          _side(ref, context,
              label: 'Bride',
              profileId: request.brideProfileId ?? '',
              fallback: request.brideName ?? ''),
        ],
      ),
    );
  }

  Widget _side(
    WidgetRef ref,
    BuildContext context, {
    required String label,
    required String profileId,
    required String fallback,
  }) {
    final p = profileId.isEmpty
        ? null
        : ref.watch(profileByIdProvider(profileId)).valueOrNull;
    final h = p?.horoscope;
    final name = p?.fullName.trim().isNotEmpty == true
        ? p!.fullName
        : (fallback.trim().isEmpty ? '—' : fallback);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label — $name',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary)),
        const SizedBox(height: 6),
        kvRow('Rasi', h?.rasi ?? ''),
        kvRow('Nakshatra', h?.nakshatra ?? ''),
        kvRow('Lagnam', h?.lagnam ?? ''),
        kvRow('Dasa Balance', h?.dasaBalance ?? ''),
        kvRow('Chevvai Dosham', h?.dosham ?? ''),
        kvRow('Rahu / Kethu Dosham', h?.rahuKethuDosham ?? ''),
        kvRow('Kalasarpa Dosham', h?.kalasarpaDosham ?? ''),
        const SizedBox(height: 10),
        HoroscopeDocumentsView.fromHoroscope(
          h,
          title: context.l10n.horoscopeDocuments,
          thumbnailSize: 78,
        ),
      ],
    );
  }
}

// ── Fill Report ──────────────────────────────────────────────────────────────

/// Entry point to the structured Marriage Compatibility Report — the ONE place
/// a report is written and submitted, for admins and employees alike.
class _FillReportCard extends StatelessWidget {
  final AstrologerRequestModel request;
  const _FillReportCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final r = request;
    final saved = CompatibilityReport.tryFrom(r.compatReport);
    final completed = r.status == AstrologerRequestStatus.completed;
    final submitted = (saved?.isSubmitted ?? false) || completed;

    final (String statusLabel, Color statusColor) = submitted
        ? ('Submitted', AppColors.success)
        : saved != null
            ? ('Draft in progress', AppColors.warning)
            : ('Not started', Colors.grey);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_outlined,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Marriage Compatibility Report',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: statusColor)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'திருமண பொருத்தம் அறிக்கை — the official A4 certificate the user '
            'receives (porutham table, தோஷம், திசா சந்தி, விளக்கம், '
            'இறுதி முடிவு).',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CompatibilityReportScreen(
                requestId: r.id,
                request: r,
                employee: true,
              ),
            )),
            icon: Icon(
                submitted ? Icons.visibility_outlined : Icons.edit_outlined,
                size: 18),
            label: Text(submitted
                ? 'View Submitted Report'
                : (saved != null ? 'Continue Report' : 'Fill Report')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}
