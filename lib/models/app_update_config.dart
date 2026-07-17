import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin-managed force-update configuration, stored at
/// `app_settings/app_update`:
///
/// * [currentVersion]      — latest version published on the Play Store.
/// * [minSupportedVersion] — versions BELOW this are blocked when
///                           [forceUpdate] is ON.
/// * [forceUpdate]         — master ON/OFF switch for the blocking gate.
/// * [updateTitle] / [updateMessage] — text shown on the blocking screen.
/// * [playStoreUrl]        — opened by the "Update Now" button.
class AppUpdateConfig {
  final String currentVersion;
  final String minSupportedVersion;
  final bool forceUpdate;
  final String updateTitle;
  final String updateMessage;
  final String playStoreUrl;
  final DateTime? updatedAt;

  const AppUpdateConfig({
    this.currentVersion = '',
    this.minSupportedVersion = '',
    this.forceUpdate = false,
    this.updateTitle = '',
    this.updateMessage = '',
    this.playStoreUrl = '',
    this.updatedAt,
  });

  factory AppUpdateConfig.fromMap(Map<String, dynamic> map) => AppUpdateConfig(
        currentVersion: (map['currentVersion'] as String?) ?? '',
        minSupportedVersion: (map['minSupportedVersion'] as String?) ?? '',
        forceUpdate: (map['forceUpdate'] as bool?) ?? false,
        updateTitle: (map['updateTitle'] as String?) ?? '',
        updateMessage: (map['updateMessage'] as String?) ?? '',
        playStoreUrl: (map['playStoreUrl'] as String?) ?? '',
        updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'currentVersion': currentVersion,
        'minSupportedVersion': minSupportedVersion,
        'forceUpdate': forceUpdate,
        'updateTitle': updateTitle,
        'updateMessage': updateMessage,
        'playStoreUrl': playStoreUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

/// True when semantic version [a] is LOWER than [b] (e.g. '1.2.0' < '1.10.1').
/// Non-numeric segments are treated as 0; missing segments are 0, so
/// '1.2' == '1.2.0'. Malformed input can therefore never lock users out.
bool isVersionBelow(String a, String b) {
  List<int> parse(String v) => v
      .trim()
      .split(RegExp(r'[.+-]'))
      .map((s) => int.tryParse(s) ?? 0)
      .toList();
  final va = parse(a), vb = parse(b);
  final len = va.length > vb.length ? va.length : vb.length;
  for (var i = 0; i < len; i++) {
    final x = i < va.length ? va[i] : 0;
    final y = i < vb.length ? vb[i] : 0;
    if (x != y) return x < y;
  }
  return false;
}
