import 'package:cloud_firestore/cloud_firestore.dart';

/// What the app should do about updating, for the build that is running.
enum AppUpdateRequirement {
  /// Installed build is current (or newer than the config knows about).
  none,

  /// A newer build exists. The member may update or tap Later.
  optional,

  /// The installed build is below the minimum supported version, or the admin
  /// flagged this release as mandatory. The member cannot continue without
  /// updating.
  forced,
}

/// Admin-managed release configuration (`app_config/update`).
///
/// The app NEVER hardcodes the latest version — it reads it from here and
/// compares against its own `PackageInfo.buildNumber` (spec §2). Version CODES
/// are compared, never version-name strings, because "1.10.0" vs "1.9.0" sorts
/// wrong as text.
///
/// Safety rule that outranks everything else: a missing, empty or malformed
/// config must never lock anyone out. Every numeric field defaults to 0, and
/// [requirementFor] treats a non-positive [latestVersionCode] as "nothing to
/// do" — so a config that was never created, or a document with a typo, leaves
/// the app fully usable.
class AppUpdateConfig {
  /// Display name of the newest release, e.g. "1.12.0". Shown in the prompt;
  /// never used for the comparison itself.
  final String latestVersionName;

  /// Version CODE of the newest release. 0 or less = not configured.
  final int latestVersionCode;

  /// Builds below this can no longer be used. 0 disables the floor entirely.
  final int minimumSupportedVersionCode;

  /// Makes the newest release mandatory even for builds at or above the
  /// minimum. Independent of [minimumSupportedVersionCode] so the admin can
  /// force a single critical release without raising the permanent floor.
  final bool forceUpdate;

  /// Admin's own wording. When blank the app uses its localized default, so
  /// the prompt still reads correctly in Tamil and English.
  final String updateMessage;

  /// Play listing URL. Blank falls back to [defaultPlayStoreUrl], which is
  /// built from the real applicationId — never an invented link.
  final String playStoreUrl;

  // ── Update notification (spec §5/§6) ──
  final String notificationTitle;
  final String notificationBody;

  /// Whether the admin wants an update push sent for [latestVersionCode].
  final bool sendNotification;

  final DateTime? updatedAt;

  const AppUpdateConfig({
    this.latestVersionName = '',
    this.latestVersionCode = 0,
    this.minimumSupportedVersionCode = 0,
    this.forceUpdate = false,
    this.updateMessage = '',
    this.playStoreUrl = '',
    this.notificationTitle = '',
    this.notificationBody = '',
    this.sendNotification = false,
    this.updatedAt,
  });

  /// The app's real Play listing, derived from the applicationId in
  /// `android/app/build.gradle`. Kept as a constant rather than composed at
  /// runtime so a wrong package id is a compile-time-visible mistake.
  static const String defaultPlayStoreUrl =
      'https://play.google.com/store/apps/details?id=com.jothida.jothida_matrimony';

  String get effectivePlayStoreUrl {
    final u = playStoreUrl.trim();
    // Only accept a real Play URL: a blank or obviously wrong value falls back
    // rather than sending the member somewhere unexpected.
    if (u.startsWith('https://play.google.com/') || u.startsWith('market://')) {
      return u;
    }
    return defaultPlayStoreUrl;
  }

  /// True when this document carries a usable release number.
  bool get isConfigured => latestVersionCode > 0;

  /// What [installedVersionCode] should do about this config.
  ///
  /// An unreadable installed version (0, which is what `PackageInfo` yields
  /// when the build number cannot be parsed) is treated as "nothing to do":
  /// blocking a member because we could not read our OWN version would be the
  /// worst possible failure mode.
  AppUpdateRequirement requirementFor(int installedVersionCode) {
    if (!isConfigured || installedVersionCode <= 0) {
      return AppUpdateRequirement.none;
    }
    if (minimumSupportedVersionCode > 0 &&
        installedVersionCode < minimumSupportedVersionCode) {
      return AppUpdateRequirement.forced;
    }
    if (installedVersionCode >= latestVersionCode) {
      return AppUpdateRequirement.none;
    }
    return forceUpdate
        ? AppUpdateRequirement.forced
        : AppUpdateRequirement.optional;
  }

  factory AppUpdateConfig.fromFirestore(DocumentSnapshot doc) =>
      AppUpdateConfig.fromFirestoreMap(
          (doc.data() as Map<String, dynamic>?) ?? const {});

  /// Parses the raw document map. Separated from [fromFirestore] so the
  /// parsing rules — which decide whether a member is blocked — can be tested
  /// without constructing a Firestore snapshot.
  factory AppUpdateConfig.fromFirestoreMap(Map<String, dynamic> d) {
    return AppUpdateConfig(
      latestVersionName: '${d['latestVersionName'] ?? ''}',
      latestVersionCode: _int(d['latestVersionCode']),
      minimumSupportedVersionCode: _int(d['minimumSupportedVersionCode']),
      forceUpdate: d['forceUpdate'] == true,
      updateMessage: '${d['updateMessage'] ?? ''}',
      playStoreUrl: '${d['playStoreUrl'] ?? ''}',
      notificationTitle: '${d['notificationTitle'] ?? ''}',
      notificationBody: '${d['notificationBody'] ?? ''}',
      sendNotification: d['sendNotification'] == true,
      updatedAt: d['updatedAt'] is Timestamp
          ? (d['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'latestVersionName': latestVersionName,
        'latestVersionCode': latestVersionCode,
        'minimumSupportedVersionCode': minimumSupportedVersionCode,
        'forceUpdate': forceUpdate,
        'updateMessage': updateMessage,
        'playStoreUrl': playStoreUrl,
        'notificationTitle': notificationTitle,
        'notificationBody': notificationBody,
        'sendNotification': sendNotification,
      };

  /// Tolerant int parse: a legacy document storing "12" as a string, or a
  /// double, still resolves. Anything unparseable becomes 0 — which disables
  /// the gate rather than enabling it.
  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}'.trim()) ?? 0;
  }

  AppUpdateConfig copyWith({
    String? latestVersionName,
    int? latestVersionCode,
    int? minimumSupportedVersionCode,
    bool? forceUpdate,
    String? updateMessage,
    String? playStoreUrl,
    String? notificationTitle,
    String? notificationBody,
    bool? sendNotification,
  }) =>
      AppUpdateConfig(
        latestVersionName: latestVersionName ?? this.latestVersionName,
        latestVersionCode: latestVersionCode ?? this.latestVersionCode,
        minimumSupportedVersionCode:
            minimumSupportedVersionCode ?? this.minimumSupportedVersionCode,
        forceUpdate: forceUpdate ?? this.forceUpdate,
        updateMessage: updateMessage ?? this.updateMessage,
        playStoreUrl: playStoreUrl ?? this.playStoreUrl,
        notificationTitle: notificationTitle ?? this.notificationTitle,
        notificationBody: notificationBody ?? this.notificationBody,
        sendNotification: sendNotification ?? this.sendNotification,
        updatedAt: updatedAt,
      );
}
