/// The ONE application logo (spec §5).
///
/// Everything that shows the brand mark — launcher icon, Play Store icon,
/// splash, login, loading, app bars, drawer, report headers, exported PDFs —
/// renders THIS asset. There is deliberately no second "report" or "launcher"
/// variant any more: one file, one look, everywhere.
///
/// To change the logo, replace `assets/images/app_logo.png` with a square
/// 1024×1024 PNG and regenerate the Android launcher icons:
///
/// ```
/// flutter pub get
/// dart run flutter_launcher_icons
/// ```
///
/// (`pubspec.yaml` → `flutter_launcher_icons.image_path` already points here,
/// so the launcher icon and the in-app logo can never drift apart.)
const String kAppLogoAsset = 'assets/images/app_logo.png';
