/// The ONE application logo (spec §5).
///
/// Everything that shows the brand mark — launcher icon, Play Store icon,
/// splash, login, loading, app bars, drawer, report headers, exported PDFs —
/// renders THIS asset. There is deliberately no second "report", "launcher" or
/// "store" variant any more: one file, one look, everywhere.
///
/// The artwork is a full-bleed square: the red plate reaches all four edges
/// (only its rounded corners are transparent), because every render site feeds
/// it through `BoxFit.cover` and clips to a circle or squircle. A version with
/// a transparent margin would shrink inside those clips and, on
/// [AppLauncherLogo]'s white plate, ring the logo in white.
///
/// To change the logo, run ONE command with the new artwork — it trims the
/// margin, rewrites this master and regenerates every Android and Play icon:
///
/// ```
/// python tool/generate_brand_icons.py path/to/new_logo.png --write-master
/// ```
///
/// Do not hand-replace this file alone: the Android bitmaps under
/// `android/app/src/main/res/` are separate copies and would keep the old mark.
const String kAppLogoAsset = 'assets/images/app_logo.png';
