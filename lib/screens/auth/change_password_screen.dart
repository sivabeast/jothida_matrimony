import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/gradient_button.dart';

/// Change Password (`/change-password`).
///
/// Reached from Settings, and FORCED by the router while
/// `users/{uid}.mustChangePassword` is set — i.e. after an administrator issued
/// a temporary password. The current password is always re-verified first
/// (Firebase requires a recent sign-in to change it), and changing it ends the
/// account's other sessions.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final forced =
        ref.read(currentUserProvider).valueOrNull?.mustChangePassword ?? false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(
          currentPassword: _current.text, newPassword: _new.text);
      ref.invalidate(currentUserProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.passwordChangedSuccess)));
      if (forced || !context.canPop()) {
        context.go('/home');
      } else {
        context.pop();
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _toggle(bool obscure, VoidCallback onTap) => IconButton(
        icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
        onPressed: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final forced =
        ref.watch(currentUserProvider).valueOrNull?.mustChangePassword ?? false;
    final hasPassword = ref
        .read(authRepositoryProvider)
        .currentProviderIds
        .contains('password');
    return PopScope(
      // A temporary password must be replaced before anything else.
      canPop: !forced,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(l10n.changePassword),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: !forced,
          actions: [
            if (forced)
              IconButton(
                tooltip: l10n.logout,
                icon: const Icon(Icons.logout),
                onPressed: _busy
                    ? null
                    : () => ref.read(authNotifierProvider.notifier).signOut(),
              ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: !hasPassword
                    ? Text(l10n.changePasswordNoPasswordLogin,
                        style: AppTextStyles.bodyMedium)
                    : Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Icon(Icons.password_outlined,
                                size: 56, color: AppColors.primary),
                            const SizedBox(height: 14),
                            Text(
                              forced
                                  ? l10n.mustChangePasswordIntro
                                  : l10n.changePasswordIntro,
                              style: AppTextStyles.bodyMedium,
                            ),
                            const SizedBox(height: 22),
                            AppTextField(
                              controller: _current,
                              label: l10n.currentPassword,
                              obscureText: _obscureCurrent,
                              validator: Validators.password,
                              suffixIcon: _toggle(
                                  _obscureCurrent,
                                  () => setState(() =>
                                      _obscureCurrent = !_obscureCurrent)),
                            ),
                            const SizedBox(height: 16),
                            AppTextField(
                              controller: _new,
                              label: l10n.newPassword,
                              obscureText: _obscureNew,
                              validator: (v) =>
                                  Validators.password(v) ??
                                  (v == _current.text
                                      ? l10n.newPasswordMustDiffer
                                      : null),
                              suffixIcon: _toggle(_obscureNew,
                                  () => setState(() => _obscureNew = !_obscureNew)),
                            ),
                            const SizedBox(height: 16),
                            AppTextField(
                              controller: _confirm,
                              label: l10n.confirmPassword,
                              obscureText: _obscureConfirm,
                              validator: (v) =>
                                  Validators.confirmPassword(v, _new.text),
                              suffixIcon: _toggle(
                                  _obscureConfirm,
                                  () => setState(() =>
                                      _obscureConfirm = !_obscureConfirm)),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Text(_error!,
                                  style:
                                      const TextStyle(color: AppColors.error)),
                            ],
                            const SizedBox(height: 24),
                            GradientButton(
                              onPressed: _busy ? null : _submit,
                              isLoading: _busy,
                              text: l10n.changePassword,
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown while a signed-in session belongs to a login the administrator
/// removed (`users/{uid}.authStatus`), e.g. a device that stayed signed in.
class AccountUnavailableScreen extends ConsumerWidget {
  const AccountUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.no_accounts_outlined,
                      size: 64, color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(l10n.accountUnavailableTitle,
                      style: AppTextStyles.heading2,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Text(l10n.accountUnavailableMessage,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium),
                  const SizedBox(height: 26),
                  GradientButton(
                    onPressed: () async {
                      await ref.read(authNotifierProvider.notifier).signOut();
                      if (context.mounted) context.go('/login');
                    },
                    text: l10n.logout,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.push('/help'),
                    child: Text(l10n.helpSupport),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
