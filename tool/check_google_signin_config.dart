// Verifies the Android Google Sign-In configuration end to end.
//
//   dart run tool/check_google_signin_config.dart
//
// Checks, in order:
//   1. android/app/google-services.json exists and matches the applicationId
//      in android/app/build.gradle.
//   2. lib/firebase_options.dart agrees with google-services.json (same
//      project / app id / api key).
//   3. The web OAuth client (client_type 3) exists and is the one passed as
//      `serverClientId` in lib/services/firebase/auth_service.dart.
//   4. EVERY signing key this project can produce (debug + release/upload) has
//      its SHA-1 registered as an Android OAuth client (client_type 1).
//
// Step 4 is the one that silently breaks release builds: an APK/AAB signed
// with a key whose SHA-1 is not registered gets no ID token back from Google,
// so sign-in cannot complete no matter how correct the Dart code is.
//
// Exits non-zero when something is wrong, so CI can gate on it.

import 'dart:convert';
import 'dart:io';

const _reset = '\x1B[0m';
const _red = '\x1B[31m';
const _green = '\x1B[32m';
const _yellow = '\x1B[33m';
const _bold = '\x1B[1m';

var _failures = 0;

void _ok(String message) => print('$_green  OK $_reset $message');
void _warn(String message) => print('$_yellow WARN$_reset $message');
void _fail(String message) {
  _failures++;
  print('$_red FAIL$_reset $message');
}

void _section(String title) => print('\n$_bold$title$_reset');

