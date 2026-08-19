import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/porutham_match.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/astrology_service_config.dart';
import '../../models/profile_model.dart';
import '../../providers/astrology_config_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/interest_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/profile_provider.dart';

/// Opens (or explains the not-yet-ready state of) the Astrology Analysis Chat
/// for a horoscope-report request [r]. Used by the accepted-match card so every
/// "Open Analysis Chat" shortcut lands in the SAME thread — the request's
/// responder uid once the team accepts, else the internal account uid captured
/// in config (spec §12).
Future<void> openAnalysisChat(
  BuildContext context,
  WidgetRef ref,
  AstrologerRequestModel r,
  AstrologyServiceConfig cfg,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final otherUid =
      r.astrologerUid.isNotEmpty ? r.astrologerUid : cfg.internalUid;
  if (otherUid.isEmpty) {
    messenger.showSnackBar(const SnackBar(
        content: Text(
            'Your analysis chat will open once our team begins your report.')));
    return;
  }
  final name = cfg.expertName.trim().isEmpty ? 'Astrology Service' : cfg.expertName;
  try {
    final id = await ref.read(chatControllerProvider).openChatWith(
          otherUid: otherUid,
          otherName: name,
          otherPhoto: cfg.expertPhotoUrl,
        );
    if (!context.mounted) return;
    context.push('/chat/$id', extra: {
      'name': name,
      'photo': cfg.expertPhotoUrl,
      'isAstrologer': true,
    });
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Could not open chat. Please try again.')));
  }
}

/// The user's horoscope-report request for the pairing with [otherUserId], if
/// one exists (so the card can show the "Open Analysis Chat" shortcut).
AstrologerRequestModel? _reportRequestFor(WidgetRef ref, String otherProfileId) {
  final analyses =
      ref.watch(myMatchAnalysisRequestsProvider).valueOrNull ?? const [];
  for (final r in analyses) {
    if (r.profileAId == otherProfileId || r.profileBId == otherProfileId) {
      return r;
    }
  }
  return null;
}

/// Horoscope Matching — lists ONLY the members the signed-in user has a
/// mutually-accepted interest with, for horoscope-focused matching.
///
/// Pending / rejected interests never appear here. Each card shows a summary
/// (photo, name, age, location, matched-porutham count) plus the horoscope
/// actions. Tapping a card — like every other horoscope entry point in the app
/// — opens the ONE canonical Horoscope Match Result page.
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

    final cfg = ref.watch(astrologyServiceConfigValueProvider);
    final existingReport = _reportRequestFor(ref, other.id);
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
            onTap: () => context.push('/horoscope-match/$userId'),
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
                        // Porutham count only — no grade / percentage.
                        _poruthamCountChip(result),
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
                      child: _actionChip(Icons.compare_arrows, 'Match Result',
                          () => context.push('/horoscope-match/$userId')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    // Enters the SAME canonical Horoscope Match Result page as
                    // every other entry point; payment is offered there, after
                    // the free basic result.
                    onPressed: () =>
                        context.push('/horoscope-match/$userId'),
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Get Horoscope Compatibility Report'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(42),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                // Shortcut to the Astrology Analysis Chat — shown only once the
                // user has purchased a report for this pairing (spec §12).
                if (existingReport != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          openAnalysisChat(context, ref, existingReport, cfg),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: const Text('Open Analysis Chat'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                            color: AppColors.primary.withOpacity(0.4)),
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
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

  Widget _avatar() => Container(
        color: const Color(0xFFEFE7D6),
        child: Icon(Icons.person, size: 40, color: Colors.brown.shade200),
      );

  /// A neutral porutham COUNT chip — "7/10 poruthams matched". Never a grade,
  /// percentage or Excellent/Good/Average label; the full breakdown lives on
  /// the canonical Horoscope Match Result page.
  Widget _poruthamCountChip(PoruthamMatchResult? result) {
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Text(
        '${result.matchedCount}/${result.totalCount} poruthams matched',
        style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.primary,
            fontWeight: FontWeight.w700),
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
