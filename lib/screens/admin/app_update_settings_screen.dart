import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_dialogs.dart';
import '../../models/app_update_config.dart';
import '../../providers/app_update_provider.dart';

/// Admin → Settings → Version Management.
///
/// NOTHING about a version is typed here. The screen reads the RUNNING build's
/// version code / name straight from the platform package, shows what is
/// currently published in `app_settings/app_update`, and publishes the next
/// release with a single "Release Next Version" tap (`latestVersionCode + 1`).
/// The admin only writes the update copy: title, description, Play Store URL
/// and the Force Update switch.
class AppUpdateSettingsScreen extends ConsumerStatefulWidget {
  const AppUpdateSettingsScreen({super.key});

  @override
  ConsumerState<AppUpdateSettingsScreen> createState() =>
      _AppUpdateSettingsScreenState();
}

class _AppUpdateSettingsScreenState
    extends ConsumerState<AppUpdateSettingsScreen> {
  final _title = TextEditingController();
  final _message = TextEditingController();
  final _storeUrl = TextEditingController();
  bool _forceUpdate = false;
  bool _prefilled = false;
  bool _saving = false;

  /// The version code staged by "Release Next Version" and not yet saved.
  /// Null means "publish nothing new" — Save only rewrites the copy.
  int? _stagedVersionCode;

  @override
  void dispose() {
    for (final c in [_title, _message, _storeUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prefill(AppUpdateConfig cfg) {
    if (_prefilled) return;
    _prefilled = true;
    _title.text = cfg.updateTitle;
    _message.text = cfg.updateMessage;
    _storeUrl.text = cfg.playStoreUrl;
    _forceUpdate = cfg.forceUpdate;
  }

  /// The version code the next release will carry.
  ///
  /// Normally `published + 1` (spec: one tap, never a typed number). The very
  /// FIRST release has nothing published yet, so it seeds from the code this
  /// admin device is running — publishing "1" there would be below every real
  /// build and would silently prompt nobody.
  int _nextVersionCode(int published, int installed) =>
      published > 0 ? published + 1 : (installed > 0 ? installed : 1);

  Future<void> _save({
    required int publishedCode,
    required String publishedName,
    required String installedName,
  }) async {
    setState(() => _saving = true);
    try {
      final code = _stagedVersionCode ?? publishedCode;
      // The version NAME is display-only and always taken from the running
      // build — never typed. Falls back to whatever is already published when
      // the package info is unavailable.
      final name =
          installedName.trim().isNotEmpty ? installedName.trim() : publishedName;
      final cfg = AppUpdateConfig(
        latestVersionCode: code,
        latestVersionName: name,
        forceUpdate: _forceUpdate,
        updateTitle: _title.text.trim(),
        updateMessage: _message.text.trim(),
        playStoreUrl: _storeUrl.text.trim(),
      );
      await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('app_update')
          .set(cfg.toMap(), SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _stagedVersionCode = null);
      showAppSnack(context,
          'Saved. Published version code is now $code — older builds will be '
          'prompted to update.');
    } catch (e) {
      debugPrint('[AppUpdateSettings] save failed: $e');
      if (mounted) {
        showAppSnack(context, 'Could not save settings. Please try again.',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(appUpdateConfigProvider);
    final info = ref.watch(appPackageInfoProvider).valueOrNull;
    cfgAsync.whenData((cfg) {
      if (cfg != null) _prefill(cfg);
    });

    final cfg = cfgAsync.valueOrNull;
    final publishedCode = cfg?.latestVersionCode ?? 0;
    final publishedName = cfg?.latestVersionName ?? '';
    final installedCode = int.tryParse(info?.buildNumber.trim() ?? '') ?? 0;
    final installedName = info?.version ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _banner(),
        const SizedBox(height: 16),
        _installedVersionCard(installedCode, installedName),
        const SizedBox(height: 14),
        _publishedVersionCard(publishedCode, publishedName, installedCode),
        const SizedBox(height: 14),
        _updateInfoCard(),
        if (_willLockThisDevice(publishedCode, installedCode)) ...[
          const SizedBox(height: 14),
          _selfLockWarning(),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saving
                ? null
                : () => _save(
                      publishedCode: publishedCode,
                      publishedName: publishedName,
                      installedName: installedName,
                    ),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(_saving
                ? 'Saving…'
                : (_stagedVersionCode != null
                    ? 'Save & Publish v$_stagedVersionCode'
                    : 'Save Settings')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _workflowNote(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _banner() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryLight]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.system_update, color: Colors.white, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Version Management',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text(
                      'Version codes are detected and published automatically — '
                      'nothing to type.',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );

  /// What THIS device is running — read straight from the app package.
  Widget _installedVersionCard(int code, String name) => _card(
        children: [
          _cardTitle(Icons.phone_android_outlined, 'Current Installed Version',
              'Detected automatically from this app package'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                  child: _versionTile(
                      'Version Code', code > 0 ? '$code' : '—', AppColors.info)),
              const SizedBox(width: 12),
              Expanded(
                  child: _versionTile('Version Name',
                      name.trim().isEmpty ? '—' : name, AppColors.info)),
            ],
          ),
        ],
      );

  /// What every user's app compares itself against, plus the one-tap release.
  Widget _publishedVersionCard(int published, String name, int installed) {
    final next = _nextVersionCode(published, installed);
    final staged = _stagedVersionCode;
    return _card(
      children: [
        _cardTitle(Icons.cloud_done_outlined, 'Current Published Version',
            'Live in Firebase — every app checks this on startup'),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _versionTile('Version Code',
                  published > 0 ? '$published' : 'Not released',
                  AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _versionTile('Version Name',
                  name.trim().isEmpty ? '—' : name, AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (staged != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.success.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.rocket_launch_outlined,
                    size: 20, color: AppColors.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ready to release',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.success)),
                      const SizedBox(height: 2),
                      Text(
                        published > 0
                            ? 'Version Code  $published  →  $staged'
                            : 'First release — Version Code  $staged',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _stagedVersionCode = null),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                      visualDensity: VisualDensity.compact),
                  child: const Text('Undo', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('Press Save below to publish it.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
        ] else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _stagedVersionCode = next),
              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
              label: Text('Release Next Version  ($next)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary, width: 1.4),
                minimumSize: const Size.fromHeight(48),
                textStyle: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _updateInfoCard() => _card(
        children: [
          _cardTitle(Icons.campaign_outlined, 'Update Information',
              'The only thing you fill in'),
          const SizedBox(height: 6),
          SwitchListTile(
            value: _forceUpdate,
            onChanged: (v) => setState(() => _forceUpdate = v),
            activeColor: AppColors.primary,
            contentPadding: EdgeInsets.zero,
            title: const Text('Force Update',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            subtitle: const Text(
                'ON: users below the published version code cannot use the app '
                'until they update. OFF: they only see a dismissible prompt.',
                style: TextStyle(fontSize: 12.5)),
          ),
          const Divider(height: 20),
          _field(_title, 'Update Title', hint: 'What\'s new in this release'),
          _field(_message, 'Update Description',
              hint: 'Tell members why they should update.', maxLines: 3),
          _field(_storeUrl, 'Play Store URL',
              hint: 'https://play.google.com/store/apps/details?id=…'),
        ],
      );

  /// The gate makes no exception for admins: publishing a code above the one
  /// THIS device is running, with Force Update ON, blocks this device too — and
  /// the blocking popup has no way back into the admin panel.
  bool _willLockThisDevice(int published, int installed) {
    if (!_forceUpdate || installed <= 0) return false;
    return (_stagedVersionCode ?? published) > installed;
  }

  Widget _selfLockWarning() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 20, color: AppColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('This will also block THIS device',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.error)),
                  const SizedBox(height: 4),
                  Text(
                    'Force Update is ON and you are publishing a version code '
                    'above the build installed here, so this app will be gated '
                    'too — including this screen. Install the new build first, '
                    'or turn Force Update off until you have.',
                    style: TextStyle(
                        fontSize: 12, height: 1.45, color: Colors.grey[800]),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _workflowNote() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 18, color: AppColors.goldDark),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Release workflow',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[850])),
                  const SizedBox(height: 4),
                  Text(
                    'Build the app  →  upload it to the Play Store  →  tap '
                    'Release Next Version  →  write the title and description '
                    '→  Save. Every older build is prompted the next time it '
                    'opens (or immediately, if it is already running).',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[800], height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ── Small building blocks ────────────────────────────────────────────────

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _cardTitle(IconData icon, String title, String subtitle) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      );

  Widget _versionTile(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 18,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: color)),
          ],
        ),
      );

  Widget _field(TextEditingController c, String label,
          {String? hint, int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: c,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey[400]),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      );
}
