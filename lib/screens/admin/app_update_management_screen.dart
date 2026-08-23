import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_dialogs.dart';
import '../../models/app_update_config.dart';
import '../../providers/app_update_provider.dart';
import '../../providers/notification_provider.dart';

/// **App Update** management (spec §6).
///
/// One admin page for the whole release gate: which version is current, which
/// version is the floor, whether the update is mandatory, the wording members
/// see, the Play link, and the optional update push.
///
/// It writes the single `app_config/update` document that every app reads, so
/// announcing a release never needs a code change or a rebuild.
class AppUpdateManagementScreen extends ConsumerStatefulWidget {
  const AppUpdateManagementScreen({super.key});

  @override
  ConsumerState<AppUpdateManagementScreen> createState() =>
      _AppUpdateManagementScreenState();
}

class _AppUpdateManagementScreenState
    extends ConsumerState<AppUpdateManagementScreen> {
  final _formKey = GlobalKey<FormState>();

  final _versionName = TextEditingController();
  final _versionCode = TextEditingController();
  final _minVersionCode = TextEditingController();
  final _message = TextEditingController();
  final _storeUrl = TextEditingController();
  final _notifTitle = TextEditingController();
  final _notifBody = TextEditingController();

  bool _forceUpdate = false;
  bool _sendNotification = false;
  bool _loaded = false;
  bool _saving = false;
  bool _sending = false;

  @override
  void dispose() {
    _versionName.dispose();
    _versionCode.dispose();
    _minVersionCode.dispose();
    _message.dispose();
    _storeUrl.dispose();
    _notifTitle.dispose();
    _notifBody.dispose();
    super.dispose();
  }

  /// Seeds the form ONCE from the live config, so an admin's half-typed edit is
  /// never overwritten by a snapshot arriving mid-typing.
  void _seed(AppUpdateConfig c) {
    if (_loaded) return;
    _loaded = true;
    _versionName.text = c.latestVersionName;
    _versionCode.text = c.latestVersionCode > 0 ? '${c.latestVersionCode}' : '';
    _minVersionCode.text =
        c.minimumSupportedVersionCode > 0 ? '${c.minimumSupportedVersionCode}' : '';
    _message.text = c.updateMessage;
    _storeUrl.text = c.playStoreUrl;
    _notifTitle.text = c.notificationTitle;
    _notifBody.text = c.notificationBody;
    _forceUpdate = c.forceUpdate;
    _sendNotification = c.sendNotification;
  }

  int _int(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    await ref.read(appUpdateConfigControllerProvider.notifier).save({
      'latestVersionName': _versionName.text.trim(),
      'latestVersionCode': _int(_versionCode),
      'minimumSupportedVersionCode': _int(_minVersionCode),
      'forceUpdate': _forceUpdate,
      'updateMessage': _message.text.trim(),
      'playStoreUrl': _storeUrl.text.trim(),
      'notificationTitle': _notifTitle.text.trim(),
      'notificationBody': _notifBody.text.trim(),
      'sendNotification': _sendNotification,
    });
    if (!mounted) return;
    final failed = ref.read(appUpdateConfigControllerProvider).hasError;
    setState(() => _saving = false);
    showAppSnack(
        context,
        failed
            ? 'Could not save the update settings.'
            : 'Update settings saved.',
        error: failed);
  }

  /// Sends the update push to every member on an older build.
  ///
  /// Deliberately a separate, explicit action rather than a side effect of
  /// Save: an admin fixing a typo in the message must not re-notify everyone.
  Future<void> _sendNotificationNow() async {
    final code = _int(_versionCode);
    if (code <= 0) {
      showAppSnack(context, 'Set the latest version code first.', error: true);
      return;
    }
    final ok = await showAppConfirmDialog(
      context,
      title: 'Send the update notification?',
      message: 'Every member running a build older than $code will be '
          'notified once. Members already on $code or newer are skipped, and '
          'nobody is notified twice for the same version.',
      confirmLabel: 'Send',
      cancelLabel: 'Cancel',
      icon: Icons.campaign_outlined,
    );
    if (!ok || !mounted) return;
    setState(() => _sending = true);
    final sent = await ref
        .read(notificationNotifierProvider.notifier)
        .sendUpdateAnnouncement(
          versionCode: code,
          versionName: _versionName.text.trim(),
          title: _notifTitle.text.trim(),
          body: _notifBody.text.trim(),
        );
    if (!mounted) return;
    setState(() => _sending = false);
    showAppSnack(
        context,
        sent < 0
            ? 'Could not send the update notification.'
            : 'Update notification queued for $sent member(s).',
        error: sent < 0);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(appUpdateConfigProvider);
    final installed = ref.watch(installedVersionCodeProvider).valueOrNull;
    final config = async.valueOrNull;
    if (config != null) _seed(config);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: async.isLoading && config == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _StatusCard(config: config, installedVersionCode: installed),
                  const SizedBox(height: 16),
                  _section('Release', [
                    _text(_versionName, 'Latest Version Name',
                        hint: 'e.g. 1.12.0'),
                    const SizedBox(height: 12),
                    _number(_versionCode, 'Latest Version Code',
                        hint: 'the +N from pubspec, e.g. 17',
                        required: true),
                    const SizedBox(height: 6),
                    _hint('Members whose installed version code is BELOW this '
                        'are offered the update.'),
                    const SizedBox(height: 12),
                    _number(_minVersionCode, 'Minimum Supported Version Code',
                        hint: 'leave blank or 0 for no floor'),
                    const SizedBox(height: 6),
                    _hint('Members below this cannot continue without '
                        'updating. Leave blank unless an old build is truly '
                        'broken — this locks people out.'),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      value: _forceUpdate,
                      activeThumbColor: AppColors.error,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Force this release'),
                      subtitle: const Text(
                          'Makes the latest release mandatory for everyone '
                          'below it, without raising the permanent floor.'),
                      onChanged: (v) => setState(() => _forceUpdate = v),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _section('Wording', [
                    _text(_message, 'Update Message',
                        hint: 'Leave blank to use the app’s own '
                            'Tamil/English wording',
                        maxLines: 4),
                    const SizedBox(height: 12),
                    _text(_storeUrl, 'Play Store URL',
                        hint: AppUpdateConfig.defaultPlayStoreUrl),
                    const SizedBox(height: 6),
                    _hint('Blank uses the app’s own Play listing. A value '
                        'that is not a play.google.com or market:// link is '
                        'ignored.'),
                  ]),
                  const SizedBox(height: 14),
                  _section('Update notification', [
                    _text(_notifTitle, 'Notification Title',
                        hint: 'New Update Available 🎉'),
                    const SizedBox(height: 12),
                    _text(_notifBody, 'Notification Body',
                        maxLines: 3,
                        hint: 'Blank uses the app’s default wording'),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      value: _sendNotification,
                      activeThumbColor: AppColors.success,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Update notifications enabled'),
                      subtitle: const Text(
                          'Turn off to stop announcing this release.'),
                      onChanged: (v) => setState(() => _sendNotification = v),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: (_sending || !_sendNotification)
                          ? null
                          : _sendNotificationNow,
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_outlined, size: 18),
                      label: const Text('Send update notification now'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _hint('Only members on an older build are notified, and '
                        'each member is notified once per version.'),
                  ]),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(_saving ? 'Saving…' : 'Save Settings'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _section(String title, List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const Divider(height: 18),
            ...children,
          ],
        ),
      );

  Widget _text(TextEditingController c, String label,
          {String? hint, int maxLines = 1}) =>
      TextFormField(
        controller: c,
        maxLines: maxLines,
        decoration: _dec(label, hint),
      );

  Widget _number(TextEditingController c, String label,
          {String? hint, bool required = false}) =>
      TextFormField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: _dec(label, hint),
        validator: required
            ? (v) => (int.tryParse((v ?? '').trim()) ?? 0) > 0
                ? null
                : 'Enter the version code'
            : null,
      );

  Widget _hint(String text) => Text(text,
      style: TextStyle(fontSize: 11.5, height: 1.4, color: Colors.grey[600]));

  InputDecoration _dec(String label, String? hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        hintMaxLines: 2,
        isDense: true,
        filled: true,
        fillColor: AppColors.scaffoldBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}

/// Shows what the config currently does — including to THIS device, which is
/// the quickest way for an admin to sanity-check a change.
class _StatusCard extends StatelessWidget {
  final AppUpdateConfig? config;
  final int? installedVersionCode;

  const _StatusCard({required this.config, required this.installedVersionCode});

  @override
  Widget build(BuildContext context) {
    final c = config;
    final installed = installedVersionCode ?? 0;
    final requirement =
        c?.requirementFor(installed) ?? AppUpdateRequirement.none;
    final configured = c?.isConfigured ?? false;

    final (color, text) = switch (requirement) {
      AppUpdateRequirement.forced => (
          AppColors.error,
          'This build ($installed) would be FORCED to update.'
        ),
      AppUpdateRequirement.optional => (
          AppColors.warning,
          'This build ($installed) would be offered an optional update.'
        ),
      AppUpdateRequirement.none => configured
          ? (
              AppColors.success,
              'This build ($installed) is up to date — no prompt.'
            )
          : (
              Colors.grey,
              'No release configured yet, so nobody is prompted. Set the '
                  'latest version code below to switch the gate on.'
            ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.phonelink_setup_outlined, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12.5, height: 1.45)),
          ),
        ],
      ),
    );
  }
}
