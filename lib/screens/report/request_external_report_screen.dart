import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/master_astrology_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/horoscope_roles.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/utils/value_l10n.dart';
import '../../l10n/app_localizations.dart';
import '../../models/profile_model.dart';
import '../../providers/astrology_config_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/billing/horoscope_report_purchase.dart';
import 'horoscope_request_person_form.dart';
import 'sample_compatibility_report_screen.dart';

/// **Horoscope Report Request** — the compatibility request for any two people
/// (spec §1, §2, §12).
///
/// Four steps, in this order:
///
///   Person 1  →  Person 2  →  Contact  →  Review + ₹199 payment
///
/// The rules that shape everything here:
///
///  * **Person 1 is already filled in.** The signed-in member's profile is
///    loaded the moment the screen opens — no "Use my profile details" button
///    to press (spec §1A). A single **Clear** empties the card so a report can
///    be requested for somebody else entirely.
///
///  * **Gender is never asked twice.** Person 1's comes from the profile;
///    Person 2's is the opposite of Person 1's; Female is the Bride and Male is
///    the Groom (spec §1B/§1D/§1E). Only a cleared Person 1 is asked, once.
///
///  * **Nothing exists until it is paid for.** ONE complete request — both
///    charts together — costs ₹199, charged once, and the request document is
///    written only after Play reports a verified purchase (spec §2). A
///    cancelled, failed or abandoned payment leaves nothing behind and the
///    member can simply try again.
///
///  * **The stored request is a SNAPSHOT** (spec §12). The profile supplies
///    DEFAULTS only; what is written at payment time is frozen, so editing the
///    profile afterwards can never rewrite a request already sent.
///
/// A guest may do all of this without an account: Play Billing is tied to the
/// device's Google account, not to a Firebase login. Signing in is offered
/// afterwards purely so the request can be TRACKED.
/// What (if anything) is wrong with a horoscope request's contact details,
/// as a message ready to show — or null when they are fine.
///
/// Deliberately a VALUE check with no Form involved, and top-level so it can be
/// exercised on its own. The contact `Form` only exists in the widget tree
/// while the contact step is on screen, so by the time the pay button is
/// pressed its `currentState` is null. A check routed through the Form read
/// that null as "invalid" and sent the member back a step — which is exactly
/// why pressing "Pay ₹199 · Request report" looked like it navigated backwards
/// instead of opening Google Play.
String? horoscopeContactProblem({
  required String name,
  required String whatsapp,
  required AppLocalizations l10n,
}) {
  if (name.trim().length < 2) return l10n.pleaseEnterFullName;
  final digits = whatsapp.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return l10n.whatsappRequired;
  if (digits.length != 10) return l10n.whatsappMustBe10Digits;
  return null;
}

/// A step the request cannot be paid for without, and why.
class _IncompleteStep {
  /// Index into the four-step form — where the [message] can be fixed.
  final int step;

  /// The step's own label, so the "Fix in …" button names a place the member
  /// recognises from the progress bar.
  final String label;

  final String message;

  const _IncompleteStep(this.step, this.label, this.message);
}

class RequestExternalReportScreen extends ConsumerStatefulWidget {
  const RequestExternalReportScreen({super.key});

  @override
  ConsumerState<RequestExternalReportScreen> createState() =>
      _RequestExternalReportScreenState();
}

