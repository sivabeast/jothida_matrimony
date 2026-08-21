import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/root_navigator.dart';
import '../../widgets/common/create_profile_sheet.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/value_l10n.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/compatibility_report_model.dart';
import '../../models/interest_model.dart';
import '../../models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/interest_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/profile_provider.dart';
import '../report/compatibility_report_screen.dart';
import '../../widgets/common/network_photo.dart';
import '../../widgets/interest/match_celebration.dart';

/// Interest Management Center — replaces the old chat/messages page.
///
/// Four MUTUALLY-EXCLUSIVE tabs over the Firestore `interests` collection
/// (a profile can only ever appear under its interest's current status):
///  • Received  — PENDING interests others sent me (Accept / Reject)
///  • Sent      — PENDING interests I sent (Withdraw)
///  • Accepted  — mutually accepted (View Profile / Horoscope Report)
///  • Rejected  — declined history
class InterestsCenterScreen extends ConsumerStatefulWidget {
  /// Initial tab to open: 0 Received · 1 Sent · 2 Accepted · 3 Rejected.
  final int initialTab;

  /// When true the screen provides its own Scaffold + AppBar (pushed as a route,
  /// e.g. from the side menu's "Interests Sent / Received"). When false it is
  /// rendered inline as the Home shell's Interests tab.
  final bool standalone;

  /// UID of the counterpart to scroll to and briefly highlight in the initial
  /// tab — set when arriving from a notification so the user immediately sees
  /// WHICH profile triggered it.
  final String? highlightUid;

  const InterestsCenterScreen({
    super.key,
    this.initialTab = 0,
    this.standalone = false,
    this.highlightUid,
  });

  @override
  ConsumerState<InterestsCenterScreen> createState() =>
      _InterestsCenterScreenState();
}

