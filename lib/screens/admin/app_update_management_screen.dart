import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_dialogs.dart';
import '../../models/app_update_config.dart';
import '../../providers/app_update_provider.dart';

/// **App Version** — what the release gate is doing, and the one policy switch
/// that changes it (spec §10).
///
/// The admin does not, and cannot, type a version number here. Every number on
/// this page is read from somewhere that actually knows it:
///
///   * **Current App Version** — this build's own `PackageInfo`.
///   * **Latest Published Version** — Google Play's live track, plus the
///     `app_config/update` document that the newest build publishes on an
///     admin's device. Both are automatic.
///   * **Minimum Supported Version** — `kMinimumSupportedVersionCode`, compiled
///     into the release and published with it.
///
/// The only control is **Force Update**: whether members on an out-of-date
/// build are blocked until they update, or merely offered the update and
/// allowed to continue (spec §10A/§10B/§10C). That is a policy decision, which
/// is why it belongs to the admin — the version numbers are facts, which is why
/// they do not.
///
/// Publishing happens quietly on open: if this build is newer than what the
/// document records, it writes its own metadata across. So the way to publish a
/// new version is simply to release it and open the app — there is no form and
/// no "increase version" button, both of which were removed here.
class AppUpdateManagementScreen extends ConsumerStatefulWidget {
  const AppUpdateManagementScreen({super.key});

  @override
  ConsumerState<AppUpdateManagementScreen> createState() =>
      _AppUpdateManagementScreenState();
}

