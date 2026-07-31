import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/value_l10n.dart';
import '../../models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/block_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/interest_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/contact_reveal_card.dart';
import '../../widgets/common/fullscreen_photo_viewer.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/horoscope_documents_view.dart';
import '../../widgets/common/network_photo.dart';

class ProfileViewScreen extends ConsumerStatefulWidget {
  /// Open by profile-document id — used from Discover / Matches, where the id
  /// comes straight from the loaded profile and is reliable.
  final String? profileId;

  /// Open by the profile owner's USER id (UID) — preferred from accepted
  /// interests, where the UID (senderId / receiverId) is the dependable key and
  /// a stored profile-document id may be stale or missing.
  final String? userId;

  const ProfileViewScreen({super.key, this.profileId, this.userId})
      : assert(profileId != null || userId != null,
            'Provide either a profileId or a userId');

  @override
  ConsumerState<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends ConsumerState<ProfileViewScreen> {
  /// Guards the one-time view-count increment for this screen instance.
  bool _viewCounted = false;

  /// True when the signed-in user is looking at their OWN profile — the owner
  /// always sees everything, privacy switches only apply to other members.
  bool _isOwner(ProfileModel profile) {
    final myUid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
    return myUid != null && myUid == profile.userId;
  }

  /// Records a single profile view per screen-open, and never when the owner
  /// views their own profile. This previously lived inside build(), so it fired
  /// on every rebuild (photo swipes, scrolls, parent rebuilds) and also counted
  /// self-views — which silently inflated viewCount into the hundreds.
  void _recordViewOnce(ProfileModel profile) {
    if (_viewCounted) return;
    final myUid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
    if (myUid != null && myUid == profile.userId) return; // skip self-views
    _viewCounted = true;
    // Best-effort: a non-owner view-count write may be denied by Firestore
    // rules — swallow it so it can NEVER surface as a "couldn't load" error.
    ref
        .read(profileRepositoryProvider)
        .incrementViewCount(profile.id)
        .catchError((_) {});
  }

  Future<void> _sendInterest(ProfileModel profile) async {
    final userId = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
    if (userId == null) return;
    final myProfile = await ref.read(profileRepositoryProvider).getProfileByUserId(userId);
    if (myProfile == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(context.l10n.createProfileFirstInterest)));
      }
      return;
    }
    // Sending interests is FREE and unlimited — no plan gate.
    await ref.read(interestNotifierProvider.notifier).sendInterest(
          senderId: userId,
          receiverId: profile.userId,
          senderProfileId: myProfile.id,
          receiverProfileId: profile.id,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.interestSentSuccess)));
    }
  }

  void _reportProfile(ProfileModel profile) {
    context.push('/report/${profile.id}');
  }

  /// Report / Block overflow menu on the profile header (spec §5, §6). Block is
  /// hidden on your own profile.
  Widget _moderationMenu(ProfileModel profile) {
    final myUid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
    final isSelf = myUid != null && myUid == profile.userId;
    final iBlocked =
        (ref.watch(myBlockedUidsProvider).valueOrNull ?? const <String>{})
            .contains(profile.userId);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (v) {
        switch (v) {
          case 'report':
            _reportProfile(profile);
            break;
          case 'block':
            _confirmBlockProfile(profile);
            break;
          case 'unblock':
            _unblockProfile(profile);
            break;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'report',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.flag_outlined),
            title: Text(context.l10n.reportProfileAction),
          ),
        ),
        if (!isSelf)
          PopupMenuItem(
            value: iBlocked ? 'unblock' : 'block',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(iBlocked ? Icons.lock_open : Icons.block,
                  color: iBlocked ? null : AppColors.error),
              title: Text(iBlocked
                  ? context.l10n.unblockUserAction
                  : context.l10n.blockUserAction),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmBlockProfile(ProfileModel profile) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.blockUserQuestion(profile.name)),
        content: Text(l10n.blockUserBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(l10n.blockLabel),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(blockControllerProvider.notifier).block(profile.userId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.userBlockedToast(profile.name))));
      context.pop();
    }
  }

  Future<void> _unblockProfile(ProfileModel profile) async {
    await ref.read(blockControllerProvider.notifier).unblock(profile.userId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.userUnblockedToast(profile.name))));
    }
  }

  /// Whether this member's phone number may be shown to the viewer.
  ///
  /// "Hide Phone Number" is ON by default (§17) and an accepted interest does
  /// NOT flip it — only the owner can, from Privacy Settings. So the contact
  /// actions below are hidden entirely for a member who keeps their number
  /// private, rather than offering a button that leads to a locked card.
  bool _phoneVisible(ProfileModel profile) =>
      _isOwner(profile) || !profile.hidesPhone;

  void _showContact(ProfileModel profile) {
    // Contact & WhatsApp viewing is FREE — no plan gate. (The privacy gate —
    // contact unlocks only after a mutually-accepted interest — still lives in
    // ContactRevealCard / the contacts security rules.)
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ContactRevealCard(
                otherUserId: profile.userId,
                otherName: profile.name,
                contact: profile.contact,
                hiddenByOwner: !_phoneVisible(profile)),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptInterest(String interestId) async {
    await ref.read(interestNotifierProvider.notifier).acceptInterest(interestId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.interestAcceptedMatch)));
    }
  }

  /// The bottom action(s). Public profiles (§17/§18) expose contact to every
  /// viewer, so a "View Contact" button is shown up-front — the accepted branch
  /// already reveals contact, so this only prepends it for the other states.
  Widget _interestAction(ProfileModel profile) {
    final accepted = ref.watch(interestStatusForProfileProvider(profile.id)) ==
        InterestUiStatus.accepted;
    final action = _statusInterestAction(profile);
    if (!profile.isContactPublic || accepted || !_phoneVisible(profile)) {
      return action;
    }
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showContact(profile),
            icon: const Icon(Icons.call),
            label: Text(context.l10n.viewContact),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              minimumSize: const Size.fromHeight(52),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        action,
      ],
    );
  }

  /// Status-aware bottom action. Source of truth is the real Firestore interest
  /// status, so an accepted interest never shows "Send Interest" again, and an
  /// interest the other user already sent us offers "Accept" rather than a
  /// duplicate "Send Interest".
  Widget _statusInterestAction(ProfileModel profile) {
    final status = ref.watch(interestStatusForProfileProvider(profile.id));
    final accepted = status == InterestUiStatus.accepted;
    final alreadySent = status == InterestUiStatus.sent;

    if (status == InterestUiStatus.rejected) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.cancel),
          label: Text(context.l10n.interestRejected),
          style: ElevatedButton.styleFrom(
            disabledBackgroundColor: Colors.grey.shade400,
            disabledForegroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    if (status == InterestUiStatus.receivedPending) {
      final pending =
          ref.watch(pendingReceivedInterestFromProfileProvider(profile.id));
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: pending == null ? null : () => _acceptInterest(pending.id),
          icon: const Icon(Icons.favorite),
          label: Text(context.l10n.acceptInterest),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    if (accepted) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Text(context.l10n.interestAccepted,
                    style: const TextStyle(
                        color: Colors.green, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Contact is offered ONLY when the member has not switched
          // "Hide Phone Number" on. Acceptance alone never reveals it (§17).
          if (_phoneVisible(profile)) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                // Reveal straight from the (readable) profile document — no
                // connection/gated read.
                onPressed: () => _showContact(profile),
                icon: const Icon(Icons.call),
                label: Text(context.l10n.viewContact),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Chat — opens the conversation with this matched user. Shown ONLY
          // when the interest is accepted (this branch); the auto-created thread
          // is idempotent so this always opens the SAME conversation as the
          // Chats tab (spec §4/§7). Single leading icon, Material styling.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openChat(profile),
              icon: const Icon(Icons.chat_bubble_outline, size: 20),
              label: Text(context.l10n.chat,
                  style: const TextStyle(
                      fontSize: 15,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                elevation: 1.5,
                shadowColor: AppColors.gold.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      );
    }

    if (alreadySent) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.hourglass_top),
          label: Text(context.l10n.interestSent),
          style: ElevatedButton.styleFrom(
            disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
            disabledForegroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: GradientButton(
        onPressed: () => _sendInterest(profile),
        text: context.l10n.sendInterest,
      ),
    );
  }

  /// Re-fetch whichever lookup this screen was opened with.
  void _reloadProfile() {
    if (widget.userId != null) {
      ref.invalidate(profileByUserIdProvider(widget.userId!));
    } else {
      ref.invalidate(profileByIdProvider(widget.profileId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prefer the UID lookup when opened from an accepted interest; otherwise use
    // the profile-document id. Both yield AsyncValue<ProfileModel?>.
    final profileAsync = widget.userId != null
        ? ref.watch(profileByUserIdProvider(widget.userId!))
        : ref.watch(profileByIdProvider(widget.profileId!));

    return Scaffold(
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.couldNotLoadProfileRetry,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _reloadProfile,
                  icon: const Icon(Icons.refresh),
                  label: Text(context.l10n.tryAgain),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary)),
                ),
              ],
            ),
          ),
        ),
        data: (profile) {
          if (profile == null) {
            return Center(child: Text(context.l10n.profileNotFound));
          }
          // Record a single view after this frame — never mutate a provider
          // during build. The guard inside _recordViewOnce ensures exactly one
          // increment per screen-open and skips the owner's own visits.
          if (!_viewCounted) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _recordViewOnce(profile));
          }
          return _buildProfileView(profile);
        },
      ),
    );
  }

  Widget _buildProfileView(ProfileModel profile) {
    final isOwner = _isOwner(profile);
    // §16/§17 — the four privacy switches. The owner always sees their own
    // data; for everyone else a hidden field is simply not rendered, and
    // accepting an interest does NOT change that.
    final hidePhoto = !isOwner && profile.hidesPhoto;
    final hideSalary = !isOwner && profile.hidesSalary;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [_moderationMenu(profile)],
          flexibleSpace: FlexibleSpaceBar(
            background: _headerPhoto(profile, hidden: hidePhoto),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.displayName(context.isTamil),
                    style: AppTextStyles.heading1),
                Text(
                  '${profile.age} yrs • ${[
                    profile.city,
                    profile.state
                  ].where((s) => s.trim().isNotEmpty).join(', ')}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                // ── Basic Details — labels via l10n, stored values via the
                // EN→TA value map so everything switches with the language. ──
                _buildInfoSection(context.l10n.basicDetails, [
                  _InfoItem(Icons.cake_outlined, context.l10n.age,
                      '${profile.age} ${context.l10n.years}'),
                  _InfoItem(Icons.height, context.l10n.height, profile.height),
                  _InfoItem(Icons.monitor_weight_outlined, context.l10n.weight,
                      profile.weight),
                  _InfoItem(Icons.wc, context.l10n.maritalStatus,
                      context.localizeValue(profile.maritalStatus)),
                  _InfoItem(Icons.school_outlined, context.l10n.education,
                      context.localizeValue(profile.education)),
                  _InfoItem(Icons.work_outline, context.l10n.profession,
                      context.localizeValue(profile.occupation)),
                  // Salary is one of the four privacy switches (§16) — hidden
                  // by default and never auto-revealed.
                  _InfoItem(Icons.payments_outlined, context.l10n.annualIncome,
                      hideSalary ? '' : context.localizeValue(profile.annualIncome)),
                  _InfoItem(Icons.place_outlined, context.l10n.location,
                      [profile.city, profile.state].where((s) => s.trim().isNotEmpty).join(', ')),
                  _InfoItem(Icons.translate, context.l10n.motherTongue,
                      context.localizeValue(profile.motherTongue)),
                  _InfoItem(Icons.accessibility_new, context.l10n.physicalStatus,
                      context.localizeValue(profile.physicalStatus)),
                  _InfoItem(Icons.church_outlined, context.l10n.religion,
                      context.localizeValue(profile.religion)),
                  _InfoItem(Icons.people_outline, context.l10n.caste,
                      context.localizeValue(profile.caste ?? '')),
                  _InfoItem(Icons.groups_2_outlined, context.l10n.subCaste,
                      context.localizeValue(profile.subCaste ?? '')),
                  _InfoItem(Icons.account_balance_outlined, context.l10n.gothram,
                      profile.gothram),
                  _InfoItem(Icons.auto_awesome_outlined, context.l10n.kuladeivam,
                      profile.kuladeivam),
                  _InfoItem(Icons.badge_outlined, context.l10n.employmentType,
                      context.localizeValue(profile.employmentType)),
                  _InfoItem(Icons.business_outlined, context.l10n.companyName,
                      profile.companyName ?? ''),
                  _InfoItem(Icons.account_balance, context.l10n.collegeName,
                      profile.collegeName ?? ''),
                  _InfoItem(Icons.location_city_outlined,
                      context.l10n.nativePlace, profile.nativePlace ?? ''),
                ]),
                if (profile.about.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(context.l10n.aboutMe, style: AppTextStyles.heading3),
                  const SizedBox(height: 8),
                  Text(profile.about, style: AppTextStyles.bodyMedium),
                ],
                const SizedBox(height: 20),
                // ── Family Details ──
                ..._familySection(profile.family),
                // ── Horoscope Details ──
                _horoscopeSection(profile),
                const SizedBox(height: 20),
                // ── Lifestyle Details ──
                ..._lifestyleSection(profile.lifestyle),
                // ── Partner Preference Comparison ──
                ..._partnerPreferenceComparison(profile),
                const SizedBox(height: 32),
                // Status-aware action: accepted → View Contact (never "Send
                // Interest" again); pending → "Interest Sent"; otherwise the
                // Send Interest button.
                _interestAction(profile),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The single 1:1 profile photo in the collapsing header.
  ///
  /// Tapping it opens the full-screen viewer (dark background, zoom, pan,
  /// close) — §10. When the member hides their photo (§16, default), a neutral
  /// placeholder is shown instead and there is nothing to open.
  Widget _headerPhoto(ProfileModel profile, {required bool hidden}) {
    final url = profile.profilePhotoUrl ?? '';
    if (hidden || url.isEmpty) {
      return Container(
        color: AppColors.primary.withOpacity(0.3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person, size: 100, color: Colors.white),
            if (hidden) ...[
              const SizedBox(height: 8),
              Text(context.l10n.photoHiddenByMember,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            ],
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: () => FullScreenPhotoViewer.open(context, url),
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetworkPhoto(
            url: url,
            fit: BoxFit.cover,
            fallbackIconSize: 100,
            showLoadingSpinner: true,
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.42),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.zoom_out_map,
                      size: 13, color: Colors.white),
                  const SizedBox(width: 5),
                  Text(context.l10n.tapPhotoToEnlarge,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Lifestyle section — rendered only when at least one habit/field is set.
  List<Widget> _lifestyleSection(LifestyleDetails l) {
    final items = <_InfoItem>[
      _InfoItem(Icons.restaurant_outlined, context.l10n.eatingHabit,
          context.localizeValue(l.eatingHabit)),
      _InfoItem(Icons.smoke_free, context.l10n.smokingHabit,
          context.localizeValue(l.smokingHabit)),
      _InfoItem(Icons.no_drinks_outlined, context.l10n.drinkingHabit,
          context.localizeValue(l.drinkingHabit)),
      _InfoItem(Icons.sports_esports_outlined, context.l10n.hobbies, l.hobbies),
      _InfoItem(Icons.interests_outlined, context.l10n.interests, l.interests),
      _InfoItem(Icons.translate, context.l10n.languagesKnown,
          l.languagesKnown.map(context.localizeValue).join(', ')),
    ];
    if (items.every((i) => i.value.trim().isEmpty)) return const [];
    return [
      _buildInfoSection(context.l10n.lifestyleDetails, items),
      const SizedBox(height: 20),
    ];
  }

  /// Family Details section — rendered only when at least one field is set.
  List<Widget> _familySection(FamilyDetails f) {
    final items = <_InfoItem>[
      _InfoItem(Icons.man_outlined, context.l10n.father, f.fatherName),
      _InfoItem(Icons.work_history_outlined, context.l10n.fatherOccupation,
          context.localizeValue(f.fatherOccupation)),
      _InfoItem(Icons.woman_outlined, context.l10n.mother, f.motherName),
      _InfoItem(Icons.work_history_outlined, context.l10n.motherOccupation,
          context.localizeValue(f.motherOccupation)),
      _InfoItem(Icons.group_outlined, context.l10n.brothers,
          f.brothersCount > 0 ? '${f.brothersCount}' : ''),
      _InfoItem(Icons.group_outlined, context.l10n.sisters,
          f.sistersCount > 0 ? '${f.sistersCount}' : ''),
      _InfoItem(Icons.family_restroom, context.l10n.familyType,
          context.localizeValue(f.familyType)),
      _InfoItem(Icons.diamond_outlined, context.l10n.familyStatus,
          context.localizeValue(f.familyStatus)),
    ];
    if (items.every((i) => i.value.trim().isEmpty) &&
        f.aboutFamily.trim().isEmpty) {
      return const [];
    }
    return [
      _buildInfoSection(context.l10n.familyDetails, items),
      if (f.aboutFamily.trim().isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(context.l10n.aboutFamily, style: AppTextStyles.heading3),
        const SizedBox(height: 8),
        Text(f.aboutFamily, style: AppTextStyles.bodyMedium),
      ],
      const SizedBox(height: 20),
    ];
  }

  /// Partner-preference COMPARISON — instead of just listing the viewer's
  /// preferences, compares each against THIS profile and shows whether it
  /// matches, ending with an overall "X of Y Preferences Matched" summary.
  List<Widget> _partnerPreferenceComparison(ProfileModel profile) {
    final me = ref.watch(myProfileProvider).valueOrNull;
    if (me == null) return const [];
    // Don't compare the viewer's own profile against itself.
    if (me.userId == profile.userId) return const [];

    final rows = _comparisonRows(me.partnerPreferences, profile);
    if (rows.isEmpty) return const [];
    final matched = rows.where((r) => r.matched).length;

    return [
      Text(context.l10n.partnerPreferenceMatch, style: AppTextStyles.heading3),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          children: [
            // Header row.
            Container(
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                        flex: 5,
                        child: _HeaderText(context.l10n.preferenceHeader)),
                    Expanded(
                        flex: 6, child: _HeaderText(context.l10n.myPrefHeader)),
                    Expanded(
                        flex: 6,
                        child: _HeaderText(context.l10n.thisProfileHeader)),
                    Expanded(
                        flex: 5, child: _HeaderText(context.l10n.statusHeader)),
                  ],
                ),
              ),
            ),
            for (var i = 0; i < rows.length; i++) ...[
              Divider(height: 1, color: Colors.grey[200]),
              _comparisonRowTile(rows[i]),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      // Overall summary.
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.favorite, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(context.l10n.overallPreferenceMatch,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
            ),
            Text(context.l10n.matchedCount(matched, rows.length),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ],
        ),
      ),
      const SizedBox(height: 8),
    ];
  }

  Widget _comparisonRowTile(_PrefCmp r) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 5,
              child: Text(r.label,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              flex: 6,
              child: Text(r.myPref,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            ),
            Expanded(
              flex: 6,
              child: Text(r.theirs,
                  style: const TextStyle(fontSize: 12)),
            ),
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Icon(r.matched ? Icons.check_circle : Icons.cancel,
                      size: 14,
                      color: r.matched ? AppColors.success : AppColors.error),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                        r.matched
                            ? context.l10n.matchWord
                            : context.l10n.noMatchWord,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color:
                                r.matched ? AppColors.success : AppColors.error)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  /// Builds one comparison row per ACTIVE preference dimension. Age & Height are
  /// always compared (they always carry a range); the rest are included only
  /// when the viewer has actually set them.
  List<_PrefCmp> _comparisonRows(PartnerPreferences p, ProfileModel c) {
    bool set(String? s) {
      final n = (s ?? '').trim().toLowerCase();
      return n.isNotEmpty && n != 'any';
    }

    bool eq(String a, String? b) {
      final na = a.trim().toLowerCase(), nb = (b ?? '').trim().toLowerCase();
      if (na.isEmpty || nb.isEmpty) return false;
      return na == nb || na.contains(nb) || nb.contains(na);
    }

    String dash(String s) => s.trim().isEmpty ? '—' : s;

    final rows = <_PrefCmp>[];

    final l10n = context.l10n;

    // Age (always).
    rows.add(_PrefCmp(
      l10n.age,
      l10n.ageRangeValue(p.minAge, p.maxAge),
      c.age > 0 ? '${c.age} ${l10n.years}' : '—',
      c.age >= p.minAge && c.age <= p.maxAge,
    ));

    // Height (always; matched only when all three values are recognised).
    final hl = AppConstants.heightList;
    final minI = hl.indexOf(p.minHeight);
    final maxI = hl.indexOf(p.maxHeight);
    final cI = hl.indexOf(c.height);
    final hMatched =
        (minI >= 0 && maxI >= 0 && cI >= 0) ? (cI >= minI && cI <= maxI) : true;
    rows.add(_PrefCmp(
      l10n.height,
      l10n.rangeValue(p.minHeight, p.maxHeight),
      dash(c.height),
      hMatched,
    ));

    // Education.
    if (p.education.isNotEmpty) {
      rows.add(_PrefCmp(
        l10n.education,
        p.education.map(context.localizeValue).join(', '),
        dash(context.localizeValue(c.education)),
        p.education.any((e) => eq(c.education, e)),
      ));
    }

    // Profession (occupation).
    if (p.occupation.isNotEmpty) {
      rows.add(_PrefCmp(
        l10n.profession,
        p.occupation.map(context.localizeValue).join(', '),
        dash(context.localizeValue(c.occupation)),
        p.occupation.any((o) => eq(c.occupation, o)),
      ));
    }

    // Location (city / state).
    if (set(p.city) || set(p.state)) {
      final pref =
          [p.city, p.state].where((s) => set(s)).map((s) => s!).join(', ');
      final theirs =
          [c.city, c.state].where((s) => s.trim().isNotEmpty).join(', ');
      final ok = (set(p.city) ? eq(c.city, p.city) : true) &&
          (set(p.state) ? eq(c.state, p.state) : true);
      rows.add(_PrefCmp(l10n.location, pref, dash(theirs), ok));
    }

    // Religion.
    if (set(p.religion)) {
      rows.add(_PrefCmp(
          l10n.religion,
          context.localizeValue(p.religion),
          dash(context.localizeValue(c.religion)),
          eq(c.religion, p.religion)));
    }

    // Caste.
    if (set(p.caste)) {
      rows.add(_PrefCmp(
          l10n.caste,
          context.localizeValue(p.caste!),
          dash(context.localizeValue(c.caste ?? '')),
          eq(c.caste ?? '', p.caste)));
    }

    return rows;
  }

  /// Horoscope section with privacy rules:
  ///  • The OWNER sees the full generated horoscope (Rasi, Nakshatra, Lagnam,
  ///    birth details, doshams).
  ///  • A member who switched "Hide Horoscope Details" ON (the DEFAULT, §17)
  ///    shows nothing at all to other viewers — accepting an interest does not
  ///    change that; only the owner can, from Privacy Settings.
  ///  • Otherwise OTHER users see only Rasi + Nakshatra + a "Horoscope
  ///    Available" indicator, and can tap "Consult Astrologer".
  Widget _horoscopeSection(ProfileModel profile) {
    final isOwner = _isOwner(profile);
    final h = profile.horoscopeDetails;

    if (!isOwner && profile.hidesHoroscope) {
      return _hiddenSectionCard(context.l10n.horoscopeDetails);
    }

    if (isOwner) {
      // The owner always sees their own uploaded documents — no gate.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoSection(context.l10n.horoscopeDetails, [
            _InfoItem(Icons.stars, context.l10n.rasi, h.rasi),
            _InfoItem(Icons.star_border, context.l10n.nakshatra, h.nakshatra),
            _InfoItem(Icons.wb_twilight, context.l10n.lagnam, h.lagnam),
            _InfoItem(
                Icons.place_outlined, context.l10n.birthPlace, h.birthPlace),
            _InfoItem(Icons.access_time, context.l10n.birthTime, h.birthTime),
            _InfoItem(Icons.brightness_5_outlined, context.l10n.chevvaiDosham,
                context.localizeValue(h.dosham)),
            _InfoItem(Icons.brightness_5_outlined, context.l10n.rahuKethuDosham,
                context.localizeValue(h.rahuKethuDosham)),
            _InfoItem(Icons.brightness_5_outlined, context.l10n.kalasarpaDosham,
                context.localizeValue(h.kalasarpaDosham)),
          ]),
          if (h.horoscopeImages.isNotEmpty || h.allPdfUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            HoroscopeDocumentsView.fromHoroscope(
              h,
              title: context.l10n.horoscopeDocuments,
            ),
          ],
        ],
      );
    }

    // Other users: limited view (Rasi + Nakshatra only) + availability note.
    final hasHoroscope = h.rasi.trim().isNotEmpty ||
        h.nakshatra.trim().isNotEmpty ||
        h.horoscopeGenerated ||
        h.allPdfUrls.isNotEmpty ||
        h.horoscopeImages.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoSection(context.l10n.horoscope, [
          _InfoItem(Icons.stars, context.l10n.rasi, h.rasi),
          _InfoItem(Icons.star_border, context.l10n.nakshatra, h.nakshatra),
        ]),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                      hasHoroscope
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      size: 18,
                      color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    hasHoroscope
                        ? context.l10n.horoscopeAvailable
                        : context.l10n.horoscopeNotProvided,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.horoscopePrivateNote,
                style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
              ),
              if (hasHoroscope) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _consultAstrologer(profile),
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(context.l10n.consultAstrologer),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _horoscopeDocumentsSection(profile),
      ],
    );
  }

  /// Uploaded horoscope documents, gated on a mutually-accepted interest.
  ///
  ///  • BEFORE acceptance → a locked card explaining how to unlock it. The
  ///    files are never rendered, downloadable or linked.
  ///  • AFTER acceptance  → full access: image previews (tap = full screen)
  ///    and PDFs with View + Download.
  ///
  /// (Employees/admins reach the same documents through the Request Details
  /// page, which is not subject to this gate.)
  Widget _horoscopeDocumentsSection(ProfileModel profile) {
    final h = profile.horoscopeDetails;
    final hasFiles =
        h.horoscopeImages.isNotEmpty || h.allPdfUrls.isNotEmpty;
    if (!hasFiles) return const SizedBox.shrink();

    final accepted = ref.watch(interestStatusForProfileProvider(profile.id)) ==
        InterestUiStatus.accepted;

    if (!accepted) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(context.l10n.horoscopeLockedTitle,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(context.l10n.horoscopeLockedBody,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_open_outlined,
                  size: 18, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.l10n.horoscopeUnlockedNote,
                    style: TextStyle(
                        fontSize: 12.5, color: Colors.grey[800])),
              ),
            ],
          ),
          const SizedBox(height: 12),
          HoroscopeDocumentsView.fromHoroscope(
            h,
            title: context.l10n.horoscopeDocuments,
          ),
        ],
      ),
    );
  }

  /// Opens the Horoscope Compatibility Report service for this pairing.
  void _consultAstrologer(ProfileModel profile) {
    context.push('/horoscope-report/${profile.userId}');
  }

  /// Opens the one shared conversation with this accepted match. [openChatWith]
  /// is idempotent (deterministic thread id), so it never creates a duplicate
  /// room — the Chats tab and this button always land on the same chat (§7).
  Future<void> _openChat(ProfileModel profile) async {
    final messenger = ScaffoldMessenger.of(context);
    final pic = profile.profilePhotoUrl ?? '';
    final photo = pic.isNotEmpty
        ? pic
        : (profile.photos.isNotEmpty ? profile.photos.first : '');
    try {
      final id = await ref.read(chatControllerProvider).openChatWith(
            otherUid: profile.userId,
            otherName: profile.name,
            otherPhoto: photo,
          );
      if (!mounted) return;
      context.push('/chat/$id', extra: {'name': profile.name, 'photo': photo});
    } catch (_) {
      messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotOpenChatRetry)));
    }
  }

  /// Neutral "the member keeps this private" card. Used for a whole section
  /// the owner has switched off in Privacy Settings (§16/§17) — it states the
  /// fact without hinting at the value and offers no way to reveal it.
  Widget _hiddenSectionCard(String title) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.heading3),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(context.l10n.hiddenByMember,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[700])),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _buildInfoSection(String title, List<_InfoItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.heading3),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: items
                .where((item) => item.value.isNotEmpty)
                .map((item) => ListTile(
                      dense: true,
                      leading: Icon(item.icon, size: 20, color: AppColors.primary),
                      title: Text(item.label,
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: Text(item.value,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;

  const _InfoItem(this.icon, this.label, this.value);
}

/// Bold column header used by the partner-preference comparison table.
class _HeaderText extends StatelessWidget {
  final String text;
  const _HeaderText(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.primary),
      );
}

/// One comparison row: the viewer's preference vs. this profile's value and
/// whether the profile satisfies it.
class _PrefCmp {
  final String label;
  final String myPref;
  final String theirs;
  final bool matched;

  const _PrefCmp(this.label, this.myPref, this.theirs, this.matched);
}
