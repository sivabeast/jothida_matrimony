import 'package:flutter_test/flutter_test.dart';
import 'package:jothida_matrimony/models/app_update_config.dart';

/// The update gate decides whether a member can use the app at all, so its two
/// jobs are pinned here: never block when anything is unknown, and never let a
/// legacy (hand-typed version string) document block anybody.
void main() {
  group('AppUpdateConfig.isOutdated', () {
    test('blocks a build below the published version code', () {
      const cfg = AppUpdateConfig(latestVersionCode: 7);
      expect(cfg.isOutdated(6), isTrue);
    });

    test('allows the published build and anything newer', () {
      const cfg = AppUpdateConfig(latestVersionCode: 7);
      expect(cfg.isOutdated(7), isFalse);
      expect(cfg.isOutdated(8), isFalse);
    });

    test('never blocks when nothing has been released', () {
      const cfg = AppUpdateConfig(latestVersionCode: 0);
      expect(cfg.isOutdated(1), isFalse);
      expect(cfg.isOutdated(0), isFalse);
    });
  });

  group('AppUpdateConfig.fromMap', () {
    test('reads the version code written by Release Next Version', () {
      final cfg = AppUpdateConfig.fromMap({
        'latestVersionCode': 7,
        'latestVersionName': '1.3.0',
        'forceUpdate': true,
        'updateTitle': 'Faster matches',
        'updateMessage': 'Please update.',
        'playStoreUrl': 'https://play.google.com/store/apps/details?id=x',
      });
      expect(cfg.latestVersionCode, 7);
      expect(cfg.latestVersionName, '1.3.0');
      expect(cfg.forceUpdate, isTrue);
      expect(cfg.versionLabel, '1.3.0');
      expect(cfg.isOutdated(6), isTrue);
    });

    test('coerces a hand-edited string version code', () {
      final cfg = AppUpdateConfig.fromMap({'latestVersionCode': '9'});
      expect(cfg.latestVersionCode, 9);
    });

    test('a legacy document cannot gate the app', () {
      // Written by the old admin screen: version STRINGS only, no version code.
      final cfg = AppUpdateConfig.fromMap({
        'currentVersion': '1.4.0',
        'minSupportedVersion': '1.3.0',
        'forceUpdate': true,
      });
      expect(cfg.latestVersionCode, 0);
      expect(cfg.isOutdated(1), isFalse, reason: 'no version code → no gate');
      // The old string still serves as the display name.
      expect(cfg.latestVersionName, '1.4.0');
      expect(cfg.versionLabel, '1.4.0');
    });

    test('falls back to the version code for the badge when no name is set', () {
      final cfg = AppUpdateConfig.fromMap({'latestVersionCode': 7});
      expect(cfg.versionLabel, '7');
    });

    test('an empty document is inert', () {
      final cfg = AppUpdateConfig.fromMap(const {});
      expect(cfg.forceUpdate, isFalse);
      expect(cfg.latestVersionCode, 0);
      expect(cfg.versionLabel, isEmpty);
      expect(cfg.isOutdated(6), isFalse);
    });
  });
}