class _InterestsCenterScreenState extends ConsumerState<InterestsCenterScreen>
    with SingleTickerProviderStateMixin {
  static const int _acceptedTab = 2;

  late final TabController _tab = TabController(
      length: 4, vsync: this, initialIndex: widget.initialTab.clamp(0, 3));

  /// Consumed once — the first time the target tab renders its list.
  String? _pendingHighlight;

  /// Which tab [_pendingHighlight] belongs to. Starts as the tab the screen was
  /// opened on and moves to Accepted after an interest is accepted here.
  late int _highlightTab = widget.initialTab.clamp(0, 3);

  @override
  void initState() {
    super.initState();
    _pendingHighlight = widget.highlightUid?.trim().isEmpty ?? true
        ? null
        : widget.highlightUid!.trim();
  }

  /// Called by a Received card the moment an interest has been SUCCESSFULLY
  /// accepted (spec §14): switch to the Accepted tab and flag the just-accepted
  /// member so the list scrolls to them and flashes their card. The accepted
  /// list is driven by the same live Firestore streams, so the profile is
  /// already there — no extra fetch and no duplicate interest record.
  void _goToAccepted(String otherUid) {
    if (!mounted) return;
    setState(() {
      _highlightTab = _acceptedTab;
      _pendingHighlight = otherUid.trim().isEmpty ? null : otherUid.trim();
    });
    _tab.animateTo(_acceptedTab);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid ?? '';
    final sentAsync = ref.watch(sentInterestsProvider);
    final receivedAsync = ref.watch(receivedInterestsProvider);

    final sent = sentAsync.valueOrNull ?? const <InterestModel>[];
    final received = receivedAsync.valueOrNull ?? const <InterestModel>[];
    final loading = sentAsync.isLoading || receivedAsync.isLoading;
    final hasError = sentAsync.hasError || receivedAsync.hasError;

    // Tab contents — STRICTLY status-partitioned so no profile can ever appear
    // under two tabs at once:
    //  • Received = pending interests sent TO me;
    //  • Sent     = pending interests I sent (an accepted one lives ONLY in
    //    Accepted, a declined one ONLY in Rejected);
    //  • Accepted/Rejected merge BOTH directions and de-duplicate by the OTHER
    //    user's id so each profile is shown exactly once.
    final receivedPending = _sorted(received.where((i) => i.isPending));
    final sentPending = _sorted(sent.where((i) => i.isPending));
    final accepted = _dedupByCounterpart(
        _sorted([...sent, ...received].where((i) => i.isAccepted)), myUid);
    final rejected = _dedupByCounterpart(
        _sorted([...sent, ...received].where((i) => i.isRejected)), myUid);

    final l10n = context.l10n;
    final content = Column(
      children: [
        // Inline (Home-tab) heading. When shown as a standalone route the AppBar
        // title already names the page, so this in-body title is dropped.
        if (!widget.standalone)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            alignment: Alignment.centerLeft,
            child: Text(l10n.interests,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 18)),
          ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: TabBar(
            controller: _tab,
            // Scrollable pill tabs → each tab auto-sizes to its Tamil label so
            // the text always shows at full size and never truncates; the row
            // scrolls horizontally if the four labels don't fit the width.
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.primary,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(24),
            ),
            dividerColor: Colors.transparent,
            labelPadding: const EdgeInsets.symmetric(horizontal: 5),
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            tabs: [
              _countTab(l10n.received, receivedPending.length),
              _countTab(l10n.sent, sentPending.length),
              _countTab(l10n.accepted, accepted.length),
              _countTab(l10n.rejected, rejected.length),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _InterestList(
                  items: receivedPending,
                  mode: _CardMode.received,
                  myUid: myUid,
                  loading: loading,
                  hasError: hasError,
                  emptyText: l10n.noReceivedInterests,
                  highlightUid: _highlightFor(0),
                  onHighlightShown: _clearHighlight,
                  onAccepted: _goToAccepted),
              _InterestList(
                  items: sentPending,
                  mode: _CardMode.sent,
                  myUid: myUid,
                  loading: loading,
                  hasError: hasError,
                  emptyText: l10n.noSentInterests,
                  highlightUid: _highlightFor(1),
                  onHighlightShown: _clearHighlight),
              _InterestList(
                  items: accepted,
                  mode: _CardMode.accepted,
                  myUid: myUid,
                  loading: loading,
                  hasError: hasError,
                  emptyText: l10n.noAcceptedInterests,
                  highlightUid: _highlightFor(2),
                  onHighlightShown: _clearHighlight),
              _InterestList(
                  items: rejected,
                  mode: _CardMode.rejected,
                  myUid: myUid,
                  loading: loading,
                  hasError: hasError,
                  emptyText: l10n.noRejectedInterests,
                  highlightUid: _highlightFor(3),
                  onHighlightShown: _clearHighlight),
            ],
          ),
        ),
      ],
    );

    if (widget.standalone) {
      return Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: Text(l10n.interests),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: content,
      );
    }
    return content;
  }

  /// The highlight target for tab [index] — only the tab currently holding the
  /// highlight receives it, and only until it has been shown once.
  String? _highlightFor(int index) =>
      index == _highlightTab ? _pendingHighlight : null;

  void _clearHighlight() {
    if (_pendingHighlight == null) return;
    // Post-frame: the callback fires during the list's first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _pendingHighlight = null);
    });
  }

  /// A fixed-width tab whose "Label (count)" text shrinks to fit rather than
  /// overflowing or forcing horizontal scroll on narrow screens.
  Widget _countTab(String label, int count) => Tab(
        height: 40,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('$label ($count)', maxLines: 1),
        ),
      );

  List<InterestModel> _sorted(Iterable<InterestModel> it) {
    final list = it.toList()..sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return list;
  }

  /// Keeps only the first interest per counterpart (the other user's id), so a
  /// profile never appears more than once. [items] should already be sorted
  /// newest-first so the most recent interest is the one kept.
  List<InterestModel> _dedupByCounterpart(
      List<InterestModel> items, String myUid) {
    final seen = <String>{};
    final out = <InterestModel>[];
    for (final i in items) {
      final otherId = i.senderId == myUid ? i.receiverId : i.senderId;
      if (otherId.isEmpty) continue;
      if (seen.add(otherId)) out.add(i);
    }
    return out;
  }
}

enum _CardMode { received, sent, accepted, rejected }

class _InterestList extends StatefulWidget {
  final List<InterestModel> items;
  final _CardMode mode;
  final String myUid;
  final bool loading;
  final bool hasError;
  final String emptyText;

  /// Counterpart UID to scroll to + briefly flash (from a notification tap, or
  /// after an interest was just accepted).
  final String? highlightUid;
  final VoidCallback? onHighlightShown;

