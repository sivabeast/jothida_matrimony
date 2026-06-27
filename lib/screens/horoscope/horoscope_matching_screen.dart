import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/porutham_match.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/interest_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/horoscope_match_badge.dart' show categoryColor;

/// Horoscope Matching — lists ONLY the members the signed-in user has a
/// mutually-accepted interest with, for horoscope-focused matching.
///
/// Pending / rejected interests never appear here. Each card shows a summary
/// (photo, name, age, location, match category) plus the four horoscope
/// actions (View Horoscope · Compare Horoscope · Request Astrologer Analysis ·
/// Book Consultation). Tapping a card opens the full horoscope-matching detail.
class HoroscopeMatchingScreen extends StatelessWidget {
  const HoroscopeMatchingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Horoscope Matching'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: const AcceptedMatchesView(),
    );
  }
}

/// The accepted-matches list (no Scaffold / AppBar) — reused by the standalone
/// Horoscope Matching screen and the Home "Astrology" tab. Lists ONLY members
/// the user has a mutually-accepted interest with; each card offers the
/// horoscope actions including "Send for Match Analysis".
class AcceptedMatchesView extends ConsumerWidget {
  const AcceptedMatchesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
    final sent = ref.watch(sentInterestsProvider).valueOrNull ?? const [];
    final received =
        ref.watch(receivedInterestsProvider).valueOrNull ?? const [];

    // Every member with an ACCEPTED interest in EITHER direction.
    final uids = <String>{};
    for (final i in sent) {
      if (i.isAccepted) uids.add(i.receiverId);
    }
    for (final i in received) {
      if (i.isAccepted) uids.add(i.senderId);
    }
    uids.remove(myUid);
    final uidList = uids.toList();

    if (uidList.isEmpty) return const _EmptyMatches();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: uidList.length,
      itemBuilder: (_, i) => _AcceptedMatchCard(userId: uidList[i]),
    );
  }
}

/// One accepted-match card. Loads the member's public profile and renders the
/// summary + horoscope actions. Renders nothing if the profile can't be loaded.
class _AcceptedMatchCard extends ConsumerWidget {
  final String userId;
  const _AcceptedMatchCard({required this.userId});

