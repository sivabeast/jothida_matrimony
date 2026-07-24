// Generates the Google Play Store "hi-res app icon" (exactly 512×512 PNG)
// from the branded master, for upload under Play Console → Store listing.
//
// The installed-app launcher icons are generated separately by
// `dart run flutter_launcher_icons` (see pubspec.yaml). This script only
// produces the Console store-listing asset, which is NOT part of the AAB.
//
// Run:  dart run tool/gen_play_store_icon.dart
// Out:  branding/play_store_icon_512.png
import 'dart:io';
import 'package:image/image.dart' as img;

const _src = 'assets/images/report_logo.png';
const _outDir = 'branding';
const _out = '$_outDir/play_store_icon_512.png';

void main() {
  final srcFile = File(_src);
  if (!srcFile.existsSync()) {
    stderr.writeln('ERROR: source not found: $_src');
    exit(1);
  }

  final decoded = img.decodePng(srcFile.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('ERROR: could not decode $_src as PNG');
    exit(1);
  }

  // Play requires exactly 512×512, 32-bit PNG. Flatten onto the brand maroon
  // first so any transparent pixels never render as artefacts in the Console.
  final maroon = img.Image(width: decoded.width, height: decoded.height)
    ..clear(img.ColorRgb8(0x8B, 0x00, 0x00));
  img.compositeImage(maroon, decoded);

  final resized = img.copyResize(
    maroon,
    width: 512,
    height: 512,
    interpolation: img.Interpolation.cubic,
  );

  Directory(_outDir).createSync(recursive: true);
  File(_out).writeAsBytesSync(img.encodePng(resized));
  stdout.writeln('Wrote $_out (${resized.width}x${resized.height})');
}