  /// Fired with the counterpart's uid once an interest here has been accepted
  /// successfully (Received tab only).
  final ValueChanged<String>? onAccepted;

  const _InterestList({
    required this.items,
    required this.mode,
    required this.myUid,
    required this.loading,
    required this.hasError,
    required this.emptyText,
    this.highlightUid,
    this.onHighlightShown,
    this.onAccepted,
  });

  @override
  State<_InterestList> createState() => _InterestListState();
}

class _InterestListState extends State<_InterestList> {
  final ScrollController _scroll = ScrollController();

  /// The counterpart uid currently being flashed ('' = none).
  String _flashUid = '';
  bool _highlightConsumed = false;

  /// Rough per-card extents used to land the scroll near the target — the
  /// flash animation then makes the exact card unmistakable.
  double get _estimatedExtent => switch (widget.mode) {
        _CardMode.accepted => 400,
        _CardMode.received => 210,
        _ => 190,
      };

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _InterestList old) {
    super.didUpdateWidget(old);
    // A NEW highlight target (e.g. a second interest accepted in this session)
    // must be able to fire again — the consumed flag is per-target.
    if (widget.highlightUid != old.highlightUid && widget.highlightUid != null) {
      _highlightConsumed = false;
    }
  }

  String _counterpartOf(InterestModel i) =>
      i.senderId == widget.myUid ? i.receiverId : i.senderId;

  void _maybeHighlight() {
    final target = widget.highlightUid;
    if (_highlightConsumed || target == null || widget.items.isEmpty) return;
    final index =
        widget.items.indexWhere((i) => _counterpartOf(i) == target);
    if (index < 0) return;
    _highlightConsumed = true;
    widget.onHighlightShown?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_scroll.hasClients && index > 0) {
        final offset = (index * _estimatedExtent)
            .clamp(0.0, _scroll.position.maxScrollExtent);
        await _scroll.animateTo(offset,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic);
      }
      if (!mounted) return;
      setState(() => _flashUid = target);
      Future.delayed(const Duration(milliseconds: 2600), () {
        if (mounted) setState(() => _flashUid = '');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      if (widget.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _EmptyState(
        text: widget.hasError ? context.l10n.couldntLoadInterests : widget.emptyText,
        subtitle: widget.hasError
            ? context.l10n.checkConnectionRetry
            : context.l10n.interestStartHint,
      );
    }
    _maybeHighlight();
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: widget.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _InterestCard(
        interest: widget.items[i],
        mode: widget.mode,
        myUid: widget.myUid,
        highlighted: _flashUid.isNotEmpty &&
            _counterpartOf(widget.items[i]) == _flashUid,
        onAccepted: widget.onAccepted,
      ),
    );
  }
}

class _InterestCard extends ConsumerWidget {
  final InterestModel interest;
  final _CardMode mode;
  final String myUid;

  /// True while this card is being flashed after a notification deep link.
  final bool highlighted;

  /// Notifies the parent (with the counterpart's uid) once this interest has
  /// been accepted successfully, so it can switch to the Accepted tab.
  final ValueChanged<String>? onAccepted;

