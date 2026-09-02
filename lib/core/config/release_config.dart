/// Release metadata that ships INSIDE the build (spec §10/§10D).
///
/// The app version is never typed by a human at runtime. Two of the three
/// numbers the update gate needs come from the build itself:
///
///   * **Current version** — `PackageInfo.buildNumber`, i.e. the `+N` in
///     `pubspec.yaml`. Read at runtime, never stored in code.
///   * **Minimum supported version** — [kMinimumSupportedVersionCode] below.
///     This is the only one that cannot be discovered at runtime, because it is
///     a decision about OLD builds that the old builds themselves cannot know.
///     It is set here, next to the code, and travels with the release.
///
/// The third — the **latest published version** — comes from Google Play (the
/// In-App Update API reports the version code live on the track) and from the
/// `app_config/update` document, which the newest build publishes on an admin's
/// device. Nobody types it either way.
///
/// ## Release checklist
///
/// Bump `version:` in `pubspec.yaml` for every release, as normal. Touch
/// [kMinimumSupportedVersionCode] ONLY when an older build genuinely must stop
/// working — a broken data migration, a security fix, a server contract that
/// changed. Raising it locks those members out of the app until they update, so
/// it is a deliberate act, not routine release hygiene.
library;

/// The oldest build code still allowed to run, as decided by THIS release.
///
/// `0` disables the floor entirely, which is the correct default: an ordinary
/// release makes the update available, it does not make it mandatory. Force
/// Update (an admin policy switch, see `AppUpdateConfig.forceUpdate`) is the
/// separate lever for insisting.
const int kMinimumSupportedVersionCode = 0;
