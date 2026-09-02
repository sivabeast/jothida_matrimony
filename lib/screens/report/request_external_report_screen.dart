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
import '../../models/profile_model.dart';
import '../../providers/astrology_config_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/billing/play_billing_service.dart';
import '../../widgets/report/horoscope_fee_card.dart';
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
    try {
      final billing = ref.read(playBillingServiceProvider);
      await billing.init();
      if (!mounted) return;
      setState(() =>
          _storePrice = billing.priceLabel(BillingProducts.horoscopeReport));
    } catch (_) {
      // Keep the fallback price.
    }
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

  /// The contact step, checked before the member is allowed near the payment
  /// step — nobody should reach a pay button and then be told their phone
  /// number is wrong.
  bool _validateContact() {
    if (!(_contactKey.currentState?.validate() ?? false)) return false;
    if (_whatsapp.text.replaceAll(RegExp(r'\D'), '').length != 10) {
      _snack(context.l10n.whatsappMustBe10Digits);
      return false;
    }
    return true;
  }

  void _next() {
    final ok = switch (_step) {
      0 => _validatePerson(_personOneKey, _one, _personOneLabel),
      1 => _validatePerson(_personTwoKey, _two, _personTwoLabel),
      2 => _validateContact(),
      _ => true,
    };
    if (!ok) return;
    setState(() => _step = (_step + 1).clamp(0, _steps - 1));
  }

  void _back() {
    if (_step == 0) {
      context.pop();
      return;
    }
    setState(() => _step -= 1);
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
    if (!_validateContact()) {
      setState(() => _step = 2); // send them back to the field that failed
      return;
    }
    // Belt and braces behind the formatter + validator: the number that
    // reaches Firestore is ALWAYS exactly 10 digits.
    final digits = _whatsapp.text.replaceAll(RegExp(r'\D'), '');

    setState(() {
      _busy = true;
      _paymentError = null;
    });
    final l10n = context.l10n;
    final isGuest = ref.read(isGuestProvider);
    final billing = ref.read(playBillingServiceProvider);

    try {
      // Re-use an already-paid-for token rather than charging again.
      var token = _paidToken;
      var charged = _fee;
      var verifiedBy = _paidVerifiedBy;
      var orderId = _paidOrderId;

      if (token.isEmpty) {
        final result =
            await billing.buyConsumable(BillingProducts.horoscopeReport);
        if (!mounted) return;
        if (!result.isPurchased) {
          setState(() {
            _busy = false;
            _paymentError = switch (result.outcome) {
              BillingOutcome.canceled => l10n.paymentRequiredToSubmit,
              BillingOutcome.unavailable =>
                result.message ?? l10n.billingUnavailable,
              _ => result.message ?? l10n.paymentCouldNotComplete,
            };
          });
          return;
        }
        token = result.purchaseToken.isNotEmpty
            ? result.purchaseToken
            : 'play_billing';
        verifiedBy = result.verification == BillingVerification.server
            ? 'server'
            : 'client';
        orderId = result.orderId;
        // Record what Play ACTUALLY charged, so revenue stays correct if the
        // Console price is changed without an app update.
        final raw = billing.rawPrice(BillingProducts.horoscopeReport);
        if (raw != null && raw > 0) charged = raw.round();
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
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
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

  // ── Step 4: review + ₹199 payment (spec §2/§3) ───────────────────────────

  Widget _payStep() {
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
            child: const Icon(Icons.verified_outlined,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.reviewAndPayTitle,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5)),
                const SizedBox(height: 2),
                Text(l10n.reviewAndPaySubtitle,
                    style: TextStyle(
                        fontSize: 12, height: 1.4, color: Colors.grey[600])),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 16),
        _summaryCard(),
        const SizedBox(height: 14),
        // Free sample FIRST, price second: the member should know what ₹199
        // buys before they are asked for it (spec §3).
        HoroscopeSamplePreviewCard(
          onView: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const SampleCompatibilityReportScreen())),
        ),
        const SizedBox(height: 14),
        HoroscopeFeeCard(priceText: _priceText),
        if (_paymentError != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.error.withValues(alpha: 0.30)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.error_outline, size: 18, color: AppColors.error),
              const SizedBox(width: 9),
              Expanded(
                child: Text(_paymentError!,
                    style: const TextStyle(
                        fontSize: 12.5, height: 1.45, color: AppColors.error)),
              ),
            ]),
          ),
        ],
      ],
    );
  }

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
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ),
              Expanded(
                child: Text(value.trim().isEmpty ? '—' : value,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

    // The heading carries the Bride/Groom mapping the astrologer will use, so
    // it can be checked before paying rather than queried afterwards (§1E).
    Widget person(String title, HoroscopePersonDraft d) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                if (d.role.isNotEmpty)
                  Text(
                      d.role == kRoleBride
                          ? '· ${l10n.brideRole}'
                          : '· ${l10n.groomRole}',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: d.role == kRoleBride
                              ? const Color(0xFFC2185B)
                              : AppColors.info)),
              ],
            ),
            const SizedBox(height: 4),
            line(l10n.fullName, d.name.text),
            line(l10n.gender, context.localizeValue(d.gender)),
            line(l10n.dateOfBirth,
                d.dob == null ? '' : '${d.dob!.day}-${d.dob!.month}-${d.dob!.year}'),
            line(l10n.timeOfBirth, d.birthTimeText),
            line(l10n.placeOfBirthLabel, d.place?.display ?? ''),
            if ((d.nakshatra ?? '').isNotEmpty)
              line(l10n.nakshatra, d.nakshatra!),
            if ((d.rasi ?? '').isNotEmpty) line(l10n.rasi, d.rasi!),
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
          Row(children: [
            const Icon(Icons.fact_check_outlined,
                size: 17, color: AppColors.primary),
            const SizedBox(width: 7),
            Text(l10n.reviewYourRequest,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13.5)),
          ]),
          const SizedBox(height: 10),
          person(_personOneLabel, _one),
          const Divider(height: 20),
          person(_personTwoLabel, _two),
        ],
      ),
    );
  }

  // ── Chrome ────────────────────────────────────────────────────────────────

  /// Explains, up front, that a guest may submit and what logging in adds
  /// (spec §1). Shown only on the first step so it never becomes wallpaper.
  Widget _intro() {
    final l10n = context.l10n;
    final isGuest = ref.watch(isGuestProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.description_outlined,
                color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l10n.compatibilityReportWithAnyone,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
              isGuest
                  ? l10n.guestCanSubmitHoroscopeRequest
                  : l10n.memberHoroscopeRequestTracked,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 10),
          // Wrap, not Row: in Tamil these two labels do not fit side by side on
          // a 360px phone, and they must stack rather than overflow (§5A).
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              // The free sample, on the very first screen — before a single
              // field has been filled in (spec §3).
              _introLink(
                icon: Icons.auto_stories_outlined,
                label: l10n.viewSampleReport,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    // No pay CTA here: the member is already inside the flow
                    // and both charts still have to be filled in, so closing
                    // the sample simply returns them to the form.
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
          ),
        ],
      ),
    );
  }

  /// An underlined white link inside the maroon intro card.
  Widget _introLink({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: Colors.white),
        label: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white)),
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
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white))
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
