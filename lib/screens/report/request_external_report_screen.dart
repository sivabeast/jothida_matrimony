import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/master_astrology_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/phone_utils.dart';
import '../../models/profile_model.dart';
import '../../providers/astrology_config_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/profile_provider.dart';
import 'horoscope_request_person_form.dart';

/// **Horoscope Report Request** — the compatibility request for any two people
/// (spec §1–§9).
///
/// Three steps, in this order:
///
///   Person 1 details  →  Person 2 details  →  Contact person + WhatsApp
///
/// Two rules shape everything here:
///
///  * **A guest may submit.** No login is demanded before or during the form,
///    and none at submit either (spec §1). Signing in is offered as an upgrade
///    — it links the request to the account so it can be TRACKED later — never
///    as a gate. A guest's request is stored exactly the same way and reaches
///    the admin identically; the contact WhatsApp number is how it is answered.
///
///  * **The stored request is a SNAPSHOT** (spec §7). A signed-in member's
///    profile only supplies DEFAULTS for Person 1, and every one of those
///    defaults stays editable — or can be wiped with "Clear" so a completely
///    different person is entered. What gets written at submission time is
///    frozen: editing the profile afterwards can never rewrite a request that
///    has already been sent.
///
/// Person 1 is not "the member" and Person 2 is not "the other party" — they
/// are simply the two charts being matched, which is why both use the SAME
/// form ([HoroscopePersonForm]) with the same auto-fill and clear actions.
class RequestExternalReportScreen extends ConsumerStatefulWidget {
  const RequestExternalReportScreen({super.key});

  @override
  ConsumerState<RequestExternalReportScreen> createState() =>
      _RequestExternalReportScreenState();
}

class _RequestExternalReportScreenState
    extends ConsumerState<RequestExternalReportScreen> {
  static const int _steps = 3;

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

  List<String> _rasiOptions = const [];
  List<String> _nakOptions = const [];

  @override
  void initState() {
    super.initState();
    _loadMasterOptions();
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
    if (_autofilled || me == null || !_one.isBlank) return;
    _autofilled = true;
    _one.fillFromProfile(me);
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

  // ── Step validation ───────────────────────────────────────────────────────

  /// Person steps: Name, DOB, birth time and place are required; Nakshatra,
  /// Rasi and the horoscope upload are explicitly optional (spec §3/§34).
  bool _validatePerson(
      GlobalKey<FormState> key, HoroscopePersonDraft d, String who) {
    final l10n = context.l10n;
    if (!(key.currentState?.validate() ?? false)) return false;
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

  void _next() {
    final ok = switch (_step) {
      0 => _validatePerson(_personOneKey, _one, _personOneLabel),
      1 => _validatePerson(_personTwoKey, _two, _personTwoLabel),
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

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_contactKey.currentState?.validate() ?? false)) return;
    // Belt and braces behind the formatter + validator: the number that
    // reaches Firestore is ALWAYS exactly 10 digits (spec §8).
    final digits = _whatsapp.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      _snack(context.l10n.whatsappMustBe10Digits);
      return;
    }

    setState(() => _busy = true);
    final l10n = context.l10n;
    final isGuest = ref.read(isGuestProvider);

    try {
      final id = await ref
          .read(matchAnalysisControllerProvider.notifier)
          .requestHoroscopeReport(
            personOne: _one.toMap(),
            personTwo: _two.toMap(),
            contactName: _contactName.text.trim(),
            contactWhatsapp: digits,
            isGuest: isGuest,
          );
      if (!mounted) return;
      await _showSubmitted(id, digits);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(l10n.couldNotCreateRequest);
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
    switch (_step) {
      case 0:
        return Form(
          key: _personOneKey,
          child: HoroscopePersonForm(
            draft: _one,
            title: context.l10n.personOneDetails,
            subtitle: context.l10n.personDetailsSubtitle,
            icon: Icons.person_outline,
            nakshatraOptions: _nakOptions,
            rasiOptions: _rasiOptions,
            onChanged: () => setState(() {}),
            onAutofill: me == null ? null : () => _one.fillFromProfile(me),
          ),
        );
      case 1:
        return Form(
          key: _personTwoKey,
          child: HoroscopePersonForm(
            draft: _two,
            title: context.l10n.personTwoDetails,
            subtitle: context.l10n.personDetailsSubtitle,
            icon: Icons.person_add_alt_1_outlined,
            nakshatraOptions: _nakOptions,
            rasiOptions: _rasiOptions,
            onChanged: () => setState(() {}),
            onAutofill: me == null ? null : () => _two.fillFromProfile(me),
          ),
        );
      default:
        return Form(key: _contactKey, child: _contactStep());
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
        const SizedBox(height: 18),
        _summaryCard(),
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

    Widget person(String title, HoroscopePersonDraft d) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
            const SizedBox(height: 4),
            line(l10n.fullName, d.name.text),
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
          if (isGuest) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.go('/login'),
                icon: const Icon(Icons.login, size: 16, color: Colors.white),
                label: Text(l10n.loginToTrackRequest,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white)),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _progress() {
    final labels = [
      context.l10n.personOne,
      context.l10n.personTwo,
      context.l10n.contactStep,
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
                onPressed: _busy ? null : (last ? _submit : _next),
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
                    : Text(last ? l10n.submitRequest : l10n.continueLabel,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
