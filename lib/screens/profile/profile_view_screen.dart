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
import '../../providers/chat_provider.dart';
import '../../providers/interest_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/contact_reveal_card.dart';
import '../../widgets/common/gradient_button.dart';
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
  int _photoIndex = 0;

  /// Guards the one-time view-count increment for this screen instance.
  bool _viewCounted = false;

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
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Create your profile first to send interest')));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Interest sent successfully!')));
    }
  }

  void _reportProfile(ProfileModel profile) {
    context.push('/report/${profile.id}');
  }

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
                contact: profile.contact),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptInterest(String interestId) async {
    await ref.read(interestNotifierProvider.notifier).acceptInterest(interestId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Interest accepted — it\'s a match!')));
    }
  }

  /// Status-aware bottom action. Source of truth is the real Firestore interest
  /// status, so an accepted interest never shows "Send Interest" again, and an
  /// interest the other user already sent us offers "Accept" rather than a
  /// duplicate "Send Interest".
  Widget _interestAction(ProfileModel profile) {
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              // Interest is accepted → contact is unlocked. Reveal it straight
              // from the (readable) profile document — no connection/gated read.
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
                const Text(
                  'Couldn\'t load this profile right now. Please try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _reloadProfile,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
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
            return const Center(child: Text('Profile not found'));
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
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => _reportProfile(profile),
              tooltip: 'Report',
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                profile.photos.isNotEmpty
                    ? NetworkPhoto(
                        url: profile.photos[_photoIndex],
                        fit: BoxFit.cover,
                        fallbackIconSize: 100,
                        showLoadingSpinner: true,
                      )
                    : Container(
                        color: AppColors.primary.withOpacity(0.3),
                        child: const Icon(Icons.person, size: 100, color: Colors.white)),
                // Photo dots
                if (profile.photos.length > 1)
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        profile.photos.length,
                        (i) => GestureDetector(
                          onTap: () => setState(() => _photoIndex = i),
                          child: Container(
                            width: _photoIndex == i ? 20 : 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: _photoIndex == i ? Colors.white : Colors.white54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.name, style: AppTextStyles.heading1),
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
                  _InfoItem(Icons.payments_outlined, context.l10n.annualIncome,
                      profile.annualIncome),
                  _InfoItem(Icons.place_outlined, context.l10n.location,
                      [profile.city, profile.state].where((s) => s.trim().isNotEmpty).join(', ')),
                  _InfoItem(Icons.translate, context.l10n.motherTongue,
                      context.localizeValue(profile.motherTongue)),
                  _InfoItem(Icons.accessibility_new, 'Physical Status',
                      context.localizeValue(profile.physicalStatus)),
                  _InfoItem(Icons.church_outlined, context.l10n.religion,
                      context.localizeValue(profile.religion)),
                  _InfoItem(Icons.people_outline, context.l10n.caste,
                      profile.caste ?? ''),
                  _InfoItem(Icons.groups_2_outlined, context.l10n.subCaste,
                      profile.subCaste ?? ''),
                  _InfoItem(Icons.account_balance_outlined, 'Gothram',
                      profile.gothram),
                  _InfoItem(Icons.auto_awesome_outlined, 'Kuladeivam',
                      profile.kuladeivam),
                  _InfoItem(Icons.badge_outlined, 'Employment Type',
                      context.localizeValue(profile.employmentType)),
                  _InfoItem(
                      Icons.business_outlined, 'Company', profile.companyName ?? ''),
                  _InfoItem(Icons.account_balance, 'College',
                      profile.collegeName ?? ''),
                  _InfoItem(Icons.location_city_outlined, 'Native Place',
                      profile.nativePlace ?? ''),
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

  /// Lifestyle section — rendered only when at least one habit/field is set.
  List<Widget> _lifestyleSection(LifestyleDetails l) {
    final items = <_InfoItem>[
      _InfoItem(Icons.restaurant_outlined, 'Eating Habit',
          context.localizeValue(l.eatingHabit)),
      _InfoItem(Icons.smoke_free, 'Smoking',
          context.localizeValue(l.smokingHabit)),
      _InfoItem(Icons.no_drinks_outlined, 'Drinking',
          context.localizeValue(l.drinkingHabit)),
      _InfoItem(Icons.sports_esports_outlined, 'Hobbies', l.hobbies),
      _InfoItem(Icons.interests_outlined, 'Interests', l.interests),
      _InfoItem(Icons.translate, 'Languages Known',
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
      _InfoItem(
          Icons.work_history_outlined, "Father's Occupation", f.fatherOccupation),
      _InfoItem(Icons.woman_outlined, context.l10n.mother, f.motherName),
      _InfoItem(
          Icons.work_history_outlined, "Mother's Occupation", f.motherOccupation),
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
        Text('About Family', style: AppTextStyles.heading3),
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

    // Age (always).
    rows.add(_PrefCmp(
      'Age',
      '${p.minAge} - ${p.maxAge} yrs',
      c.age > 0 ? '${c.age} yrs' : '—',
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
      'Height',
      '${p.minHeight} - ${p.maxHeight}',
      dash(c.height),
      hMatched,
    ));

    // Education.
    if (p.education.isNotEmpty) {
      rows.add(_PrefCmp(
        'Education',
        p.education.join(', '),
        dash(c.education),
        p.education.any((e) => eq(c.education, e)),
      ));
    }

    // Profession (occupation).
    if (p.occupation.isNotEmpty) {
      rows.add(_PrefCmp(
        'Profession',
        p.occupation.join(', '),
        dash(c.occupation),
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
      rows.add(_PrefCmp('Location', pref, dash(theirs), ok));
    }

    // Religion.
    if (set(p.religion)) {
      rows.add(_PrefCmp(
          'Religion', p.religion, dash(c.religion), eq(c.religion, p.religion)));
    }

    // Caste.
    if (set(p.caste)) {
      rows.add(_PrefCmp(
          'Caste', p.caste!, dash(c.caste ?? ''), eq(c.caste ?? '', p.caste)));
    }

    return rows;
  }

  /// Horoscope section with privacy rules:
  ///  • The OWNER sees the full generated horoscope (Rasi, Nakshatra, Lagnam,
  ///    birth details, doshams).
  ///  • OTHER users see only Rasi + Nakshatra + a "Horoscope Available"
  ///    indicator, and can tap "Consult Astrologer" for detailed matching.
  Widget _horoscopeSection(ProfileModel profile) {
    final myUid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
    final isOwner = myUid != null && myUid == profile.userId;
    final h = profile.horoscopeDetails;

    if (isOwner) {
      return _buildInfoSection(context.l10n.horoscopeDetails, [
        _InfoItem(Icons.stars, context.l10n.rasi, h.rasi),
        _InfoItem(Icons.star_border, context.l10n.nakshatra, h.nakshatra),
        _InfoItem(Icons.wb_twilight, context.l10n.lagnam, h.lagnam),
        _InfoItem(Icons.place_outlined, context.l10n.birthPlace, h.birthPlace),
        _InfoItem(Icons.access_time, context.l10n.birthTime, h.birthTime),
        _InfoItem(Icons.brightness_5_outlined, 'Chevvai Dosham', h.dosham),
        _InfoItem(Icons.brightness_5_outlined, 'Rahu / Kethu Dosham',
            h.rahuKethuDosham),
        _InfoItem(Icons.brightness_5_outlined, 'Kalasarpa Dosham',
            h.kalasarpaDosham),
      ]);
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
      ],
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
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not open chat. Please try again.')));
    }
  }

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