class _RequestExternalReportScreenState
    extends ConsumerState<RequestExternalReportScreen> {
  static const int _steps = 4;

  /// The fixed fee for ONE complete compatibility request — both people, one
  /// charge (spec §2). Play Console is the source of truth for what is actually
  /// billed; this is the fallback label and the amount the rules enforce.
  static const int _fee = AppConstants.horoscopeAnalysisFee; // ₹199

  final _personOneKey = GlobalKey<FormState>();
  final _personTwoKey = GlobalKey<FormState>();
  final _contactKey = GlobalKey<FormState>();

  final _one = HoroscopePersonDraft();
  final _two = HoroscopePersonDraft();

  final _contactName = TextEditingController();
  final _whatsapp = TextEditingController();

  int _step = 0;
  bool _busy = false;

  /// Set once Person 1 has been seeded from the profile, so re-entering the
  /// step never silently overwrites edits the member has since made.
  bool _autofilled = false;

  /// True once the member has emptied Person 1 to enter somebody else. That is
  /// the ONE case where the gender has to be asked, and it also stops the
  /// profile from seeding the card a second time.
  bool _oneCleared = false;

  /// Play's own localized price (e.g. "₹199.00"), or null until the store
  /// answers. Never blocks anything — the built-in ₹199 stands in.
  String? _storePrice;

  /// A verified purchase token that has been PAID FOR but whose request has not
  /// been written yet (the network dropped between the two). Holding it means
  /// a retry re-uses the payment instead of charging a second time.
  String _paidToken = '';

  /// How that held payment was verified, carried alongside the token so a retry
  /// records the same provenance the original purchase had.
  String _paidVerifiedBy = 'client';
  String _paidOrderId = '';

  /// What went wrong with the last payment attempt, shown above the pay button
  /// so a cancelled purchase explains itself instead of failing silently.
  String? _paymentError;

  /// Which step still has a gap in it, once the pay button has been pressed.
  /// Rendered as a banner on the review step WITH a button to go and fix it —
  /// the member decides when the page moves, not the pay handler.
  _IncompleteStep? _incomplete;

  List<String> _rasiOptions = const [];
  List<String> _nakOptions = const [];

  @override
  void initState() {
    super.initState();
    _loadMasterOptions();
    _loadStorePrice();
  }

  @override
  void dispose() {
    _one.dispose();
    _two.dispose();
    _contactName.dispose();
    _whatsapp.dispose();
    super.dispose();
  }

  Future<void> _loadMasterOptions() async {
    final m = await MasterAstrologyData.load();
    if (!mounted) return;
    setState(() {
      _rasiOptions = m.rasis.map((e) => e.nameTamil).toList();
      _nakOptions = m.nakshatras.map((e) => e.nameTamil).toList();
    });
  }

  /// Best-effort: an unreachable store (emulator without Play, no network)
  /// must never surface an error here — the UI keeps showing the built-in ₹199
  /// until Play answers.
  Future<void> _loadStorePrice() async {
    final price = await loadHoroscopeReportPrice(
        () => ref.read(playBillingServiceProvider));
    if (!mounted || price == null) return;
    setState(() => _storePrice = price);
  }

  String get _priceText => _storePrice ?? '₹$_fee';

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  /// Seeds Person 1 from the member's profile the FIRST time it is available.
  /// Only ever runs once, and only while the step is still untouched — the
  /// member's own edits always win (spec §5/§6).
  void _maybeAutofill(ProfileModel? me) {
    if (_autofilled || _oneCleared || me == null || !_one.isBlank) return;
    _autofilled = true;
    _one.fillFromProfile(me);
    // Person 2's gender falls out of Person 1's — never asked (spec §1D).
    _syncPersonTwoGender();
    _contactName.text = me.contact.contactPersonName.trim().isNotEmpty
        ? me.contact.contactPersonName.trim()
        : me.fullName;
    // WhatsApp first, then the plain mobile — both are stored in many shapes,
    // so only the last 10 digits are taken (spec §8).
    final phone = (me.contact.whatsappNumber ?? '').trim().isNotEmpty
        ? me.contact.whatsappNumber!.trim()
        : me.contact.mobileNumber.trim();
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      _whatsapp.text = digits.substring(digits.length - 10);
    }
  }

  // ── Gender & Bride/Groom mapping (spec §1B/§1D/§1E) ───────────────────────

  /// Person 2 is always the opposite of Person 1. Re-run whenever Person 1's
  /// gender can have changed, so the two can never drift apart.
  void _syncPersonTwoGender() {
    _two.gender = oppositeHoroscopeGender(_one.gender);
  }

  /// How Person 1's gender is presented: taken from the profile until the
  /// member clears the card, after which this is a different person and the
  /// gender is the one thing that cannot be inferred.
  HoroscopeGenderMode get _personOneGenderMode =>
      (_autofilled && !_oneCleared)
          ? HoroscopeGenderMode.fromProfile
          : HoroscopeGenderMode.manual;

  /// "Clear" on Person 1 (spec §1A). Empties the card, remembers that the
  /// profile must not seed it again, and drops Person 2's derived gender with
  /// it — it was derived from a person who is no longer in the form.
  void _clearPersonOne() {
    _one.clear();
    _oneCleared = true;
    _syncPersonTwoGender();
  }

  // ── Step validation ───────────────────────────────────────────────────────

  /// Person steps: Name, DOB, birth time and place are required; Nakshatra,
  /// Rasi and the horoscope upload are explicitly optional (spec §3/§34).
  bool _validatePerson(
      GlobalKey<FormState> key, HoroscopePersonDraft d, String who) {
    final l10n = context.l10n;
    if (!(key.currentState?.validate() ?? false)) return false;
    // Only ever fails for a cleared Person 1 — every other case is derived.
    if (d.gender.isEmpty) {
      _snack(l10n.pleaseSelectGenderFor(who));
      return false;
    }
    if (d.dob == null) {
      _snack(l10n.pleaseSelectDobFor(who));
      return false;
    }
    if (!d.hasBirthTime) {
      _snack(l10n.pleaseSelectTobFor(who));
      return false;
    }
    if (d.place == null || d.place!.isEmpty) {
      _snack(l10n.pleaseSelectPlaceFor(who));
      return false;
    }
    return true;
  }

  String get _personOneLabel => context.l10n.personOne;
  String get _personTwoLabel => context.l10n.personTwo;

  /// What (if anything) is wrong with the contact details, as a message.
  String? _contactProblem() => horoscopeContactProblem(
        name: _contactName.text,
        whatsapp: _whatsapp.text,
        l10n: context.l10n,
      );

  /// The contact step's own Continue: paints the inline field errors (the Form
  /// IS mounted here) and refuses to advance while anything is wrong.
  bool _validateContactStep() {
    // `?? true` and not `?? false`: a missing Form state means the step is not
    // on screen, which is never a reason to call the values invalid.
    final formOk = _contactKey.currentState?.validate() ?? true;
    final problem = _contactProblem();
    if (problem != null) {
      _snack(problem);
      return false;
    }
    return formOk;
  }

  /// The first step that is not finished, or null when the request is ready to
  /// be paid for.
  ///
  /// Every check here is a VALUE check — `HoroscopePersonDraft.isComplete` and
  /// [horoscopeContactProblem], never a `Form`. Only one step's `Form` is
  /// mounted at a time, so on the review step all three `currentState`s are
  /// null; a check routed through them reads that null as "invalid" and
  /// declares a perfectly complete request broken.
  _IncompleteStep? _missingPiece() {
    final l10n = context.l10n;
    if (!_one.isComplete) {
      return _IncompleteStep(0, l10n.personOne, l10n.personOneIncomplete);
    }
    if (!_two.isComplete) {
      return _IncompleteStep(1, l10n.personTwo, l10n.personTwoIncomplete);
    }
    final contact = _contactProblem();
    if (contact != null) {
      return _IncompleteStep(2, l10n.contactStep, contact);
    }
    return null;
  }

  void _next() {
    final ok = switch (_step) {
      0 => _validatePerson(_personOneKey, _one, _personOneLabel),
      1 => _validatePerson(_personTwoKey, _two, _personTwoLabel),
      2 => _validateContactStep(),
      _ => true,
    };
    if (!ok) return;
    _goTo(_step + 1);
  }

  void _back() {
    if (_step == 0) {
      context.pop();
      return;
    }
    _goTo(_step - 1);
  }

  /// The ONE place the step index changes. Nothing entered is touched — the
  /// drafts and the contact controllers live on this State, so moving between
  /// steps (or leaving for Google Play and coming back) rebuilds the fields
  /// from values that never went anywhere (spec §12).
  void _goTo(int step) {
    setState(() {
      _step = step.clamp(0, _steps - 1);
      // The banner named a gap on the step being opened; it has served its
      // purpose and would otherwise still be there after the fix.
      _incomplete = null;
    });
  }

  // ── Payment, then submit (spec §2) ────────────────────────────────────────

  /// ₹199 → Play → verified purchase → request created. In that order, always.
  ///
  /// Three failure modes are handled distinctly, because they mean different
  /// things to the member:
  ///
  ///  * **Cancelled / failed / unavailable** — nothing was charged and nothing
  ///    was written. The pay button comes back with a plain explanation.
  ///  * **Purchased, but the write failed** — the token is KEPT in [_paidToken]
  ///    so pressing the button again re-uses that payment. This is the case
  ///    that would otherwise charge somebody twice for one report.
  ///  * **Purchased and written** — the confirmation sheet, exactly as before.
  Future<void> _payAndSubmit() async {
    if (_busy) return;

    // Anything still missing is reported HERE, on this step, next to a button
    // the member can choose to press. The screen does not move on its own:
    // silently jumping back to the contact step is what made this button look
    // like it navigated backwards instead of opening Google Play, and a
    // payment CTA that answers by changing the page is indistinguishable from
    // one that is broken (spec §3/§13/§15).
    final missing = _missingPiece();
    if (missing != null) {
      setState(() => _incomplete = missing);
      return;
    }
    // Belt and braces behind the formatter + validator: the number that
    // reaches Firestore is ALWAYS exactly 10 digits.
    final digits = _whatsapp.text.replaceAll(RegExp(r'\D'), '');

    setState(() {
      _busy = true;
      _incomplete = null;
      _paymentError = null;
    });
    final l10n = context.l10n;
    final isGuest = ref.read(isGuestProvider);

    try {
      // Re-use an already-paid-for token rather than charging again.
      var token = _paidToken;
      var charged = _fee;
      var verifiedBy = _paidVerifiedBy;
      var orderId = _paidOrderId;

      if (token.isEmpty) {
        // The SAME purchase the profile-based Horoscope Compatibility Report
        // runs: one Play product, one verification path, one recorded amount.
        final payment = await buyHoroscopeReport(
            () => ref.read(playBillingServiceProvider));
        if (!mounted) return;
        if (!payment.isPaid) {
          setState(() {
            _busy = false;
            _paymentError = payment.failureMessage(l10n);
          });
          return;
        }
        token = payment.purchaseToken;
        verifiedBy = payment.verifiedBy;
        orderId = payment.orderId;
        charged = payment.chargedAmount;
        // Survive a failed write: the money is spent, the token must not be.
        _paidToken = token;
        _paidVerifiedBy = verifiedBy;
        _paidOrderId = orderId;
      }

      final id = await ref
          .read(matchAnalysisControllerProvider.notifier)
          .requestHoroscopeReport(
            personOne: _one.toMap(),
            personTwo: _two.toMap(),
            contactName: _contactName.text.trim(),
            contactWhatsapp: digits,
            isGuest: isGuest,
            amount: charged,
            paymentId: token,
            paymentVerifiedBy: verifiedBy,
            paymentOrderId: orderId,
          );
      if (!mounted) return;
      _paidToken = ''; // consumed
      _paidVerifiedBy = 'client';
      _paidOrderId = '';
      await _showSubmitted(id, digits);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Distinguish "you were charged, we could not save it" from "payment
        // failed" — telling someone their payment failed after taking their
        // money is the worst thing this screen could say.
        _paymentError = _paidToken.isNotEmpty
            ? l10n.paidButRequestNotSavedRetry
            : l10n.couldNotCreateRequest;
      });
    }
  }

  /// Confirmation sheet — the request id to keep, plus the WhatsApp hand-off
  /// (spec §9). Guests are additionally offered a login, because that is the
  /// ONLY thing an account adds here: tracking the request later.
  Future<void> _showSubmitted(String id, String whatsapp) async {
    final l10n = context.l10n;
    final isGuest = ref.read(isGuestProvider);
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l10n.requestSubmittedTitle,
                      style: const TextStyle(
                          fontSize: 17,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.requestIdLabel,
                        style:
                            TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                    const SizedBox(height: 3),
                    SelectableText(id,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.requestSubmittedWhatsappBody,
                  style: TextStyle(
                      fontSize: 13, height: 1.5, color: Colors.grey[700])),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openWhatsapp(id, whatsapp),
                  icon: const Icon(Icons.chat, size: 18),
                  label: Text(l10n.sendOnWhatsapp),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              if (isGuest) ...[
                const SizedBox(height: 10),
                Text(l10n.guestRequestTrackHint,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.go('/login');
                    },
                    icon: const Icon(Icons.login, size: 18),
                    label: Text(l10n.loginToContinue),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _leave(trackable: !isGuest);
                  },
                  child: Text(l10n.done,
                      style: const TextStyle(color: Colors.grey)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) _leave(trackable: !isGuest);
  }

  /// Leaves the form. A member lands on the Reports tab where the new request
  /// is already listed; a guest simply goes Home, since there is nothing
  /// account-scoped for them to look at.
  void _leave({required bool trackable}) {
    if (!mounted) return;
    if (trackable) {
      ref.read(homeTabIndexProvider.notifier).state = kReportsTabIndex;
    }
    context.go('/home');
  }

  /// Opens WhatsApp with the request summary pre-typed, addressed to the
  /// office number from the admin-managed astrology config. Falls back to the
  /// contact person's own number when the office has not configured one, so
  /// the hand-off is never a dead button.
  Future<void> _openWhatsapp(String id, String contactNumber) async {
    final cfg = ref.read(astrologyServiceConfigValueProvider);
    final office = cfg.whatsappNumber.trim();
    final target = office.isNotEmpty ? office : contactNumber;
    final text = Uri.encodeComponent(
        '${context.l10n.whatsappRequestIntro}\n'
        'Request ID: $id\n'
        '${_one.name.text.trim()} — ${_one.birthTimeText} — '
        '${_one.place?.display ?? ''}\n'
        '${_two.name.text.trim()} — ${_two.birthTimeText} — '
        '${_two.place?.display ?? ''}\n'
        'Contact: ${_contactName.text.trim()} (+91 $contactNumber)');
    final uri = Uri.parse('${whatsappUri(target)}?text=$text');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) _snack(context.l10n.couldNotOpenWhatsapp);
    } catch (_) {
      if (mounted) _snack(context.l10n.couldNotOpenWhatsapp);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(myProfileProvider).valueOrNull;
    _maybeAutofill(me);
    final l10n = context.l10n;

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: Text(l10n.requestNewHoroscopeReport),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back), onPressed: _back),
        ),
        body: Column(
          children: [
            _progress(),
            Expanded(
              child: ListView(
                // The sticky pay bar sits on top of the list, so the bottom
                // padding has to clear it — otherwise the last field of every
                // step is typed into from behind a button.
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                // Dismissing the keyboard by scrolling is the gesture people
                // already use to reach the field below the one they just
                // filled in.
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  if (_step == 0) _intro(),
                  if (_step == 0) const SizedBox(height: 14),
                  _card(child: _stepBody(me)),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _bottomBar(),
      ),
    );
  }

  Widget _stepBody(ProfileModel? me) {
    final l10n = context.l10n;
    switch (_step) {
      case 0:
        return Form(
          key: _personOneKey,
          child: HoroscopePersonForm(
            draft: _one,
            title: l10n.personOneDetails,
            // Says whose details these ARE, which is the whole point of loading
            // them automatically (spec §1A).
            subtitle: _personOneGenderMode == HoroscopeGenderMode.fromProfile
                ? l10n.personOneFromYourProfile
                : l10n.personOneEnterManually,
            icon: Icons.person_outline,
            nakshatraOptions: _nakOptions,
            rasiOptions: _rasiOptions,
            genderMode: _personOneGenderMode,
            // Person 1 is the ONLY side with a Clear action, and only once
            // there is something to clear.
            onClear: me == null && _one.isBlank ? null : _clearPersonOne,
            onChanged: () => setState(_syncPersonTwoGender),
          ),
        );
      case 1:
        return Form(
          key: _personTwoKey,
          child: HoroscopePersonForm(
            draft: _two,
            title: l10n.personTwoDetails,
            subtitle: l10n.personTwoPartnerSubtitle,
            icon: Icons.person_add_alt_1_outlined,
            nakshatraOptions: _nakOptions,
            rasiOptions: _rasiOptions,
            // Derived from Person 1, and there is deliberately NO "use my
            // profile details" here: Person 2 is somebody else (spec §1C).
            genderMode: HoroscopeGenderMode.auto,
            onChanged: () => setState(() {}),
          ),
        );
      case 2:
        return Form(key: _contactKey, child: _contactStep());
      default:
        return _payStep();
    }
  }

  // ── Step 3: contact person ───────────────────────────────────────────────
  Widget _contactStep() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.contact_phone_outlined,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.contactDetailsTitle,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5)),
                const SizedBox(height: 2),
                Text(l10n.contactDetailsSubtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 16),
        TextFormField(
          controller: _contactName,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: '${l10n.contactPersonName} *',
            prefixIcon: const Icon(Icons.person_outline, size: 19),
            filled: true,
            fillColor: Colors.white,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          validator: (v) =>
              (v ?? '').trim().length < 2 ? l10n.pleaseEnterFullName : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _whatsapp,
          keyboardType: TextInputType.number,
          // Digits only, hard-capped at 10 — an 11th digit cannot be typed and
          // a pasted "+91…" is trimmed to the local number (spec §8).
          inputFormatters: const [WhatsAppNumberFormatter()],
          decoration: InputDecoration(
            labelText: '${l10n.whatsappNumber} *',
            prefixText: '+91  ',
            counterText: '',
            helperText: l10n.whatsapp10DigitHelper,
            prefixIcon: const Icon(Icons.chat_outlined, size: 19),
            filled: true,
            fillColor: Colors.white,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (_) => setState(() {}),
          validator: (v) {
            final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
            if (d.isEmpty) return l10n.whatsappRequired;
            if (d.length != 10) return l10n.whatsappMustBe10Digits;
            return null;
          },
        ),
      ],
    );
  }

  // ── Step 4: review + payment ─────────────────────────────────────────────

  /// A confirmation screen, not a sales page.
  ///
  /// One card: who the report is for, what they entered, and what it costs.
  /// The fee sits inside the same card as the two names rather than in a
  /// separate banner, and the sample teaser is not repeated here — it is
  /// already offered on the first step, before any details are typed. Three
  /// stacked cards of explanation were burying the one thing this step exists
  /// for: check the details, then pay.
  Widget _payStep() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.verified_outlined,
              color: AppColors.primary, size: 21),
          const SizedBox(width: 9),
          Expanded(
            child: Text(l10n.reviewAndPayTitle,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    fontSize: 16)),
          ),
        ]),
        const SizedBox(height: 14),
        _summaryCard(),
        const SizedBox(height: 12),
        _feeRow(),
        if (_incomplete != null) ...[
          const SizedBox(height: 12),
          _incompleteBanner(_incomplete!),
        ],
        if (_paymentError != null) ...[
          const SizedBox(height: 12),
          _noticeBanner(_paymentError!),
        ],
      ],
    );
  }

  /// "Person 2's details are incomplete — **Fix in Person 2**".
  ///
  /// The button is the only thing that moves the page, and the member presses
  /// it. Everything they have typed is still on this State, so the trip there
  /// and back costs nothing.
  Widget _incompleteBanner(_IncompleteStep missing) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.reviewIncompleteTitle,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(missing.message,
                      style: const TextStyle(fontSize: 12.5, height: 1.45)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _goTo(missing.step),
              icon: const Icon(Icons.edit_outlined, size: 15),
              label: Text(l10n.reviewFixInStep(missing.label),
                  style: const TextStyle(fontSize: 12.5)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticeBanner(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.30)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: 9),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.45, color: AppColors.error)),
          ),
        ]),
      );

  /// "Amount payable — ₹199", on one line. The price is Play's own whenever the
  /// store has answered, so it can never disagree with what is actually
  /// charged.
  Widget _feeRow() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(context.l10n.amountPayable,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600)),
            Text(_priceText,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    height: 1.2,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      );

  /// A read-only recap of exactly what will be stored, so the member can catch
  /// a wrong DOB before the request goes out rather than after.
  Widget _summaryCard() {
    final l10n = context.l10n;
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12, height: 1.35, color: Colors.grey[600])),
              ),
              Expanded(
                child: Text(value.trim().isEmpty ? '—' : value,
                    style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

    // The heading carries the person's NAME and the Bride/Groom mapping the
    // astrologer will use, so both can be checked at a glance before paying.
    Widget person(String title, HoroscopePersonDraft d, int step) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600])),
              ),
              _editLink(step),
            ]),
            const SizedBox(height: 2),
            Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                    d.name.text.trim().isEmpty ? '—' : d.name.text.trim(),
                    style: const TextStyle(
                        fontSize: 15,
                        height: 1.3,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700)),
                if (d.role.isNotEmpty)
                  Text(
                      d.role == kRoleBride ? l10n.brideRole : l10n.groomRole,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: d.role == kRoleBride
                              ? const Color(0xFFC2185B)
                              : AppColors.info)),
              ],
            ),
            const SizedBox(height: 6),
            line(l10n.dateOfBirth,
                d.dob == null
                    ? ''
                    : '${d.dob!.day}-${d.dob!.month}-${d.dob!.year}'),
            line(l10n.timeOfBirth, d.birthTimeText),
            line(l10n.placeOfBirthLabel, d.place?.display ?? ''),
            if ((d.nakshatra ?? '').isNotEmpty)
              line(l10n.nakshatra, d.nakshatra!),
            if ((d.rasi ?? '').isNotEmpty) line(l10n.rasi, d.rasi!),
            if ((d.religion ?? '').isNotEmpty)
              line(l10n.religion, context.localizeValue(d.religion)),
            if ((d.caste ?? '').isNotEmpty)
              line(l10n.communityCaste, context.localizeValue(d.caste)),
            if (d.imageUrl.isNotEmpty || d.pdfUrl.isNotEmpty)
              line(l10n.horoscopeImage, l10n.attached),
          ],
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.horoscopeCompatibilityReport,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.3)),
          const SizedBox(height: 12),
          person(_personOneLabel, _one, 0),
          const Divider(height: 22),
          person(_personTwoLabel, _two, 1),
          const Divider(height: 22),
          // Where the finished report is sent. It was collected two steps ago
          // and never shown again — which is how a report goes out to a
          // mistyped number nobody had a chance to check.
          Row(children: [
            Expanded(
              child: Text(l10n.contactDetailsTitle,
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600])),
            ),
            _editLink(2),
          ]),
          const SizedBox(height: 4),
          line(l10n.contactPersonName, _contactName.text.trim()),
          line(l10n.whatsappNumber,
              _whatsapp.text.trim().isEmpty ? '' : '+91 ${_whatsapp.text.trim()}'),
        ],
      ),
    );
  }

  /// A quiet "Edit" beside each block of the recap. The review step is where a
  /// wrong birth time gets noticed, and noticing it should not mean pressing
  /// Back three times and finding your way forward again.
  Widget _editLink(int step) => TextButton.icon(
        onPressed: _busy ? null : () => _goTo(step),
        icon: const Icon(Icons.edit_outlined, size: 14),
        label: Text(context.l10n.edit, style: const TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );

  // ── Chrome ────────────────────────────────────────────────────────────────

  /// The two things worth offering before a single field is filled in: a look
  /// at a finished report, and — for a guest — a login so the request can be
  /// tracked afterwards. Both are links, not a card: the paragraph that used to
  /// sit here explained a flow the member is already standing in.
  ///
  /// Shown only on the first step so it never becomes wallpaper.
  Widget _intro() {
    final l10n = context.l10n;
    final isGuest = ref.watch(isGuestProvider);
    return Wrap(
      spacing: 18,
      runSpacing: 4,
      children: [
        _introLink(
          icon: Icons.auto_stories_outlined,
          label: l10n.viewSampleReport,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              // No pay CTA here: the member is already inside the flow and
              // both charts still have to be filled in, so closing the sample
              // simply returns them to the form.
              builder: (_) => const SampleCompatibilityReportScreen(),
            ),
          ),
        ),
        if (isGuest)
          _introLink(
            icon: Icons.login,
            label: l10n.loginToTrackRequest,
            onTap: () => context.go('/login'),
          ),
      ],
    );
  }

  /// An underlined brand-coloured link above the first step's form.
  Widget _introLink({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: AppColors.primary),
        label: Text(label,
            style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.primary)),
        style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      );

  Widget _progress() {
    final labels = [
      context.l10n.personOne,
      context.l10n.personTwo,
      context.l10n.contactStep,
      context.l10n.paymentStep,
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: List.generate(_steps, (i) {
          final done = i < _step;
          final active = i == _step;
          final color =
              (done || active) ? AppColors.primary : Colors.grey.shade400;
          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (done || active) ? AppColors.primary : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 1.6),
                  ),
                  child: done
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color:
                                  active ? Colors.white : Colors.grey[600])),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          color: active
                              ? AppColors.primary
                              : Colors.grey[600])),
                ),
                if (i < _steps - 1)
                  Container(width: 10, height: 1.4, color: Colors.grey[300]),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
          ],
        ),
        child: child,
      );

  Widget _bottomBar() {
    final l10n = context.l10n;
    final last = _step == _steps - 1;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06), blurRadius: 12),
          ],
        ),
        child: Row(
          children: [
            if (_step > 0) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _back,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(l10n.back),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _busy ? null : (last ? _payAndSubmit : _next),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.5),
                  minimumSize: const Size.fromHeight(48),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                // The spinner keeps its label: "Opening Google Play…" tells the
                // member the store sheet is on its way, where a bare spinner
                // on a payment button reads as a hang.
                child: _busy
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: Colors.white)),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                                _paidToken.isNotEmpty
                                    ? l10n.processingPayment
                                    : l10n.startingPayment,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    height: 1.25,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      )
                    : Text(
                        last
                            ? (_paidToken.isNotEmpty
                                ? l10n.retrySubmitRequest
                                : l10n.payAndRequestReport(_priceText))
                            : l10n.continueLabel,
                        textAlign: TextAlign.center,
                        // Tamil runs long and the price is appended — two lines
                        // inside the button beats a clipped label (spec §5A).
                        maxLines: 2,
                        style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.25,
                            fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
