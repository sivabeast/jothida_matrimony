import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../common/app_text_field.dart';
import '../common/gradient_button.dart';

/// The ONE authentication UI the app shows a guest who is about to submit
/// something that needs an account — an astrology booking, an appointment, a
/// horoscope request.
///
/// Deliberately reusable rather than re-implemented per feature: the login page
/// and every protected action present the same two choices in the same order,
/// so members are never asked to authenticate in a shape they have not seen
/// before.
///
///   Continue with Google
///   ── OR ──
///   name / phone / password / confirm  →  Create Account
///
/// No other providers. The caller keeps whatever the guest already typed and
/// resumes its own flow on success, so nothing is re-entered:
///
/// ```dart
/// if (!await ensureAccount(context, ref, reason: ...)) return; // backed out
/// await submitTheBooking();                       // data still in hand
/// ```
class AccountRequiredSheet extends ConsumerStatefulWidget {
  /// One line explaining WHY an account is needed, in the caller's words
  /// ("Create an account to confirm your appointment").
  final String reason;

  const AccountRequiredSheet({super.key, required this.reason});

  @override
  ConsumerState<AccountRequiredSheet> createState() =>
      _AccountRequiredSheetState();
}

class _AccountRequiredSheetState extends ConsumerState<AccountRequiredSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Pops with `true` only once the account actually exists, so the caller can
  /// read a `true` result as "you are signed in, carry on".
  void _done() => Navigator.of(context).pop(true);

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await ref.read(authNotifierProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    final state = ref.read(authNotifierProvider);
    setState(() => _busy = false);
    if (state.hasError || state.valueOrNull == null) {
      setState(() => _error = context.l10n.googleSignInFailed);
      return;
    }
    _done();
  }

  Future<void> _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Gender and date of birth belong to the MATRIMONY profile, not to the
    // account — an astrology customer may never create one — so they are not
    // asked for here.
    await ref.read(authNotifierProvider.notifier).registerUser(
          password: _password.text,
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          gender: '',
          dateOfBirth: DateTime(1900),
        );
    if (!mounted) return;
    final state = ref.read(authNotifierProvider);
    setState(() => _busy = false);
    if (state.hasError || state.valueOrNull == null) {
      setState(() => _error = context.l10n.couldNotCreateAccount);
      return;
    }
    _done();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(l10n.createAccount,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(widget.reason,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 18),

            // ── 1. Google, first and primary ─────────────────────────────
            OutlinedButton.icon(
              onPressed: _busy ? null : _google,
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: Text(l10n.continueWithGoogle,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: BorderSide(color: Colors.grey[300]!),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            const AuthOrDivider(),
            const SizedBox(height: 16),

            // ── 2. Manual registration ───────────────────────────────────
            Form(
              key: _formKey,
              child: Column(
                children: [
                  AppTextField(
                    controller: _name,
                    label: l10n.fullName,
                    textCapitalization: TextCapitalization.words,
                    validator: Validators.name,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _phone,
                    label: l10n.mobileNumber,
                    keyboardType: TextInputType.phone,
                    prefixText: '+91 ',
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator: Validators.phone,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _password,
                    label: l10n.password,
                    obscureText: _obscure,
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    validator: Validators.password,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _confirm,
                    label: l10n.confirmPassword,
                    obscureText: _obscure,
                    validator: (v) =>
                        Validators.confirmPassword(v, _password.text),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppColors.error, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            GradientButton(
              onPressed: _busy ? null : _register,
              text: l10n.createAccount,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child:
                  Text(l10n.cancel, style: TextStyle(color: Colors.grey[600])),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "── OR ──" rule that separates Google from the manual form. Shared so
/// the login page and the sheet cannot drift apart.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[300])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(context.l10n.orLabel,
                style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Divider(color: Colors.grey[300])),
        ],
      );
}

/// Guarantees a signed-in ACCOUNT before a protected submit.
///
/// Returns true when the caller may proceed — either the visitor was already
/// signed in, or they just created an account in the sheet. Returns false only
/// when they backed out, in which case the caller keeps its form state and
/// simply does nothing, so nothing the guest typed is lost.
///
/// A matrimony profile is deliberately NOT required: an astrology customer, or
/// someone requesting a horoscope match, needs an account — not a marriage
/// profile.
Future<bool> ensureAccount(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
}) async {
  final signedIn = ref.read(authRepositoryProvider).currentUser != null &&
      !ref.read(isGuestProvider);
  if (signedIn) return true;

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => AccountRequiredSheet(reason: reason),
  );
  return ok == true;
}