  String _location(ProfileModel p) {
    final native = (p.nativePlace ?? '').trim();
    if (native.isNotEmpty) return native;
    return [p.city, p.state].where((s) => s.trim().isNotEmpty).join(', ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final otherAsync = ref.watch(profileByUserIdProvider(userId));
    final me = ref.watch(myProfileProvider).valueOrNull;
    final other = otherAsync.valueOrNull;
    if (other == null) return const SizedBox.shrink();

    final result = me == null ? null : computePorutham(me, other);
    final photo = other.photos.isNotEmpty ? other.photos.first : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _openDetail(context, other),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Profile Photo
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 76,
                      height: 76,
                      child: photo != null
                          ? Image.network(photo,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _avatar())
                          : _avatar(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name, Age
                        Text('${other.name}, ${other.age}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                fontSize: 16.5)),
                        const SizedBox(height: 4),
                        // Location
                        if (_location(other).isNotEmpty)
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 14, color: Colors.grey[500]),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(_location(other),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13, color: Colors.grey[700])),
                              ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        // Match Category
                        _categoryChip(result),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey[400]),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // ── Horoscope actions ──
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _actionChip(Icons.auto_awesome_outlined,
                          'View Horoscope',
                          () => context.push('/horoscope-user/$userId')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _actionChip(Icons.compare_arrows, 'Compare',
                          () => context.push('/horoscope-match/$userId')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        sendForMatchAnalysis(context, ref, me, other),
                    icon: const Icon(Icons.insights_outlined, size: 18),
                    label: const Text('Send for Match Analysis'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(42),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar() => Container(
        color: const Color(0xFFEFE7D6),
        child: Icon(Icons.person, size: 40, color: Colors.brown.shade200),
      );

  Widget _categoryChip(PoruthamMatchResult? result) {
    if (result == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('Horoscope pending',
            style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
      );
    }
    final color = categoryColor(result.category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(result.category.emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 5),
          Text(result.category.label,
              style: TextStyle(
                  fontSize: 11.5, color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          minimumSize: const Size.fromHeight(40),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  void _openDetail(BuildContext context, ProfileModel other) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HoroscopeMatchDetailScreen(other: other),
    ));
  }
}

/// Sends this accepted-match pairing straight to the internal astrology service
/// for a Match Analysis — no astrologer selection, no payment. Offered ONLY on
/// accepted matches (so the horoscope is unlocked), per the spec flow.
///
/// The user's own profile + the matched profile become the groom/bride pair
/// (split by gender; falls back to user=A, match=B when genders are equal or
/// unknown). On success it jumps to "My Match Analysis" to track the request.
Future<void> sendForMatchAnalysis(
  BuildContext context,
  WidgetRef ref,
  ProfileModel? me,
  ProfileModel other,
) async {
  final messenger = ScaffoldMessenger.of(context);
  if (me == null) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Complete your own profile before requesting analysis.')));
    return;
  }
  bool isMale(ProfileModel p) => p.gender.trim().toLowerCase().startsWith('m');
  final ProfileModel groom;
  final ProfileModel bride;
  if (isMale(me) && !isMale(other)) {
    groom = me;
    bride = other;
  } else if (!isMale(me) && isMale(other)) {
    groom = other;
    bride = me;
  } else {
    groom = me;
    bride = other;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Send for Match Analysis'),
      content: Text(
          'Send your horoscope and ${other.name}\'s for an astrology match '
          'analysis? Our astrology team will review and share a detailed report.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          child: const Text('Send'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    await ref
        .read(matchAnalysisControllerProvider.notifier)
        .requestInternalMatchAnalysis(groom: groom, bride: bride);
    if (!context.mounted) return;
    messenger.showSnackBar(const SnackBar(
        content: Text('Sent for astrology match analysis.')));
    context.push('/my-analysis');
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Could not send the request. Please try again.')));
  }
}

class _EmptyMatches extends StatelessWidget {
  const _EmptyMatches();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined,
                size: 64, color: AppColors.primary.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text('No accepted matches yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'When your interests are mutually accepted, those members appear '
              'here for horoscope matching.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full horoscope-matching detail for one accepted member, opened from a card.
///
/// Sections: User Basic Details · User Horoscope · My Horoscope · Horoscope
/// Comparison · Compatibility Result · Astrologer Analysis (if available) ·
/// Book Consultation.
class HoroscopeMatchDetailScreen extends ConsumerWidget {
  final ProfileModel other;
  const HoroscopeMatchDetailScreen({super.key, required this.other});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myProfileProvider).valueOrNull;
    final result = me == null ? null : computePorutham(me, other);

    // An existing astrologer analysis for this pairing, if the user has booked
    // one and the astrologer has completed it.
    final analyses =
        ref.watch(myMatchAnalysisRequestsProvider).valueOrNull ?? const [];
    AstrologerRequestModel? analysis;
    for (final r in analyses) {
      final involvesPartner =
          r.profileAId == other.id || r.profileBId == other.id;
      if (involvesPartner && r.hasAnalysis) {
        analysis = r;
        break;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Horoscope Matching'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _basicDetails(),
          const SizedBox(height: 16),
          _horoscopeCard('${other.name}\'s Horoscope', other.horoscope),
          const SizedBox(height: 16),
          if (me != null) ...[
            _horoscopeCard('My Horoscope', me.horoscope),
            const SizedBox(height: 16),
          ],
          if (result != null) ...[
            _compatibilityResult(result),
            const SizedBox(height: 16),
            _comparison(result),
            const SizedBox(height: 16),
          ] else
            _noCompatibility(me),
          _analysisSection(context, analysis),
          const SizedBox(height: 16),
          if (analysis == null) _sendForAnalysisButton(context, ref, me),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── User Basic Details ──
  Widget _basicDetails() {
    final location =
        [other.city, other.state].where((s) => s.trim().isNotEmpty).join(', ');
    final rows = <(String, String)>[
      ('Age', other.age > 0 ? '${other.age} years' : ''),
      ('Height', other.height),
      ('Location', location),
      ('Education', other.education),
      ('Profession', other.occupation),
      ('Religion', other.religion),
      ('Caste', other.caste ?? ''),
    ];
    return _card(
      title: 'Basic Details',
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: other.photos.isNotEmpty
                      ? Image.network(other.photos.first,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _avatarSmall())
                      : _avatarSmall(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('${other.name}${other.age > 0 ? ', ${other.age}' : ''}',
                    style: const TextStyle(
                        fontSize: 17,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final r in rows)
            if (r.$2.trim().isNotEmpty) _row(r.$1, r.$2),
        ],
      ),
    );
  }

  Widget _avatarSmall() => Container(
        color: const Color(0xFFEFE7D6),
        child: Icon(Icons.person, size: 32, color: Colors.brown.shade200),
      );

  // ── Horoscope card (Rasi + Nakshatra; full chart stays private) ──
  Widget _horoscopeCard(String title, HoroscopeDetails h) => _card(
        title: title,
        child: Column(
          children: [
            _row('Rasi (Moon Sign)', h.rasi),
            _row('Nakshatra (Star)', h.nakshatra),
          ],
        ),
      );

  // ── Compatibility Result ──
  Widget _compatibilityResult(PoruthamMatchResult result) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Text('Compatibility Result',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),
          Text(result.category.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 6),
          Text(result.category.label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${result.matchedCount} of ${result.totalCount} poruthams matched',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(result.recommendation,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12.5, height: 1.4)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Horoscope Comparison (10 poruthams) ──
  Widget _comparison(PoruthamMatchResult result) => _card(
        title: 'Horoscope Comparison',
        child: Column(
          children: [
            for (final p in result.poruthams)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(p.matched ? Icons.check_circle : Icons.cancel,
                        size: 18,
                        color: p.matched
                            ? AppColors.success
                            : AppColors.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(p.name,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w500)),
                    ),
                    Text(p.note,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _noCompatibility(ProfileModel? me) => _card(
        title: 'Compatibility Result',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            me == null
                ? 'Complete your own horoscope to see a compatibility result.'
                : 'Not enough horoscope data to calculate compatibility for '
                    'this pair. Add Rasi & Nakshatra details to both profiles.',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
        ),
      );

  // ── Astrologer Analysis (if available) ──
  Widget _analysisSection(
      BuildContext context, AstrologerRequestModel? analysis) {
    if (analysis == null) {
      return _card(
        title: 'Astrologer Analysis',
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: Colors.grey[500]),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'No astrologer analysis yet. Request one below for an expert '
                'porutham report.',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }
    // PAYMENT LOCK: the astrologer's report stays hidden until the fee is paid
    // (free analyses, amount == 0, are shown immediately). The report content is
    // never rendered here while locked — only a prompt to pay in My Match
    // Analysis, where the single payment flow lives.
    final locked = analysis.amount > 0 && !analysis.paid;
    if (locked) {
      return _card(
        title: 'Astrologer Analysis',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Report ready',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Your horoscope matching report has been completed. Complete '
              'payment to unlock and view it.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.push('/my-analysis'),
                icon: const Icon(Icons.lock_open, size: 16),
                label: const Text('Complete Payment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return _card(
      title: 'Astrologer Analysis',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, size: 16, color: AppColors.success),
              const SizedBox(width: 6),
              Expanded(
                child: Text('By ${analysis.astrologerName}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(analysis.analysisText,
              style: const TextStyle(fontSize: 13, height: 1.45)),
        ],
      ),
    );
  }

  Widget _sendForAnalysisButton(
          BuildContext context, WidgetRef ref, ProfileModel? me) =>
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => sendForMatchAnalysis(context, ref, me, other),
          icon: const Icon(Icons.insights_outlined),
          label: const Text('Send for Match Analysis'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

  // ── Shared building blocks ──
  Widget _card({required String title, required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const Divider(height: 18),
            child,
          ],
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Text(label,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            ),
            Expanded(
              flex: 6,
              child: Text(value.trim().isEmpty ? '—' : value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