class _AppUpdateManagementScreenState
    extends ConsumerState<AppUpdateManagementScreen> {
  bool _saving = false;

  /// Guards against re-publishing on every rebuild — the config is a live
  /// stream, so this widget rebuilds each time the document changes.
  bool _publishAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _publish());
  }

  /// Pushes this build's own version metadata to `app_config/update`, once per
  /// visit. Silent and best-effort: it is housekeeping, not a user action, and
  /// a failure changes nothing the admin can act on.
  Future<void> _publish() async {
    if (_publishAttempted) return;
    _publishAttempted = true;
    // Let the live config arrive first, so we compare against real values
    // rather than publishing on top of a null.
    await ref.read(appUpdateConfigProvider.future).catchError(
        (_) => const AppUpdateConfig());
    if (!mounted) return;
    await ref.read(appUpdateConfigControllerProvider.notifier)
        .publishRunningRelease();
  }

  Future<void> _setForceUpdate(bool enabled) async {
    setState(() => _saving = true);
    await ref
        .read(appUpdateConfigControllerProvider.notifier)
        .setForceUpdate(enabled);
    if (!mounted) return;
    final failed = ref.read(appUpdateConfigControllerProvider).hasError;
    setState(() => _saving = false);
    showAppSnack(
      context,
      failed
          ? 'Could not change the Force Update policy.'
          : (enabled
              ? 'Force Update is ON — members below the minimum supported '
                  'version must update to continue.'
              : 'Force Update is OFF — members are offered the update and may '
                  'continue.'),
      error: failed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(appUpdateConfigProvider);
    final config = async.valueOrNull;
    final installed = ref.watch(installedVersionCodeProvider).valueOrNull ?? 0;
    final installedName =
        ref.watch(installedVersionNameProvider).valueOrNull ?? '';
    final playLatest =
        ref.watch(playAvailableVersionCodeProvider).valueOrNull ?? 0;
    final compiledFloor = ref.watch(compiledMinimumVersionCodeProvider);

    if (async.isLoading && config == null) {
      return const Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        body:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    // The published latest is whichever source knows about the newer build.
    final publishedLatest = [
      config?.latestVersionCode ?? 0,
      playLatest,
      installed,
    ].reduce((a, b) => a > b ? a : b);
    final minimum = config?.minimumSupportedVersionCode ?? compiledFloor;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(
              config: config,
              installedVersionCode: installed,
              installedVersionName: installedName),
          const SizedBox(height: 16),
          _section('Version information', [
            _readOnlyRow(
              label: 'Current App Version',
              value: _versionText(installedName, installed),
              hint: 'The build this device is running.',
            ),
            _readOnlyRow(
              label: 'Latest Published Version',
              value: _versionText(config?.latestVersionName ?? '', publishedLatest),
              hint: playLatest > 0
                  ? 'Reported by Google Play.'
                  : 'Published automatically by the newest build. Google Play '
                      'has not reported a newer release to this device.',
            ),
            _readOnlyRow(
              label: 'Minimum Supported Version',
              value: minimum > 0 ? '$minimum' : 'No floor set',
              hint: minimum > 0
                  ? 'Builds below this cannot continue while Force Update is '
                      'ON.'
                  : 'Every build is currently supported. The floor is compiled '
                      'into the release, not set here.',
            ),
            _readOnlyRow(
              label: 'Update Available',
              value: publishedLatest > installed ? 'Yes' : 'No',
              hint: publishedLatest > installed
                  ? 'A newer build than this one exists.'
                  : 'This device is on the newest known build.',
              last: true,
            ),
          ]),
          const SizedBox(height: 14),
          _section('Update policy', [
            // The ONE thing an admin decides here (spec §10A).
            SwitchListTile(
              value: config?.forceUpdate ?? false,
              activeThumbColor: AppColors.error,
              contentPadding: EdgeInsets.zero,
              title: const Text('Force Update',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text(
                  'ON — members on an out-of-date build are blocked until they '
                  'update, with no Later or Skip.\n'
                  'OFF — members see an optional prompt and may tap Later and '
                  'carry on.',
                  style: TextStyle(fontSize: 12, height: 1.5)),
              isThreeLine: true,
              onChanged: _saving ? null : _setForceUpdate,
            ),
            if (_saving) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ]),
          const SizedBox(height: 14),
          _section('How versions are set', [
            _note(
                'Version numbers are read from the app itself and from Google '
                'Play — they cannot be typed or increased by hand. Release a '
                'new build to Play as usual; the number here updates on its '
                'own the next time an admin opens this page on that build.'),
            const SizedBox(height: 10),
            _note(
                'To stop an old build from being used at all, raise '
                '`kMinimumSupportedVersionCode` in '
                'lib/core/config/release_config.dart before cutting the '
                'release, and turn Force Update ON.'),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _versionText(String name, int code) {
    if (code <= 0) return name.isNotEmpty ? name : '—';
    return name.isNotEmpty ? '$name ($code)' : '$code';
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

  /// A label / value pair that is plainly NOT an input — no border, no cursor,
  /// nothing that invites an edit.
  Widget _readOnlyRow({
    required String label,
    required String value,
    required String hint,
    bool last = false,
  }) =>
      Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wrap so a long value drops below its label instead of colliding
            // with it on a narrow screen.
            Wrap(
              spacing: 10,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.grey[600])),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 3),
            Text(hint,
                style: TextStyle(
                    fontSize: 11.5, height: 1.45, color: Colors.grey[600])),
          ],
        ),
      );

  Widget _note(String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 11.5, height: 1.55, color: Colors.grey[700])),
          ),
        ],
      );
}

/// Shows what the config currently does — including to THIS device, which is
/// the quickest way for an admin to sanity-check the policy.
class _StatusCard extends StatelessWidget {
  final AppUpdateConfig? config;
  final int installedVersionCode;
  final String installedVersionName;

  const _StatusCard({
    required this.config,
    required this.installedVersionCode,
    required this.installedVersionName,
  });

  @override
  Widget build(BuildContext context) {
    final c = config;
    final installed = installedVersionCode;
    final requirement =
        c?.requirementFor(installed) ?? AppUpdateRequirement.none;
    final configured = c?.isConfigured ?? false;

    final (color, text) = switch (requirement) {
      AppUpdateRequirement.forced => (
          AppColors.error,
          'This build ($installed) would be BLOCKED until it updates.'
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
              'No release has been published yet, so nobody is prompted. '
                  'Opening this page on the newest build publishes it.'
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Current App Version: '
                    '${installedVersionName.isNotEmpty ? installedVersionName : '—'}'
                    '${installed > 0 ? ' ($installed)' : ''}',
                    style: const TextStyle(
                        fontSize: 13.5, height: 1.35,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(text,
                    style: const TextStyle(fontSize: 12.5, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
