import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/login_identifier.dart';
import '../../core/utils/validators.dart';
import '../../models/password_reset_request.dart';
import '../../providers/service_providers.dart';
import '../common/app_text_field.dart';
import '../common/gradient_button.dart';

/// "Contact Admin to Reset Password" — the admin-assisted recovery request.
///
/// Collects ONLY the registered mobile number, an optional name and a short
/// description. It never asks for a password or an OTP, and says so, so the
/// member cannot be talked into sending one.
Future<void> showContactAdminResetSheet(BuildContext context,
    {String mobile = ''}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ContactAdminResetSheet(initialMobile: mobile),
  );
}

class _ContactAdminResetSheet extends ConsumerStatefulWidget {
  final String initialMobile;
  const _ContactAdminResetSheet({required this.initialMobile});

  @override
  ConsumerState<_ContactAdminResetSheet> createState() =>
      _ContactAdminResetSheetState();
}

class _ContactAdminResetSheetState
    extends ConsumerState<_ContactAdminResetSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _mobile = TextEditingController(
      text: LoginIdentifier.localMobile(widget.initialMobile) ?? '');
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;
  String? _result;
  bool _sent = false;

  @override
  void dispose() {
    _mobile.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      // The rules accept a request from any session, including a guest one;
      // start one if the device has none at all.
      final repo = ref.read(authRepositoryProvider);
      if (repo.currentUser == null) await repo.signInAsGuest();
      final uid = repo.currentUserId ?? '';
      final created =
          await ref.read(passwordResetRequestServiceProvider).submit(
                uid: uid,
                mobile: _mobile.text,
                name: _name.text,
                description: _description.text,
              );
      if (!mounted) return;
      setState(() {
        _sent = true;
        _result = created
            ? l10n.contactAdminSubmitted
            : l10n.contactAdminAlreadySent;
      });
    } catch (e) {
      debugPrint('[ContactAdminReset] submit failed: $e');
      if (mounted) setState(() => _result = l10n.contactAdminFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Icon(Icons.support_agent_outlined,
                  size: 44, color: AppColors.primary),
              const SizedBox(height: 10),
              Text(l10n.contactAdminToReset,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(l10n.contactAdminIntro,
                  style: TextStyle(
                      fontSize: 13, height: 1.4, color: Colors.grey[800])),
              const SizedBox(height: 18),
              if (!_sent) ...[
                AppTextField(
                  controller: _mobile,
                  label: '${l10n.mobileNumber} *',
                  hint: '9876543210',
                  keyboardType: TextInputType.phone,
                  prefixText: '+91 ',
                  maxLength: 10,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validator: context.validators.mobile,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _name,
                  label: l10n.contactAdminNameOptional,
                  maxLength: PasswordResetRequest.maxNameLength,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _description,
                  label: l10n.contactAdminDescribe,
                  maxLines: 4,
                  maxLength: PasswordResetRequest.maxDescriptionLength,
                ),
                const SizedBox(height: 18),
                GradientButton(
                  onPressed: _busy ? null : _submit,
                  isLoading: _busy,
                  text: l10n.contactAdminSubmit,
                ),
              ],
              if (_result != null) ...[
                const SizedBox(height: 14),
                Text(_result!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: _sent ? AppColors.success : AppColors.error)),
              ],
              if (_sent) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.backToLogin),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
