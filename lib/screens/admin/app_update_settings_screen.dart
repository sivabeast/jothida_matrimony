import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/app_update_config.dart';
import '../../providers/app_update_provider.dart';

/// Admin → Settings → App Update — manages the force-update gate
/// (`app_settings/app_update`): current version, minimum supported version,
/// force ON/OFF, title, message and the Play Store URL.
class AppUpdateSettingsScreen extends ConsumerStatefulWidget {
  const AppUpdateSettingsScreen({super.key});

  @override
  ConsumerState<AppUpdateSettingsScreen> createState() =>
      _AppUpdateSettingsScreenState();
}

class _AppUpdateSettingsScreenState
    extends ConsumerState<AppUpdateSettingsScreen> {
  final _currentVersion = TextEditingController();
  final _minVersion = TextEditingController();
  final _title = TextEditingController();
  final _message = TextEditingController();
  final _storeUrl = TextEditingController();
  bool _forceUpdate = false;
  bool _prefilled = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_currentVersion, _minVersion, _title, _message, _storeUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prefill(AppUpdateConfig cfg) {
    if (_prefilled) return;
    _prefilled = true;
    _currentVersion.text = cfg.currentVersion;
    _minVersion.text = cfg.minSupportedVersion;
    _title.text = cfg.updateTitle;
    _message.text = cfg.updateMessage;
    _storeUrl.text = cfg.playStoreUrl;
    _forceUpdate = cfg.forceUpdate;
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final cfg = AppUpdateConfig(
        currentVersion: _currentVersion.text.trim(),
        minSupportedVersion: _minVersion.text.trim(),
        forceUpdate: _forceUpdate,
        updateTitle: _title.text.trim(),
        updateMessage: _message.text.trim(),
        playStoreUrl: _storeUrl.text.trim(),
      );
      await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('app_update')
          .set(cfg.toMap(), SetOptions(merge: true));
      messenger.showSnackBar(
          const SnackBar(content: Text('App update settings saved.')));
    } catch (e) {
      debugPrint('[AppUpdateSettings] save failed: $e');
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not save settings. Please try again.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(appUpdateConfigProvider);
    final installed = ref.watch(appVersionProvider).valueOrNull ?? '—';
    cfgAsync.whenData((cfg) {
      if (cfg != null) _prefill(cfg);
    });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
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
                  children: [
                    const Text('Force App Update',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700)),
                    Text('Installed admin app version: $installed',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _card(
          children: [
            SwitchListTile(
              value: _forceUpdate,
              onChanged: (v) => setState(() => _forceUpdate = v),
              activeColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
              title: const Text('Force Update',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              subtitle: const Text(
                  'When ON, users below the minimum supported version cannot '
                  'use the app until they update.',
                  style: TextStyle(fontSize: 12.5)),
            ),
            const Divider(height: 20),
            _field(_currentVersion, 'Current Version',
                hint: 'e.g. 1.4.0 (latest on the Play Store)'),
            _field(_minVersion, 'Minimum Supported Version',
                hint: 'e.g. 1.2.0 — older versions are blocked'),
            _field(_title, 'Update Title', hint: 'New Update Available'),
            _field(_message, 'Update Message',
                hint: 'Update your application to continue.', maxLines: 3),
            _field(_storeUrl, 'Play Store URL',
                hint:
                    'https://play.google.com/store/apps/details?id=…'),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(_saving ? 'Saving…' : 'Save Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.gold.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 18, color: AppColors.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Users see the blocking "Update Now" screen the next time the '
                  'app checks the configuration (app start or live while '
                  'running). There is no Skip or Later.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[800], height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
          ],
        ),
        child: Column(children: children),
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