Future<void> main() async {
  final root = Directory.current;
  print('${_bold}Google Sign-In configuration check$_reset  (${root.path})');

  // ── 1. google-services.json ↔ build.gradle ────────────────────────────────
  _section('1. google-services.json');
  final gsFile = File('android/app/google-services.json');
  if (!gsFile.existsSync()) {
    _fail('android/app/google-services.json is missing. Download it from the '
        'Firebase console (Project settings → Your apps → Android).');
    exit(1);
  }
  final gs = jsonDecode(gsFile.readAsStringSync()) as Map<String, dynamic>;
  final projectId =
      (gs['project_info'] as Map<String, dynamic>)['project_id'] as String?;
  _ok('project: $projectId');

  final applicationId = _applicationIdFromGradle();
  if (applicationId == null) {
    _warn('could not read applicationId from android/app/build.gradle');
  }

  final clients = (gs['client'] as List<dynamic>).cast<Map<String, dynamic>>();
  final client = clients.firstWhere(
    (c) =>
        ((c['client_info'] as Map<String, dynamic>)['android_client_info']
            as Map<String, dynamic>)['package_name'] ==
        applicationId,
    orElse: () => <String, dynamic>{},
  );
  if (client.isEmpty) {
    _fail('no client in google-services.json for package "$applicationId". '
        'Add an Android app with that exact package name in Firebase.');
    exit(1);
  }
  final appId =
      (client['client_info'] as Map<String, dynamic>)['mobilesdk_app_id']
          as String?;
  _ok('package "$applicationId" → app id $appId');

  // ── 2. firebase_options.dart agreement ────────────────────────────────────
  _section('2. lib/firebase_options.dart');
  final optionsFile = File('lib/firebase_options.dart');
  if (!optionsFile.existsSync()) {
    _fail('lib/firebase_options.dart is missing — run `flutterfire configure`.');
  } else {
    final options = optionsFile.readAsStringSync();
    final apiKey = ((client['api_key'] as List<dynamic>?)?.first
        as Map<String, dynamic>?)?['current_key'] as String?;
    if (appId != null && options.contains(appId)) {
      _ok('appId matches google-services.json');
    } else {
      _fail('the Android appId in firebase_options.dart does not match '
          'google-services.json — re-run `flutterfire configure`.');
    }
    if (apiKey != null && options.contains(apiKey)) {
      _ok('apiKey matches google-services.json');
    } else {
      _fail('the Android apiKey in firebase_options.dart does not match '
          'google-services.json — re-run `flutterfire configure`.');
    }
    if (projectId != null && options.contains(projectId)) {
      _ok('projectId matches google-services.json');
    } else {
      _fail('projectId mismatch between firebase_options.dart and '
          'google-services.json.');
    }
  }

  // ── 3. Web OAuth client (serverClientId) ──────────────────────────────────
  _section('3. Web OAuth client (serverClientId)');
  final oauthClients =
      (client['oauth_client'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>();
  final webClients = oauthClients
      .where((o) => o['client_type'] == 3)
      .map((o) => o['client_id'] as String)
      .toList();
  if (webClients.isEmpty) {
    _fail('no web OAuth client (client_type 3) in google-services.json. '
        'Enable Google under Authentication → Sign-in method, then '
        're-download the file.');
  } else {
    _ok('web client: ${webClients.first}');
    final authService =
        File('lib/services/firebase/auth_service.dart').readAsStringSync();
    if (webClients.any(authService.contains)) {
      _ok('AuthService passes this client id as serverClientId');
    } else {
      _fail('the serverClientId hard-coded in AuthService is NOT the web '
          'client in google-services.json. Update it to '
          '"${webClients.first}".');
    }
  }

  // ── 4. Signing keys ↔ registered SHA-1 fingerprints ───────────────────────
  _section('4. Signing certificates (SHA-1)');
  final registered = oauthClients
      .where((o) => o['client_type'] == 1)
      .map((o) => ((o['android_info'] as Map<String, dynamic>?)?[
              'certificate_hash'] as String?) ??
          '')
      .where((h) => h.isNotEmpty)
      .map((h) => h.toLowerCase())
      .toSet();
  if (registered.isEmpty) {
    _fail('no Android OAuth client (client_type 1) at all — Google Sign-In '
        'cannot work in any build. Add your SHA-1 fingerprints in Firebase.');
  } else {
    for (final hash in registered) {
      _ok('registered SHA-1: ${_pretty(hash)}');
    }
  }

  final keytool = _findKeytool();
  if (keytool == null) {
    _warn('keytool not found — skipping the local keystore comparison. '
        'Install a JDK (or Android Studio) to enable it.');
  } else {
    for (final key in _keystores()) {
      final sha1 = _sha1Of(keytool, key);
      if (sha1 == null) {
        _warn('${key.label}: could not read ${key.path} (wrong password?)');
        continue;
      }
      final normalised = sha1.replaceAll(':', '').toLowerCase();
      if (registered.contains(normalised)) {
        _ok('${key.label} SHA-1 $sha1 is registered');
      } else {
        _fail('${key.label} SHA-1 $sha1 is NOT registered in Firebase.\n'
            '       Builds signed with this key cannot obtain a Google ID '
            'token, so sign-in will never complete.\n'
            '       Fix: Firebase console → Project settings → Your apps → '
            '$applicationId → Add fingerprint → paste the SHA-1 (and the '
            'SHA-256), then re-download google-services.json.');
      }
    }
    _warn('If the app ships through Google Play with Play App Signing, also '
        'register the SHA-1 shown under Play Console → Release → Setup → App '
        'signing → "App signing key certificate". That key — not the upload '
        'key — signs what users install.');
  }

  print('');
  if (_failures == 0) {
    print('${_green}All checks passed.$_reset');
  } else {
    print('$_red$_failures check(s) failed.$_reset');
  }
  exit(_failures == 0 ? 0 : 1);
}

String _pretty(String hash) {
  final pairs = <String>[];
  for (var i = 0; i + 1 < hash.length; i += 2) {
    pairs.add(hash.substring(i, i + 2).toUpperCase());
  }
  return pairs.join(':');
}

String? _applicationIdFromGradle() {
  final gradle = File('android/app/build.gradle');
  if (!gradle.existsSync()) return null;
  final match = RegExp(r'applicationId\s*=?\s*"([^"]+)"')
      .firstMatch(gradle.readAsStringSync());
  return match?.group(1);
}

class _Keystore {
  final String label;
  final String path;
  final String storePassword;
  final String alias;
  const _Keystore(this.label, this.path, this.storePassword, this.alias);
}

List<_Keystore> _keystores() {
  final keys = <_Keystore>[];
  if (File('ci/debug.keystore').existsSync()) {
    keys.add(const _Keystore(
        'debug', 'ci/debug.keystore', 'android', 'androiddebugkey'));
  }
  // Release credentials live in android/key.properties (git-ignored).
  final props = File('android/key.properties');
  if (props.existsSync()) {
    final values = <String, String>{};
    for (final line in props.readAsLinesSync()) {
      final i = line.indexOf('=');
      if (i > 0) values[line.substring(0, i).trim()] = line.substring(i + 1).trim();
    }
    final storeFile = values['storeFile'];
    if (storeFile != null) {
      // storeFile is relative to android/.
      final path = storeFile.startsWith('..')
          ? 'android/${storeFile.substring(3)}'
          : 'android/$storeFile';
      if (File(path).existsSync()) {
        keys.add(_Keystore('release/upload', path,
            values['storePassword'] ?? '', values['keyAlias'] ?? 'upload'));
      }
    }
  }
  return keys;
}

String? _findKeytool() {
  final candidates = <String>[
    'keytool',
    r'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe',
    r'C:\Program Files\Java\jdk\bin\keytool.exe',
    '/usr/bin/keytool',
    '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool',
  ];
  for (final c in candidates) {
    try {
      final r = Process.runSync(c, ['-help']);
      if (r.exitCode == 0 || (r.stderr as String).contains('keytool')) return c;
    } catch (_) {
      // try the next candidate
    }
  }
  return null;
}

String? _sha1Of(String keytool, _Keystore key) {
  final result = Process.runSync(keytool, [
    '-list',
    '-v',
    '-keystore',
    key.path,
    '-storepass',
    key.storePassword,
    '-alias',
    key.alias,
  ]);
  final out = '${result.stdout}${result.stderr}';
  return RegExp(r'SHA1:\s*([0-9A-Fa-f:]+)').firstMatch(out)?.group(1);
}
