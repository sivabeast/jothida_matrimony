import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin-managed update configuration, stored at `app_settings/app_update`.
///
/// The gate is driven ENTIRELY by the Android **version code** (`pubspec`
/// `+build` number) — nobody ever types a version string anywhere:
///
/// * [latestVersionCode] — the version code of the build that is live on the
///   Play Store. The admin publishes it with one tap ("Release Next Version",
///   which is just `latestVersionCode + 1`); the running app compares its own
///   `PackageInfo.buildNumber` against it.
/// * [latestVersionName] — display only (e.g. `1.2.0`), captured automatically
///   from the releasing device's package info. Never used for comparisons.
/// * [forceUpdate]      — when ON, an outdated build is BLOCKED until it
///   updates; when OFF an outdated build only gets the soft "Update Available"
///   prompt.
/// * [updateTitle] / [updateMessage] — the copy shown in the popup.
/// * [playStoreUrl]     — opened by the "Update Now" button.
///
/// Legacy documents written by the previous (hand-typed version string) admin
/// screen carried `currentVersion` / `minSupportedVersion`. Those keys are no
/// longer written, and [fromMap] only reads `currentVersion` as a fallback for
/// the DISPLAY name — never for the gate — so an old document can never lock
/// anybody out under the new rules.
class AppUpdateConfig {
  /// Play Store build number. `0` means "never released" → the gate is off.
  final int latestVersionCode;

  /// Human version name of that build ('' when unknown).
  final String latestVersionName;

  final bool forceUpdate;
  final String updateTitle;
  final String updateMessage;
  final String playStoreUrl;
  final DateTime? updatedAt;

  const AppUpdateConfig({
    this.latestVersionCode = 0,
    this.latestVersionName = '',
    this.forceUpdate = false,
    this.updateTitle = '',
    this.updateMessage = '',
    this.playStoreUrl = '',
    this.updatedAt,
  });

  factory AppUpdateConfig.fromMap(Map<String, dynamic> map) => AppUpdateConfig(
        latestVersionCode: _intOf(map['latestVersionCode']),
        latestVersionName: (map['latestVersionName'] as String?)?.trim().isNotEmpty
                == true
            ? (map['latestVersionName'] as String).trim()
            // Legacy display fallback only — never feeds the comparison.
            : ((map['currentVersion'] as String?) ?? '').trim(),
        forceUpdate: (map['forceUpdate'] as bool?) ?? false,
        updateTitle: (map['updateTitle'] as String?) ?? '',
        updateMessage: (map['updateMessage'] as String?) ?? '',
        playStoreUrl: (map['playStoreUrl'] as String?) ?? '',
        updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'latestVersionCode': latestVersionCode,
        'latestVersionName': latestVersionName,
        'forceUpdate': forceUpdate,
        'updateTitle': updateTitle,
        'updateMessage': updateMessage,
        'playStoreUrl': playStoreUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  AppUpdateConfig copyWith({
    int? latestVersionCode,
    String? latestVersionName,
    bool? forceUpdate,
    String? updateTitle,
    String? updateMessage,
    String? playStoreUrl,
  }) =>
      AppUpdateConfig(
        latestVersionCode: latestVersionCode ?? this.latestVersionCode,
        latestVersionName: latestVersionName ?? this.latestVersionName,
        forceUpdate: forceUpdate ?? this.forceUpdate,
        updateTitle: updateTitle ?? this.updateTitle,
        updateMessage: updateMessage ?? this.updateMessage,
        playStoreUrl: playStoreUrl ?? this.playStoreUrl,
        updatedAt: updatedAt,
      );

  /// Whether a build running [installedVersionCode] is older than what is
  /// published. `0` (never released) always answers false, so an empty or
  /// unreachable configuration can never gate the app.
  bool isOutdated(int installedVersionCode) =>
      latestVersionCode > 0 && installedVersionCode < latestVersionCode;

  /// Label for the version badge in the update popups.
  String get versionLabel => latestVersionName.isNotEmpty
      ? latestVersionName
      : (latestVersionCode > 0 ? '$latestVersionCode' : '');

  /// Defensive int read — Firestore numbers arrive as `int` or `double`, and a
  /// hand-edited console value may be a string.
  static int _intOf(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }
}