  const _InterestCard({
    required this.interest,
    required this.mode,
    required this.myUid,
    this.highlighted = false,
    this.onAccepted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amSender = interest.senderId == myUid;
    final otherUserId = amSender ? interest.receiverId : interest.senderId;

    // Resolve the other person's profile by their USER id (UID). The interest's
    // senderId / receiverId always identify the right account, whereas a stored
    // profile-document id can be stale or missing — which is what made "View
    // Profile" fail to load on accepted matches.
    final l10n = context.l10n;
    final profile = ref.watch(profileByUserIdProvider(otherUserId)).valueOrNull;
    final name = profile?.name ?? l10n.member;
    final age = profile?.age ?? 0;
    final location = profile == null
        ? ''
        : [profile.city, profile.state].where((s) => s.trim().isNotEmpty).join(', ');
    final photo = profile?.profilePhotoUrl ?? '';
    // Short profile summary: education · occupation.
    final summary = profile == null
        ? ''
        : [profile.education, profile.occupation]
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .join(' · ');

    // Interest date shown per tab: when it was responded to (accepted/rejected)
    // or when it was originally sent.
    final responded = mode == _CardMode.accepted || mode == _CardMode.rejected;
    final date = responded ? (interest.respondedAt ?? interest.sentAt) : interest.sentAt;
    final dateLabel = mode == _CardMode.accepted
        ? l10n.accepted
        : mode == _CardMode.rejected
            ? l10n.rejected
            : l10n.sent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFFFF6E3) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: highlighted ? AppColors.gold : Colors.grey.shade200,
            width: highlighted ? 2 : 1),
        boxShadow: [
          highlighted
              ? BoxShadow(
                  color: AppColors.gold.withOpacity(0.45),
                  blurRadius: 16,
                  spreadRadius: 2)
              : BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mode == _CardMode.accepted)
            _acceptedHeader(context, profile, name, age)
          else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: NetworkPhoto(url: photo, fallbackIconSize: 26),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(age > 0 ? '$name, $age' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15.5,
                            fontFamily: 'Poppins')),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _meta(Icons.work_outline, summary),
                    ],
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      _meta(Icons.location_on_outlined, location),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _modeBadge(context),
            ],
          ),
          const SizedBox(height: 10),
          // Interest date line.
          Row(
            children: [
              Icon(Icons.schedule, size: 13, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Flexible(
                child: Text('$dateLabel · ${_fmtDate(date)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _actions(context, ref, otherUserId, name, photo),
        ],
      ),
    );
  }

  /// The **Accepted** card header (spec §15): a clean profile card — larger
  /// photo, name + age, then location, education and occupation on their own
  /// lines instead of the compact one-line summary the other tabs use.
  Widget _acceptedHeader(
      BuildContext context, ProfileModel? profile, String name, int age) {
    final l10n = context.l10n;
    final photo = profile?.profilePhotoUrl ?? '';
    // Native place wins over city/state — it is what members recognise.
    final native = (profile?.nativePlace ?? '').trim();
    final location = native.isNotEmpty
        ? context.localizeValue(native)
        : (profile == null
            ? ''
            : [profile.city, profile.state]
                .where((s) => s.trim().isNotEmpty)
                .map(context.localizeValue)
                .join(', '));
    final education = context.localizeValue(profile?.education ?? '');
    final occupation = context.localizeValue(profile?.occupation ?? '');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 84,
            height: 84,
            child: NetworkPhoto(url: photo, fallbackIconSize: 34),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(age > 0 ? '$name, $age' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16.5,
                            fontFamily: 'Poppins')),
                  ),
                  const SizedBox(width: 6),
                  _modeBadge(context),
                ],
              ),
              const SizedBox(height: 6),
              if (location.isNotEmpty) ...[
                _meta(Icons.location_on_outlined, location),
                const SizedBox(height: 3),
              ],
              if (education.isNotEmpty) ...[
                _meta(Icons.school_outlined, education),
                const SizedBox(height: 3),
              ],
              if (occupation.isNotEmpty)
                _meta(Icons.work_outline, occupation),
              if (location.isEmpty && education.isEmpty && occupation.isEmpty)
                _meta(Icons.info_outline, l10n.notSpecified),
            ],
          ),
        ),
      ],
    );
  }

  /// A compact icon + text meta row (summary / location) that ellipsizes long
  /// values gracefully in the card.
  Widget _meta(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 13, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
          ),
        ],
      );

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// The status badge shown top-right of each card (Pending / Accepted /
  /// Rejected), coloured by state.
  Widget _modeBadge(BuildContext context) {
    final l10n = context.l10n;
    switch (mode) {
      case _CardMode.received:
        return _badge(AppColors.warning, l10n.pending, Icons.hourglass_bottom);
      case _CardMode.sent:
        final s = interest.status;
        if (s == 'accepted') {
          return _badge(AppColors.success, l10n.accepted, Icons.verified);
        }
        if (s == 'rejected') {
          return _badge(AppColors.error, l10n.rejected, Icons.cancel_outlined);
        }
        return _badge(AppColors.warning, l10n.pending, Icons.schedule);
      case _CardMode.accepted:
        return _badge(AppColors.success, l10n.accepted, Icons.verified);
      case _CardMode.rejected:
        return _badge(AppColors.error, l10n.rejected, Icons.cancel_outlined);
    }
  }

  Widget _badge(Color color, String label, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  /// Confirms and withdraws (unsends) a pending sent interest. Deletes the doc
  /// via the notifier so it disappears for both users immediately.
  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.withdrawInterest),
        content: Text(l10n.withdrawConfirmMsg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.withdraw),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    await ref
        .read(interestNotifierProvider.notifier)
        .withdrawInterest(interest.id);
    final ctx = context.mounted ? context : rootNavigatorKey.currentContext;
    if (ctx == null) return;
    final failed = container.read(interestNotifierProvider).hasError;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(
        content: Text(
            failed ? ctx.l10n.couldNotSendInterest : l10n.interestWithdrawn)));
  }

  /// Accepts the interest, then plays the premium match celebration with a
  /// one-tap jump into the (auto-created) conversation.
  ///
  /// NOTE on contexts: the accepted card leaves the Received list the moment
  /// the stream flips (often BEFORE the await returns), unmounting this
  /// card's context — the celebration is therefore shown on the ROOT
  /// navigator so it always appears.
  Future<void> _accept(BuildContext context, WidgetRef ref, String otherUserId,
      String name, String photo) async {
    final l10n = context.l10n;
    final notifier = ref.read(interestNotifierProvider.notifier);
    // Read once up-front; ref stays valid via the provider container even if
    // this card's element is disposed mid-await.
    final container = ProviderScope.containerOf(context, listen: false);
    await notifier.acceptInterest(interest.id);
    final rootCtx = rootNavigatorKey.currentContext;
    final ctx = context.mounted ? context : rootCtx;
    if (ctx == null) return;
    if (container.read(interestNotifierProvider).hasError) {
      ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
          SnackBar(content: Text(l10n.couldNotAcceptInterest)));
      return;
    }
    // The acceptance is committed — move the user to the Accepted tab so the
    // profile they just accepted is visible straight away (spec §14). Done
    // BEFORE the celebration so the tab has already switched behind it.
    onAccepted?.call(otherUserId);
    await showMatchCelebration(
      ctx,
      name: name,
      photoUrl: photo,
      onStartChat: () {
        final c = rootNavigatorKey.currentContext;
        if (c != null) _openChatFromRoot(c, container, otherUserId, name, photo);
      },
    );
  }

  /// Opens the conversation via the root context (safe after this card has
  /// been unmounted by the accept).
  Future<void> _openChatFromRoot(BuildContext ctx, ProviderContainer container,
      String otherUserId, String name, String photo) async {
    try {
      final threadId = await container.read(chatControllerProvider).openChatWith(
          otherUid: otherUserId, otherName: name, otherPhoto: photo);
      final c = rootNavigatorKey.currentContext;
      if (c != null && c.mounted) {
        c.push('/chat/$threadId', extra: {'name': name, 'photo': photo});
      }
    } catch (_) {
      final c = rootNavigatorKey.currentContext;
      if (c != null && c.mounted) {
        ScaffoldMessenger.maybeOf(c)?.showSnackBar(
            SnackBar(content: Text(c.l10n.couldNotOpenChatRetry)));
      }
    }
  }

  /// Confirms, then declines the interest (the sender is notified).
  Future<void> _reject(BuildContext context, WidgetRef ref, String name) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.interestRejectedConfirmTitle),
        content: Text(l10n.interestRejectedConfirmBody(name)),
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
    if (confirmed != true || !context.mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    await ref.read(interestNotifierProvider.notifier).rejectInterest(interest.id);
    final ctx = context.mounted ? context : rootNavigatorKey.currentContext;
    if (ctx == null) return;
    final failed = container.read(interestNotifierProvider).hasError;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(
        content:
            Text(failed ? ctx.l10n.couldNotAcceptInterest : l10n.interestDeclined)));
  }

  /// Report action for an accepted match, state-aware per spec §12 (one
  /// request per partner profile — the paid button disappears after the first
  /// request and never comes back).
  ///
  /// Before any request it opens the ONE Horoscope Compatibility Report page
  /// (`/horoscope-report/:uid`) directly — no intermediate informational
  /// screen. That page carries the free basic result, the service details and
  /// the ₹200 pay CTA together (spec §5/§6).
  Widget _compatReportAction(BuildContext context, WidgetRef ref,
      String otherUserId, dynamic l10n) {
    // Partner PROFILE id: prefer the live profile doc; fall back to the id
    // stamped on the interest (older docs may carry a stale/missing id).
    final amSender = interest.senderId == myUid;
    final partnerProfileId =
        ref.watch(profileByUserIdProvider(otherUserId)).valueOrNull?.id ??
            (amSender ? interest.receiverProfileId : interest.senderProfileId);
    final reqAsync = partnerProfileId.isEmpty
        ? const AsyncValue<AstrologerRequestModel?>.data(null)
        : ref.watch(compatRequestForPairProvider(partnerProfileId));
    final req = reqAsync.valueOrNull;
    // Withhold the action until the answer is known — a member who already
    // requested must never see the paid CTA flash first.
    if (reqAsync.isLoading && !reqAsync.hasValue) return const SizedBox.shrink();

    if (req == null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          // While the request stream is still loading the tap re-checks on
          // the service screen itself, so a duplicate can never slip through.
          onPressed: () {
            if (otherUserId.isEmpty) {
              _snack(context, l10n.horoscopeUnavailableMember);
              return;
            }
            context.push('/horoscope-report/$otherUserId');
          },
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: Text(l10n.getHoroscopeCompatibilityReport,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    if (req.status == AstrologerRequestStatus.completed) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () {
            final compat = CompatibilityReport.tryFrom(req.compatReport);
            if (compat != null && compat.isSubmitted) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CompatibilityReportScreen(
                    requestId: req.id, request: req),
              ));
              return;
            }
            ref.read(homeTabIndexProvider.notifier).state = kReportsTabIndex;
            context.go('/home');
          },
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: Text(l10n.viewHoroscopeReport),
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white),
        ),
      );
    }

    // Pending / in-progress → a quiet status chip, tap = Reports tab.
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          ref.read(homeTabIndexProvider.notifier).state = kReportsTabIndex;
          context.go('/home');
        },
        icon: const Icon(Icons.hourglass_top, size: 18),
        label: Text(l10n.reportUnderAnalysisTitle),
        style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.warning,
            side: BorderSide(color: AppColors.warning.withOpacity(0.6))),
      ),
    );
  }

  Widget _actions(BuildContext context, WidgetRef ref, String otherUserId,
      String name, String photo) {
    final l10n = context.l10n;
    switch (mode) {
      case _CardMode.received:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _reject(context, ref, name),
                style:
                    OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                child: Text(l10n.reject),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: FilledButton.icon(
                  onPressed: () =>
                      _accept(context, ref, otherUserId, name, photo),
                  icon: const Icon(Icons.favorite, size: 18),
                  label: Text(l10n.accept),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder()),
                ),
              ),
            ),
          ],
        );
      case _CardMode.accepted:
        // EXACTLY two actions on an accepted card: View Profile and Get
        // Horoscope Compatibility Report. Nothing else belongs here.
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  if (otherUserId.isEmpty) {
                    _snack(context, l10n.profileUnavailableMatch);
                    return;
                  }
                  openProfileOrPrompt(
                      context, ref, '/profile-user/$otherUserId');
                },
                icon: const Icon(Icons.person_outline, size: 18),
                label: Text(l10n.viewProfile),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Horoscope Compatibility Report — the maroon primary CTA that
            // opens the ONE report page (free result + service details + the
            // ₹200 payment). ONE request per partner profile (spec §12):
            // before any request → the CTA; pending → a status chip;
            // completed → View Report.
            _compatReportAction(context, ref, otherUserId, l10n),
          ],
        );
      case _CardMode.sent:
        // The Sent tab lists PENDING interests only (responded ones live in
        // Accepted / Rejected), so Withdraw is always the action here.
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _withdraw(context, ref),
            icon: const Icon(Icons.undo, size: 18),
            label: Text(l10n.withdrawInterest),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(color: AppColors.error.withOpacity(0.6)),
            ),
          ),
        );
      case _CardMode.rejected:
        // The badge + date already convey the rejected state — no further action.
        return const SizedBox.shrink();
    }
  }


  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
}

class _EmptyState extends StatelessWidget {
  final String text;
  final String subtitle;
  const _EmptyState({required this.text, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
