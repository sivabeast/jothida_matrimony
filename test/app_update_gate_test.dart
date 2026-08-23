// The release gate decides whether a member is prompted — or LOCKED OUT — so
// its edge cases matter more than its happy path. These cover the scenarios in
// the spec plus the ways a bad config could wrongly block someone.

import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/models/app_update_config.dart';

AppUpdateConfig _config({
  int latest = 0,
  int minimum = 0,
  bool force = false,
  String url = '',
}) =>
    AppUpdateConfig(
      latestVersionCode: latest,
      minimumSupportedVersionCode: minimum,
      forceUpdate: force,
      playStoreUrl: url,
    );

void main() {
  group('update requirement', () {
    test('SCENARIO 1 — installed == latest gives no prompt', () {
      expect(_config(latest: 17).requirementFor(17),
          AppUpdateRequirement.none);
    });

    test('installed NEWER than latest gives no prompt', () {
      // A tester on an unreleased build must not be nagged.
      expect(_config(latest: 17).requirementFor(18),
          AppUpdateRequirement.none);
    });

    test('SCENARIO 2 — installed < latest is optional', () {
      expect(_config(latest: 17).requirementFor(16),
          AppUpdateRequirement.optional);
    });

    test('SCENARIO 3 — installed < minimum is forced', () {
      expect(_config(latest: 17, minimum: 15).requirementFor(14),
          AppUpdateRequirement.forced);
    });

    test('at the minimum exactly is NOT forced', () {
      // The floor is "below this", not "at or below" — an off-by-one here
      // would lock out the very members it was meant to keep.
      expect(_config(latest: 17, minimum: 15).requirementFor(15),
          AppUpdateRequirement.optional);
    });

    test('forceUpdate makes the latest release mandatory on its own', () {
      expect(_config(latest: 17, force: true).requirementFor(16),
          AppUpdateRequirement.forced);
    });

    test('forceUpdate never affects someone already current', () {
      expect(_config(latest: 17, force: true).requirementFor(17),
          AppUpdateRequirement.none);
    });
  });

  group('a bad config must never lock anyone out', () {
    test('an unconfigured document prompts nobody', () {
      expect(const AppUpdateConfig().requirementFor(5),
          AppUpdateRequirement.none);
      expect(const AppUpdateConfig().isConfigured, isFalse);
    });

    test('a minimum with no latest version still prompts nobody', () {
      // Half-filled config: without a latest version there is nothing to
      // update TO, so blocking would strand the member.
      expect(_config(minimum: 99).requirementFor(1),
          AppUpdateRequirement.none);
    });

    test('an unreadable installed version prompts nobody', () {
      // PackageInfo yields 0 when the build number cannot be parsed. Blocking
      // someone because we could not read our OWN version is the worst
      // possible failure mode.
      expect(_config(latest: 17, minimum: 15, force: true).requirementFor(0),
          AppUpdateRequirement.none);
    });
  });

  group('version code parsing', () {
    test('tolerates a string or double stored by an older admin build', () {
      expect(AppUpdateConfig.fromFirestoreMap({'latestVersionCode': '17'})
          .latestVersionCode, 17);
      expect(AppUpdateConfig.fromFirestoreMap({'latestVersionCode': 17.0})
          .latestVersionCode, 17);
    });

    test('an unparseable value disables the gate rather than enabling it', () {
      expect(AppUpdateConfig.fromFirestoreMap({'latestVersionCode': 'x'})
          .latestVersionCode, 0);
    });
  });

  group('play store url', () {
    test('blank falls back to the real listing', () {
      expect(_config().effectivePlayStoreUrl,
          AppUpdateConfig.defaultPlayStoreUrl);
      expect(AppUpdateConfig.defaultPlayStoreUrl,
          contains('com.jothida.jothida_matrimony'));
    });

    test('a non-Play URL is ignored', () {
      // An admin typo — or worse — must not send members off-platform.
      expect(_config(url: 'https://example.com/malware').effectivePlayStoreUrl,
          AppUpdateConfig.defaultPlayStoreUrl);
    });

    test('a real Play or market URL is honoured', () {
      const play = 'https://play.google.com/store/apps/details?id=x';
      expect(_config(url: play).effectivePlayStoreUrl, play);
      expect(_config(url: 'market://details?id=x').effectivePlayStoreUrl,
          'market://details?id=x');
    });
  });
}
