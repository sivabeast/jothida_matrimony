import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/astrologer_model.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/profile_model.dart';
import '../../providers/astrologer_provider.dart';
import '../../providers/match_analysis_provider.dart';

/// "Book Match Analysis" — the user picks a GROOM and a BRIDE profile and sends
/// a porutham request to an astrologer.
///
/// SPEC RULE: the Groom / Bride pickers list ONLY profiles the user has an
/// ACCEPTED interest with (plus their own) — never pending, rejected or random
/// profiles. The two selections must be different.
class BookMatchAnalysisScreen extends ConsumerStatefulWidget {
  final String astrologerId;
  const BookMatchAnalysisScreen({super.key, required this.astrologerId});

  @override
  ConsumerState<BookMatchAnalysisScreen> createState() =>
      _BookMatchAnalysisScreenState();
}

class _BookMatchAnalysisScreenState
    extends ConsumerState<BookMatchAnalysisScreen> {
  String? _groomId;
  String? _brideId;
  final _note = TextEditingController();
  bool _submitting = false;
  // What happens if the astrologer doesn't respond within 24h. Defaults to the
  // simplest option (wait only for this astrologer).
  BookingReassignMode _mode = BookingReassignMode.waitOnly;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int _matchFee(Astrologer a) {
    for (final s in a.services) {
      final n = s.name.toLowerCase();
      if (n.contains('match') || n.contains('porutham') || n.contains('compat')) {
        return s.price;
      }
    }
    return a.startingPrice;
  }

  bool _isMale(ProfileModel p) => p.gender.trim().toLowerCase().startsWith('m');

  ProfileModel? _findById(List<ProfileModel> list, String? id) {
    if (id == null) return null;
    for (final p in list) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _submit(Astrologer astrologer, List<ProfileModel> grooms,
      List<ProfileModel> brides) async {
    // Booking protection — re-check at submit in case the astrologer flipped
    // to Not Available while this screen was open.
    if (!astrologer.isAvailable) {
      _snack('${astrologer.name} is currently not accepting bookings.');
      return;
    }
    final groom = _findById(grooms, _groomId);
    final bride = _findById(brides, _brideId);
    if (groom == null || bride == null) {
      _snack('Select both a groom and a bride profile.');
      return;
    }
    if (groom.id == bride.id) {
      _snack('Groom and bride must be two different profiles.');
      return;
    }
    final fee = _matchFee(astrologer);
    // SPEC §5: show the booking rules + require agreement BEFORE payment.
    final agreed = await _showBookingRules(astrologer, fee);
    if (agreed != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      // SPEC §3/§4: pay online FIRST, then the booking is created (already paid)
      // and only then reaches the astrologer.
      await ref.read(matchAnalysisControllerProvider.notifier).bookAndPay(
            astrologerId: astrologer.id,
            astrologerName: astrologer.name,
            astrologerPhoto: astrologer.photoUrl,
            amount: fee,
            groom: groom,
            bride: bride,
            note: _note.text,
            reassignMode: _mode,
          );
      if (!mounted) return;
      _snack(fee > 0
          ? 'Payment successful — booking sent to ${astrologer.name}.'
          : 'Match analysis request sent to ${astrologer.name}.');
      context.go('/my-analysis');
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('Could not complete the booking. Please try again.');
    }
  }

  /// SPEC §5 — the confirmation screen shown before payment. Lists the booking
  /// rules (analysis starts only after payment, upload a clear horoscope,
  /// response time, cancellation/refund policy) and requires the user to agree
  /// before the (mandatory online) payment can proceed. Returns true once the
  /// user agrees and taps Pay.
  Future<bool?> _showBookingRules(Astrologer astrologer, int fee) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        bool agreed = false;
        return StatefulBuilder(
          builder: (ctx, setSheet) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(3)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Before you pay',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Please read and agree to the match-analysis rules.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
                const SizedBox(height: 16),
                _rule(Icons.payments_outlined,
                    'Online payment is mandatory. Your analysis starts only after '
                    'a successful payment.'),
                _rule(Icons.image_outlined,
                    'Upload a clear horoscope / jathagam for both profiles so the '
                    'astrologer can analyse accurately.'),
                _rule(Icons.schedule_outlined,
                    'The astrologer accepts within 12 working hours. Working hours '
                    'exclude 12:00 AM – 7:00 AM.'),
                _rule(Icons.replay_outlined,
                    'If the astrologer does not respond in time, the booking '
                    'expires and you can choose another astrologer or get a refund '
                    'as per the cancellation policy.'),
                _rule(Icons.account_balance_outlined,
                    'Payment is held by the platform and settled to the astrologer '
                    'after your report is delivered.'),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: agreed,
                  onChanged: (v) => setSheet(() => agreed = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.primary,
                  title: const Text(
                      'I have read and agree to the above rules.',
                      style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        agreed ? () => Navigator.pop(ctx, true) : null,
                    icon: const Icon(Icons.lock_outline, size: 18),
                    label: Text(fee > 0 ? 'Pay ₹$fee & Book' : 'Confirm & Book'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _rule(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]))),
          ],
        ),
      );

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final astrologer = ref.watch(astrologerByIdProvider(widget.astrologerId));
    final candidatesAsync = ref.watch(matchAnalysisCandidatesProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(context.l10n.bookMatchAnalysis),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: astrologer == null
          ? const Center(child: Text('Astrologer not found'))
          : !astrologer.isAvailable
              ? _unavailable(astrologer)
              : candidatesAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => _error(),
              data: (candidates) {
                final grooms = candidates.where(_isMale).toList();
                final brides =
                    candidates.where((p) => !_isMale(p)).toList();
                if (candidates.length < 2 ||
                    grooms.isEmpty ||
                    brides.isEmpty) {
                  return _noCandidates();
                }
                return _form(astrologer, grooms, brides);
              },
            ),
    );
  }

  Widget _form(
      Astrologer astrologer, List<ProfileModel> grooms, List<ProfileModel> brides) {
    final fee = _matchFee(astrologer);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _astrologerHeader(astrologer),
        const SizedBox(height: 16),
        _infoBanner(),
        const SizedBox(height: 20),
        _label('🤵 Groom Profile', required: true),
        const SizedBox(height: 8),
        _profileDropdown(
          selectedId: _groomId,
          items: grooms,
          hint: 'Select groom',
          onChanged: (id) => setState(() => _groomId = id),
        ),
        const SizedBox(height: 18),
        _label('👰 Bride Profile', required: true),
        const SizedBox(height: 8),
        _profileDropdown(
          selectedId: _brideId,
          items: brides,
          hint: 'Select bride',
          onChanged: (id) => setState(() => _brideId = id),
        ),
        const SizedBox(height: 18),
        _label('📝 Note to astrologer (optional)'),
        const SizedBox(height: 8),
        TextField(
          controller: _note,
          maxLines: 4,
          maxLength: 500,
          decoration: InputDecoration(
            hintText: 'Anything specific you want the astrologer to check…',
            filled: true,
            fillColor: Colors.white,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 18),
        _reassignOptions(),
        const SizedBox(height: 8),
        if (fee > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.payments_outlined,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Expanded(child: Text('Analysis fee')),
                Text('₹$fee',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        fontSize: 16)),
              ],
            ),
          ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed:
                _submitting ? null : () => _submit(astrologer, grooms, brides),
            icon: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.lock_outline),
            label: Text(_submitting
                ? context.l10n.sending
                : (fee > 0 ? 'Continue to Payment' : context.l10n.submitRequest)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _astrologerHeader(Astrologer a) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              backgroundImage:
                  a.photoUrl.isNotEmpty ? NetworkImage(a.photoUrl) : null,
              child: a.photoUrl.isEmpty
                  ? const Icon(Icons.person, color: AppColors.primary)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.star, size: 15, color: AppColors.gold),
                    const SizedBox(width: 3),
                    Text('${a.rating.toStringAsFixed(1)} (${a.reviewCount})',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 10),
                    Text('${a.experienceYears} yrs',
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey[600])),
                  ]),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _infoBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.gold.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: AppColors.gold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'You can only choose profiles you have an accepted match with '
                '(and your own).',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[800]),
              ),
            ),
          ],
        ),
      );

  Widget _label(String text, {bool required = false}) => Row(
        children: [
          Text(text,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          if (required)
            const Text(' *', style: TextStyle(color: AppColors.error)),
        ],
      );

  /// The three "what if the astrologer doesn't respond in 24 hours" options.
  /// Exactly one can be chosen — the booking always belongs to a SINGLE
  /// astrologer; these only decide who picks the next one after expiry.
  Widget _reassignOptions() {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('⏳ ${l.reassignQuestion}'),
        const SizedBox(height: 8),
        _modeTile(BookingReassignMode.waitOnly, l.reassignWaitOnly,
            l.reassignWaitOnlyDesc),
        _modeTile(BookingReassignMode.chooseLater, l.reassignChooseLater,
            l.reassignChooseLaterDesc),
        _modeTile(BookingReassignMode.allowAdmin, l.reassignAllowAdmin,
            l.reassignAllowAdminDesc),
      ],
    );
  }

  Widget _modeTile(BookingReassignMode mode, String title, String subtitle) {
    final selected = _mode == mode;
    return InkWell(
      onTap: () => setState(() => _mode = mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : Colors.grey.withOpacity(0.3),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: selected ? AppColors.primary : Colors.grey,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileDropdown({
    required String? selectedId,
    required List<ProfileModel> items,
    required String hint,
    required ValueChanged<String?> onChanged,
  }) {
    // Key by profile id (not object identity) so a candidates-stream re-emit
    // can't leave a stale selection that the dropdown can't match.
    final valid =
        selectedId != null && items.any((p) => p.id == selectedId);
    return DropdownButtonFormField<String>(
      value: valid ? selectedId : null,
      isExpanded: true,
      hint: Text(hint),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: items
          .map((p) => DropdownMenuItem(
                value: p.id,
                child: Text(
                  '${p.fullName}  ·  ${p.age} yrs'
                  '${p.horoscope.rasi.isNotEmpty ? '  ·  ${p.horoscope.rasi}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _unavailable(Astrologer a) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_busy,
                  size: 64, color: AppColors.primary.withOpacity(0.4)),
              const SizedBox(height: 16),
              const Text('Not accepting bookings',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                '${a.name} is currently not available. Please check back later '
                'or choose another astrologer.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary)),
              ),
            ],
          ),
        ),
      );

  Widget _noCandidates() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_border,
                  size: 64, color: AppColors.primary.withOpacity(0.4)),
              const SizedBox(height: 16),
              const Text('No matched profiles yet',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Match analysis needs at least one accepted match. Send and get '
                'an interest accepted first, then come back to book.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => context.go('/home'),
                icon: const Icon(Icons.search),
                label: const Text('Browse matches'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary)),
              ),
            ],
          ),
        ),
      );

  Widget _error() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 56, color: AppColors.error),
              const SizedBox(height: 12),
              const Text('Could not load your matches'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    ref.invalidate(matchAnalysisCandidatesProvider),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
}
