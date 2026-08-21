import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/value_l10n.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/compatibility_report_model.dart';
import '../../models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/block_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/interest_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/auto_fit_label.dart';
import '../../widgets/export/download_saved_dialog.dart';
import '../../widgets/export/profile_form_export.dart';
import '../../widgets/common/face_centered_photo.dart';
import '../../widgets/common/fullscreen_photo_viewer.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/horoscope_documents_view.dart';
import '../../widgets/interest/interest_sent_overlay.dart';
import '../../widgets/profile/verification_tick.dart';
import '../../widgets/common/skeletons.dart';
import '../../widgets/interest/match_celebration.dart';
import '../../widgets/interest/pending_interest_card.dart';
import '../../widgets/profile/contact_details_dialog.dart';
import '../report/compatibility_report_screen.dart';

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

  /// True while the profile form is being captured and written to the phone,
  /// so the Download button can show progress instead of looking unresponsive.
  bool _downloading = false;

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

  /// True while a send is IN FLIGHT — a second tap is dropped, so a double tap
  /// can never write two interests.
  bool _sendingInterest = false;

  Future<void> _sendInterest(ProfileModel profile) async {
    if (_sendingInterest) return; // duplicate tap
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
    _sendingInterest = true;
    // Sending interests is FREE and unlimited — no plan gate.
    try {
      await ref.read(interestNotifierProvider.notifier).sendInterest(
            senderId: userId,
            receiverId: profile.userId,
            senderProfileId: myProfile.id,
            receiverProfileId: profile.id,
          );
      if (!mounted) return;
      final st = ref.read(interestNotifierProvider);
      if (st.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(interestErrorText(
                st.error, context.l10n.couldNotSendInterest))));
        return;
      }
      // Only after the backend confirms the write.
      await showInterestSentOverlay(context);
    } finally {
      _sendingInterest = false;
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

  /// The ONLY entry to contact information (spec §2): a popup that enforces
  /// the accepted / public / private rules itself and always fetches the
  /// LATEST saved contact record — nothing is ever rendered inline.
  void _showContact(ProfileModel profile) {
    showContactDetailsDialog(context, profile: profile);
  }

  /// Downloads this member's profile as the branded Tamil registration form,
  /// as a PDF or as page images.
  ///
  /// **Only ever reachable after a mutually-accepted interest**: the entry
  /// point lives inside [_connectedActionsCard], which nothing but the
  /// `accepted` branch of [_statusInterestAction] renders. The check is
  /// re-asserted here so a stale widget can never produce a file, and the
  /// export itself is redacted by the OWNER's privacy switches
  /// ([ProfileFormExportOptions.forMatch]) — the download can never contain
  /// more than this screen already shows.
  Future<void> _downloadProfile(ProfileModel profile,
      {required bool asPdf}) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    if (ref.read(interestStatusForProfileProvider(profile.id)) !=
        InterestUiStatus.accepted) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.downloadProfileLocked)));
      return;
    }

    // Contact is unlocked by the acceptance, so read the LATEST gated
    // `contacts/{userId}` record rather than the copy embedded in the profile
    // document. A denied/failed read is not fatal — the form then falls back
    // to the embedded contact, exactly like the Contact Details popup.
    ContactDetails? contact;
    try {
      contact =
          await ref.read(profileRepositoryProvider).getContact(profile.userId);
    } catch (e) {
      debugPrint('[ProfileDownload] contact read skipped: $e');
    }
    if (!mounted) return;

    // The capture + PDF encode takes a moment, so the button shows a spinner
    // rather than looking dead.
    setState(() => _downloading = true);
    final options = ProfileFormExportOptions.forMatch(profile);
    final base = profileExportBaseName(profile);
    ExportResult? result;
    try {
      result = asPdf
          ? await exportProfileFormPdf(context,
              profile: profile,
              contact: contact,
              options: options,
              fileName: '$base.pdf')
          : await exportProfileFormImages(context,
              profile: profile,
              contact: contact,
              options: options,
              baseName: base);
    } catch (e) {
      debugPrint('[ProfileDownload] export failed: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }

    // The file is on the phone by now. Only THEN is the confirmation shown,
    // which is also where sharing is offered — the save never depends on it.
    if (!mounted) return;
    if (result == null) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.downloadProfileFailed)));
      return;
    }
    await showDownloadSavedDialog(context, result: result);
  }

  /// Format picker for the connected-member download — PDF or images, the
  /// same two choices the admin export offers.
  Future<void> _chooseDownloadFormat(ProfileModel profile) async {
    final l10n = context.l10n;
    final asPdf = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(l10n.downloadProfile,
                style: const TextStyle(
                    fontSize: 16,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(l10n.downloadProfileSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.4, color: Colors.grey[600])),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined,
                  color: AppColors.primary),
              title: Text(l10n.downloadAsPdf),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading:
                  const Icon(Icons.image_outlined, color: AppColors.primary),
              title: Text(l10n.downloadAsImages),
              onTap: () => Navigator.pop(ctx, false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (asPdf == null || !mounted) return;
    await _downloadProfile(profile, asPdf: asPdf);
  }

  Future<void> _acceptInterest(ProfileModel profile, String interestId) async {
    await ref.read(interestNotifierProvider.notifier).acceptInterest(interestId);
    if (!mounted) return;
    if (ref.read(interestNotifierProvider).hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotAcceptInterest)));
      return;
    }
    // Premium match celebration with a one-tap jump into the new chat.
    await showMatchCelebration(
      context,
      name: profile.fullName,
      photoUrl: profile.hidesPhoto ? '' : (profile.profilePhotoUrl ?? ''),
      onStartChat: () => _openChat(profile),
    );
  }

  Future<void> _rejectInterest(ProfileModel profile, String interestId) async {
    final l10n = context.l10n;
    // Reject stays available but is guarded by a light confirmation — it
    // notifies the sender and cannot be undone from this screen.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.interestRejectedConfirmTitle),
        content: Text(l10n.interestRejectedConfirmBody(profile.fullName)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: Text(l10n.reject)),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(interestNotifierProvider.notifier).rejectInterest(interestId);
    if (mounted) {
      final failed = ref.read(interestNotifierProvider).hasError;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failed
              ? context.l10n.couldNotAcceptInterest
              : context.l10n.interestDeclined)));
    }
  }

  /// The bottom action(s). Contact never appears inline anywhere on this page
  /// (spec §2) — every state goes through the Contact Details popup, which
  /// enforces the accepted / public / private rules itself.
  Widget _interestAction(ProfileModel profile) => _statusInterestAction(profile);

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
      if (pending == null) return const SizedBox.shrink();
      // The receiver of a pending interest NEVER sees "Send Interest" — only
      // this premium Accept / Reject card (duplicate-interest prevention).
      return PendingInterestCard(
        name: profile.fullName,
        onAccept: () => _acceptInterest(profile, pending.id),
        onReject: () => _rejectInterest(profile, pending.id),
      );
    }

    if (accepted) return _connectedActionsCard(profile);

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

  /// The bottom card AFTER both members are connected (spec §5).
  ///
  /// Interest buttons are gone; what replaces them is one premium card:
  ///   • a "You are Connected" banner;
  ///   • **View Contact Details** as the single full-width primary action;
  ///   • the connected actions — **Chat** and **Horoscope Matching** — as two
  ///     equal tiles beneath it.
  ///
  /// None of these exist before acceptance: this whole card only ever renders
  /// in the accepted branch of [_statusInterestAction].
  Widget _connectedActionsCard(ProfileModel profile) {
    final l10n = context.l10n;
    // The horoscope request (if any) decides what the Horoscope Matching tile
    // does — book, wait, or open the finished report.
    final reqAsync = ref.watch(compatRequestForPairProvider(profile.id));
    final req = reqAsync.valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Connected banner ──
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.verified_user_outlined,
                        size: 22, color: AppColors.success),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.connectedTitle,
                            style: const TextStyle(
                                fontSize: 15,
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                color: AppColors.success)),
                        const SizedBox(height: 2),
                        Text(l10n.connectedBody,
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: Colors.grey[700])),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // ── Primary action: View Contact Details ──
              // The popup itself enforces what may be shown (accepted /
              // public / private / hidden-by-owner) — spec §2.
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _showContact(profile),
                  icon: const Icon(Icons.contact_phone_outlined, size: 21),
                  label: Text(l10n.viewContactDetails,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15.5,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                    elevation: 2,
                    shadowColor: AppColors.primary.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(l10n.connectedActionsTitle.toUpperCase(),
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: Colors.grey[500])),
              const SizedBox(height: 10),
              // ── Connected actions: two equal tiles ──
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _connectedActionTile(
                        icon: Icons.chat_bubble_outline,
                        color: AppColors.gold,
                        label: l10n.chat,
                        // The auto-created thread is idempotent, so this always
                        // opens the SAME conversation as the Chats tab.
                        onTap: () => _openChat(profile),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _horoscopeReportTile(profile, req, reqAsync.isLoading),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // ── Download this member's profile ──
              // Lives inside the connected card ON PURPOSE: this card only
              // exists in the accepted branch, so the download is structurally
              // impossible before the interest is accepted.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _downloading
                      ? null
                      : () => _chooseDownloadFormat(profile),
                  icon: _downloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary))
                      : const Icon(Icons.download_outlined, size: 19),
                  label: Text(
                      _downloading
                          ? l10n.savingLabel
                          : l10n.downloadProfile,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Status detail for an EXISTING horoscope request (under analysis /
        // ready). With no request yet, the tile above is the entry point and
        // this stays out of the way.
        if (req != null) ...[
          const SizedBox(height: 12),
          _astroConsultCard(profile),
        ],
      ],
    );
  }

  /// One square-ish connected-action tile — icon bubble over a centred label,
  /// sized purely by the row so both tiles are always identical.
  Widget _connectedActionTile({
    required IconData icon,
    required Color color,
    required String label,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Material(
      color: color.withValues(alpha: enabled ? 0.08 : 0.05),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: color.withValues(alpha: enabled ? 0.35 : 0.18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 24,
                  color: enabled ? color : color.withValues(alpha: 0.5)),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: enabled ? AppColors.textPrimary : Colors.grey,
                ),
              ),
              if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The Horoscope Report tile — one control, three states, driven by the
  /// real request document so it can never offer a second booking for a pair
  /// that already has one (spec §12, one request per partner). It opens the ONE
  /// Horoscope Compatibility Report page directly; there is no intermediate
  /// informational screen in between.
  Widget _horoscopeReportTile(
      ProfileModel profile, AstrologerRequestModel? req, bool loading) {
    final l10n = context.l10n;
    if (loading) {
      return _connectedActionTile(
        icon: Icons.auto_awesome_outlined,
        color: AppColors.primary,
        label: l10n.horoscopeReportShort,
      );
    }
    if (req == null) {
      return _connectedActionTile(
        icon: Icons.auto_awesome_outlined,
        color: AppColors.primary,
        label: l10n.horoscopeReportShort,
        onTap: () => context.push('/horoscope-report/${profile.userId}'),
      );
    }
    if (req.status == AstrologerRequestStatus.completed) {
      return _connectedActionTile(
        icon: Icons.task_alt,
        color: AppColors.success,
        label: l10n.viewHoroscopeReport,
        onTap: () => _viewCompatReport(req),
      );
    }
    // A paid report is under analysis. The FREE basic porutham result stays
    // available regardless, so the tile still opens the report page — which
    // shows the pending status in place of the paid CTA.
    return _connectedActionTile(
      icon: Icons.hourglass_top,
      color: AppColors.warning,
      label: l10n.horoscopeReportShort,
      subtitle: l10n.reportUnderAnalysisTitle,
      onTap: () => context.push('/horoscope-report/${profile.userId}'),
    );
  }

  /// Premium Astrology Consultation card — rendered ONLY inside the accepted
  /// branch (spec §6). One request per partner profile (spec §12): before any
  /// request → the booking CTA; while pending → a status card; completed →
  /// "View Horoscope Report". The report is never generated automatically and
  /// no horoscope data leaves the profile before an explicit booking.
  Widget _astroConsultCard(ProfileModel profile) {
    final l10n = context.l10n;
    final reqAsync = ref.watch(compatRequestForPairProvider(profile.id));
    final req = reqAsync.valueOrNull;
    // While the request stream is still connecting, show nothing rather than
    // flashing the "book now" CTA at a member who already paid.
    if (reqAsync.isLoading) return const SizedBox.shrink();

    final Widget inner;
    if (req == null) {
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  gradient: AppColors.goldGradient,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.auto_awesome,
                    size: 22, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(l10n.astroConsultTitle,
                    style: const TextStyle(
                        fontSize: 15,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(l10n.astroConsultBody,
              style: TextStyle(
                  fontSize: 12.5, height: 1.45, color: Colors.grey[700])),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () =>
                  context.push('/horoscope-report/${profile.userId}'),
              icon: const Icon(Icons.description_outlined, size: 19),
              label: Text(l10n.getHoroscopeCompatibilityReport,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      );
    } else if (req.status == AstrologerRequestStatus.completed) {
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.task_alt, color: AppColors.success, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l10n.reportReadyMsg,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _viewCompatReport(req),
              icon: const Icon(Icons.visibility_outlined, size: 19),
              label: Text(l10n.viewHoroscopeReport),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      );
    } else {
      inner = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top, color: AppColors.warning, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.reportUnderAnalysisTitle,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(l10n.reportUnderAnalysisBody,
                    style: TextStyle(
                        fontSize: 12, height: 1.4, color: Colors.grey[700])),
              ],
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF8EC), Color(0xFFFDEFD2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold.withOpacity(0.45)),
        ),
        child: inner,
      ),
    );
  }

  /// Opens the completed report — the structured A4 compatibility report when
  /// one was submitted, otherwise the Reports tab (legacy text/file reports).
  void _viewCompatReport(AstrologerRequestModel req) {
    final compat = CompatibilityReport.tryFrom(req.compatReport);
    if (compat != null && compat.isSubmitted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            CompatibilityReportScreen(requestId: req.id, request: req),
      ));
      return;
    }
    ref.read(homeTabIndexProvider.notifier).state = kReportsTabIndex;
    context.go('/home');
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
        // Skeleton in the real page shape — photo header + text lines — so
        // loading never means a bare spinner (spec: skeleton loaders).
        loading: () => SafeArea(
          child: SkeletonShimmer(
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                SkeletonBox(height: 300, radius: 0),
                Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLine(width: 180, height: 20),
                      SizedBox(height: 10),
                      SkeletonLine(width: 120, height: 13),
                      SizedBox(height: 24),
                      SkeletonBox(height: 220, radius: 16),
                      SizedBox(height: 20),
                      SkeletonBox(height: 160, radius: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(profile.displayName(context.isTamil),
                          style: AppTextStyles.heading1),
                    ),
                    // Verification status is ALWAYS visible at the top of the
                    // profile, right beside the name: a green tick when the
                    // admin has verified it, a dark/inactive tick when not.
                    const SizedBox(width: 8),
                    VerificationTick.forProfile(profile, size: 22),
                  ],
                ),
                // Both names are shown when they differ (§14) — the header
                // uses the app language, the sub-line carries the other one.
                if (profile.fullNameTamil.trim().isNotEmpty &&
                    profile.fullName.trim().isNotEmpty &&
                    profile.fullNameTamil.trim() != profile.fullName.trim())
                  Text(
                    context.isTamil ? profile.fullName : profile.fullNameTamil,
                    style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                Text(
                  // Each part is localized on its own so the city and the
                  // state both read in Tamil while storage stays English.
                  '${context.l10n.ageYears(profile.age)} • ${[
                    profile.city,
                    profile.state
                  ].map(context.localizeValue).where((s) => s.trim().isNotEmpty).join(', ')}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                // ── Premium information grouping (spec §4): the old 26-row
                // monolith is split into Basic / Religious / Professional so
                // a reader can scan straight to what they care about. Labels
                // via l10n, stored values via the EN→TA value map. ───────────
                _buildInfoSection(context.l10n.basicDetails, [
                  _InfoItem(Icons.person_outline, context.l10n.fullName,
                      profile.displayName(context.isTamil)),
                  _InfoItem(Icons.wc_outlined, context.l10n.gender,
                      context.localizeValue(profile.gender)),
                  _InfoItem(Icons.cake_outlined, context.l10n.age,
                      '${profile.age} ${context.l10n.years}'),
                  // Date of Birth — entered in the wizard's Basic Details step
                  // and now surfaced here like every other field.
                  _InfoItem(Icons.event_outlined, context.l10n.dateOfBirth,
                      _formatDate(profile.dateOfBirth)),
                  _InfoItem(Icons.height, context.l10n.height, profile.height),
                  _InfoItem(Icons.monitor_weight_outlined, context.l10n.weight,
                      profile.weight),
                  _InfoItem(Icons.wc, context.l10n.maritalStatus,
                      context.localizeValue(profile.maritalStatus)),
                  _InfoItem(
                      Icons.child_care_outlined,
                      context.l10n.childrenCountLabel,
                      profile.childrenCount > 0
                          ? '${profile.childrenCount}'
                          : ''),
                  _InfoItem(Icons.accessibility_new, context.l10n.physicalStatus,
                      context.localizeValue(profile.physicalStatus)),
                  _InfoItem(Icons.translate, context.l10n.motherTongue,
                      context.localizeValue(profile.motherTongue)),
                  _InfoItem(
                      Icons.place_outlined,
                      context.l10n.location,
                      [profile.city, profile.state]
                          .map(context.localizeValue)
                          .where((s) => s.trim().isNotEmpty)
                          .join(', ')),
                  _InfoItem(
                      Icons.location_city_outlined,
                      context.l10n.nativePlace,
                      context.localizeValue(profile.nativePlace ?? '')),
                  _InfoItem(Icons.flag_outlined, context.l10n.citizenship,
                      context.localizeValue(profile.citizenship ?? '')),
                ], icon: Icons.badge_outlined),
                const SizedBox(height: 20),
                _buildInfoSection(context.l10n.religiousDetails, [
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
                ], icon: Icons.temple_hindu_outlined),
                const SizedBox(height: 20),
                _buildInfoSection(context.l10n.professionalDetails, [
                  // Education Level → Course/Degree and Employment Status →
                  // Sector → Occupation (§13). The level/status/sector are
                  // localized; degree + occupation titles stay English (§9).
                  _InfoItem(Icons.school_outlined, context.l10n.education,
                      profile.educationDisplay(context.localizeValue)),
                  _InfoItem(Icons.school, context.l10n.courseDegree,
                      profile.courseDegree ?? ''),
                  _InfoItem(Icons.account_balance, context.l10n.collegeName,
                      profile.collegeName ?? ''),
                  _InfoItem(Icons.badge_outlined, context.l10n.employmentType,
                      context.localizeValue(profile.employmentType)),
                  _InfoItem(Icons.work_outline, context.l10n.profession,
                      profile.occupationDisplay(context.localizeValue)),
                  _InfoItem(Icons.business_outlined, context.l10n.companyName,
                      profile.companyName ?? ''),
                  _InfoItem(Icons.place, context.l10n.workLocation,
                      profile.workLocation ?? ''),
                  // Salary is one of the four privacy switches (§16) — hidden
                  // by default and never auto-revealed.
                  _InfoItem(Icons.payments_outlined, context.l10n.annualIncome,
                      hideSalary ? '' : context.localizeValue(profile.annualIncome)),
                ], icon: Icons.work_outline),
                if (profile.about.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(context.l10n.aboutMe, style: AppTextStyles.heading3),
                  const SizedBox(height: 8),
                  Text(profile.about, style: AppTextStyles.bodyMedium),
                ],
                const SizedBox(height: 20),
                // ── Horoscope Details ──
                _horoscopeSection(profile),
                const SizedBox(height: 20),
                // ── Lifestyle Details ──
                ..._lifestyleSection(profile.lifestyle),
                // ── Partner Preference (this member's own saved preferences) ──
                ..._partnerPreferenceSection(profile),
                // ── Partner Preference Comparison (viewer's prefs vs this) ──
                ..._partnerPreferenceComparison(profile),
                const SizedBox(height: 20),
                // ── Contact Details ──
                // Removed ENTIRELY before the interest is accepted (spec §3):
                // no heading, no card, no button, nothing that hints a phone or
                // e-mail exists. Only the owner, a connected member, or a
                // member whose owner published their contact ever sees it.
                //
                // NOT rendered once the interest is accepted: the connected
                // card below already leads with "View Contact Details", and
                // showing both put the same heading and the same button on the
                // page twice, opening the identical dialog.
                if (isOwner ||
                    (profile.isContactPublic &&
                        ref.watch(
                                interestStatusForProfileProvider(profile.id)) !=
                            InterestUiStatus.accepted)) ...[
                  _contactSection(profile),
                  const SizedBox(height: 32),
                ],
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
      // Tapping always opens the ORIGINAL, uncropped image — the face-centred
      // crop below only affects the header thumbnail.
      onTap: () => FullScreenPhotoViewer.open(context, url),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FaceCenteredPhoto(
            url: url,
            fit: BoxFit.cover,
            fallbackAlignment: Alignment.topCenter,
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

  String _formatDate(DateTime date) => DateFormat('dd MMM yyyy').format(date);

  /// THIS member's own saved Partner Preferences — every value they entered in
  /// the wizard's Partner Preference step, rendered dynamically (a preference
  /// left unset is simply omitted, never shown as a placeholder).
  ///
  /// Distinct from [_partnerPreferenceComparison] below, which compares the
  /// VIEWER's preferences against this profile.
  List<Widget> _partnerPreferenceSection(ProfileModel profile) {
    final p = profile.partnerPreferences;
    final l10n = context.l10n;

    // 'Any' is the "no preference" sentinel — treat it as unset.
    String value(String? raw) {
      final v = (raw ?? '').trim();
      if (v.isEmpty || v.toLowerCase() == 'any') return '';
      return context.localizeValue(v);
    }

    String list(List<String> raw) =>
        raw.map(context.localizeValue).where((s) => s.isNotEmpty).join(', ');

    final location = [p.city, p.district, p.state, p.country]
        .map(value)
        .where((s) => s.isNotEmpty)
        .join(', ');

    final items = <_InfoItem>[
      _InfoItem(
          Icons.cake_outlined,
          l10n.preferredAgeRange,
          p.agePreferenceSet
              ? l10n.ageRangeValue(p.minAge, p.maxAge)
              : ''),
      _InfoItem(Icons.height, l10n.preferredHeightRange,
          (p.minHeight.trim().isEmpty && p.maxHeight.trim().isEmpty)
              ? ''
              : l10n.rangeValue(p.minHeight, p.maxHeight)),
      _InfoItem(Icons.school_outlined, l10n.preferredEducation,
          list(p.education)),
      _InfoItem(Icons.work_outline, l10n.preferredOccupation,
          list(p.occupation)),
      _InfoItem(Icons.payments_outlined, l10n.preferredIncome, value(p.income)),
      _InfoItem(Icons.place_outlined, l10n.preferredLocation, location),
      _InfoItem(Icons.wc, l10n.maritalStatus, value(p.maritalStatus)),
      _InfoItem(Icons.church_outlined, l10n.religion, value(p.religion)),
      _InfoItem(Icons.people_outline, l10n.caste, value(p.caste)),
      _InfoItem(Icons.groups_2_outlined, l10n.subCaste, value(p.subCaste)),
      _InfoItem(Icons.translate, l10n.motherTongue, value(p.motherTongue)),
      _InfoItem(Icons.accessibility_new, l10n.physicalStatus,
          value(p.physicalStatus)),
      _InfoItem(Icons.badge_outlined, l10n.employmentType,
          value(p.employmentType)),
      _InfoItem(Icons.stars, l10n.rasi, value(p.rasi)),
      _InfoItem(Icons.star_border, l10n.nakshatra, value(p.nakshatra)),
      _InfoItem(Icons.brightness_5_outlined, l10n.chevvaiDosham,
          value(p.chevvaiDosham)),
      _InfoItem(Icons.restaurant_outlined, l10n.eatingHabit,
          value(p.eatingHabit)),
      _InfoItem(Icons.smoke_free, l10n.smokingHabit, value(p.smokingHabit)),
      _InfoItem(
          Icons.no_drinks_outlined, l10n.drinkingHabit, value(p.drinkingHabit)),
    ];
    if (items.every((i) => i.value.trim().isEmpty)) return const [];
    return [
      _buildInfoSection(l10n.partnerPreferences, items),
      const SizedBox(height: 20),
    ];
  }

  /// Contact Details entry.
  ///
  /// NOTHING contact-related exists on this page until the interest is
  /// accepted: no phone, no e-mail, no button, no card, not even the section
  /// heading. [_buildProfileView] therefore only calls this once the viewer is
  /// entitled — the owner, a connected (accepted) member, or a member whose
  /// owner explicitly published their contact. Even then the values are never
  /// rendered inline: the button opens the popup, which re-checks access
  /// itself and always fetches the LATEST saved `contacts/{userId}` record.
  Widget _contactSection(ProfileModel profile) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.contactDetails, icon: Icons.contact_phone_outlined),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.contactDetailsFromProfile,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.4, color: Colors.grey[600])),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showContact(profile),
                  icon: const Icon(Icons.contact_phone_outlined, size: 19),
                  label: Text(l10n.contactDetails),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
          // Every horoscope value entered during profile creation.
          _buildInfoSection(context.l10n.horoscopeDetails, [
            _InfoItem(Icons.stars, context.l10n.rasi, h.rasi),
            _InfoItem(Icons.star_border, context.l10n.nakshatra, h.nakshatra),
            _InfoItem(Icons.wb_twilight, context.l10n.lagnam, h.lagnam),
            _InfoItem(
                Icons.place_outlined, context.l10n.birthPlace, h.birthPlace),
            _InfoItem(Icons.access_time, context.l10n.birthTime, h.birthTime),
            _InfoItem(Icons.nightlight_outlined, context.l10n.moonSign,
                context.localizeValue(h.moonSign)),
            _InfoItem(Icons.wb_sunny_outlined, context.l10n.sunSign,
                context.localizeValue(h.sunSign)),
            _InfoItem(Icons.timelapse_outlined, context.l10n.dasaBalance,
                h.dasaBalance),
            _InfoItem(Icons.self_improvement_outlined, context.l10n.yogam,
                context.localizeValue(h.yogam)),
            _InfoItem(Icons.change_history_outlined, context.l10n.karanam,
                context.localizeValue(h.karanam)),
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
              // No "Consult Astrologer" button here (spec §5): astrology
              // consultation is offered ONLY after a mutually-accepted
              // interest, via the consultation card — horoscopes are never
              // shared automatically.
              Text(
                context.l10n.horoscopePrivateNote,
                style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
              ),
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

  /// One titled information card: a tinted icon bubble beside the section
  /// title, then a white card of label/value rows — the premium section idiom
  /// used by every group on this page (spec §4).
  Widget _buildInfoSection(String title, List<_InfoItem> items,
      {IconData? icon}) {
    final rows = items.where((item) => item.value.trim().isNotEmpty).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title, icon: icon),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: Colors.grey[200]),
                _infoRow(rows[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Section heading with an optional tinted icon bubble.
  Widget _sectionTitle(String title, {IconData? icon}) => Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(title, style: AppTextStyles.heading3)),
        ],
      );

  /// One label/value row.
  ///
  /// The previous `ListTile` put the value in `trailing`, which has no width
  /// budget — a long occupation or education value collided with the label and
  /// broke the layout. Here the LABEL takes a fixed share and never splits (it
  /// shrinks slightly instead), while the VALUE takes the rest and wraps freely
  /// over as many lines as it needs. Same treatment in every section.
  Widget _infoRow(_InfoItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(item.icon, size: 19, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: AutoFitLabel(
              item.label,
              maxLines: 2,
              minFontSize: 9,
              textAlign: TextAlign.start,
              style: const TextStyle(
                  fontSize: 12, height: 1.25, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 5,
            child: Text(
              item.value,
              softWrap: true,
              textAlign: TextAlign.end,
              style: const TextStyle(
                  fontSize: 13.5, height: 1.3, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
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
