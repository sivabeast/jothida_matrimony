// Folds the places MEMBERS added in the app into the bundled location JSON.
//
// Members add villages from the place picker ("+ Add"); they are stored in
// Firestore `master_options/places` (the APK's JSON assets are read-only on a
// phone, and the project has no Cloud Functions to rewrite a file). The app
// merges them in at runtime. Run this before a release to write them into
// assets/master_data/location/cities_en.json and cities_ta.json as well, so
// they ship in the APK and work before the first sync.
//
//   dart run tool/merge_place_additions.dart                 (preview only)
//   dart run tool/merge_place_additions.dart --write         (update the JSON)
//   dart run tool/merge_place_additions.dart --input places.json [--write]
//
// Without --input the document is read over the Firestore REST API using a
// throw-away anonymous session (the document is readable by any signed-in
// visitor), which is deleted again afterwards. --input takes a saved copy of
// the document (`{"entries": [...]}`) or a plain array of rows instead.
//
// Rules: existing rows are never changed, reordered or removed. A Tamil Nadu
// place is appended with its own id (>= 100001, so profiles that stored that
// id keep matching) unless its district already lists the same name — ignoring
// case, spacing and transliteration — or the id is already present. Places
// outside Tamil Nadu are reported but left in Firestore: the bundled dataset
// covers Tamil Nadu only.
import 'dart:convert';
import 'dart:io';

import 'package:jothida_matrimony/core/utils/place_additions.dart';

const _dir = 'assets/master_data/location';

Future<void> main(List<String> args) async {
  final write = args.contains('--write');
  final inputAt = args.indexOf('--input');
  final List<Object?> rawEntries;
  if (inputAt >= 0) {
    if (inputAt + 1 >= args.length) _fail('--input needs a file path');
    rawEntries = _entriesOf(
      jsonDecode(File(args[inputAt + 1]).readAsStringSync()),
    );
  } else {
    rawEntries = await _fetchEntries();
  }

  final additions = parsePlaceAdditions(rawEntries);
  final result = mergePlaceAdditionsIntoAssets(
    citiesEn: _readRows('$_dir/cities_en.json'),
    citiesTa: _readRows('$_dir/cities_ta.json'),
    districtIds: {
      for (final r in _readRows('$_dir/districts_en.json'))
        (r['id'] as num).toInt(),
    },
    additions: additions,
  );

  stdout.writeln('Member-added places: ${additions.length}');
  for (final line in result.report) {
    stdout.writeln('  $line');
  }
  stdout.writeln('To append: ${result.appended}');
  if (result.appended == 0) return;
  if (!write) {
    stdout.writeln('Preview only — run again with --write to update the JSON.');
    return;
  }
  _writeRows('$_dir/cities_en.json', result.citiesEn);
  _writeRows('$_dir/cities_ta.json', result.citiesTa);
  stdout.writeln('Updated $_dir/cities_en.json and cities_ta.json.');
}

/// The pure merge, kept separate from file and network access.
({
  List<Map<String, dynamic>> citiesEn,
  List<Map<String, dynamic>> citiesTa,
  int appended,
  List<String> report,
})
mergePlaceAdditionsIntoAssets({
  required List<Map<String, dynamic>> citiesEn,
  required List<Map<String, dynamic>> citiesTa,
  required Set<int> districtIds,
  required List<PlaceAddition> additions,
}) {
  final en = [...citiesEn];
  final ta = [...citiesTa];
  final ids = {for (final r in en) (r['id'] as num).toInt()};
  final keys = <String>{
    for (final r in [...en, ...ta])
      '${r['districtId']}|${placeNameKey('${r['name']}')}',
  };
  final report = <String>[];
  var appended = 0;
  for (final a in additions) {
    final label = '#${a.id} ${a.name}';
    if (!a.isTamilNadu) {
      report.add(
        '$label (${a.parentLabel}) — outside Tamil Nadu, kept in '
        'Firestore only',
      );
      continue;
    }
    if (!districtIds.contains(a.districtId)) {
      report.add('$label — unknown district ${a.districtId}, skipped');
      continue;
    }
    if (ids.contains(a.id)) {
      report.add('$label — id already in the JSON, skipped');
      continue;
    }
    final key = '${a.districtId}|${placeNameKey(a.name)}';
    if (keys.contains(key)) {
      report.add('$label — district ${a.districtId} already lists it, skipped');
      continue;
    }
    en.add({'id': a.id, 'districtId': a.districtId, 'name': a.name});
    ta.add({
      'id': a.id,
      'districtId': a.districtId,
      'name': a.nameTa.trim().isEmpty ? a.name : a.nameTa,
    });
    ids.add(a.id);
    keys.add(key);
    appended++;
    report.add('$label — district ${a.districtId}: append');
  }
  return (citiesEn: en, citiesTa: ta, appended: appended, report: report);
}

List<Object?> _entriesOf(Object? decoded) {
  if (decoded is List) return decoded;
  if (decoded is Map && decoded['entries'] is List) {
    return decoded['entries'] as List;
  }
  _fail('Expected {"entries": [...]} or a JSON array of rows');
}

List<Map<String, dynamic>> _readRows(String path) => [
  for (final r in jsonDecode(File(path).readAsStringSync()) as List)
    Map<String, dynamic>.from(r as Map),
];

void _writeRows(String path, List<Map<String, dynamic>> rows) => File(
  path,
).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(rows)}\n');

Never _fail(String message) {
  stderr.writeln(message);
  exit(64);
}

// ── Firestore REST ──────────────────────────────────────────────────────────

Future<List<Object?>> _fetchEntries() async {
  final options = File('lib/firebase_options.dart').readAsStringSync();
  final android = options.substring(options.indexOf('FirebaseOptions android'));
  final apiKey = RegExp(r"apiKey: '([^']+)'").firstMatch(android)?.group(1);
  final project = RegExp(r"projectId: '([^']+)'").firstMatch(android)?.group(1);
  if (apiKey == null || project == null) {
    _fail('Could not read apiKey/projectId from lib/firebase_options.dart');
  }
  final client = HttpClient();
  try {
    final session = await _json(
      client,
      'POST',
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey',
      body: {'returnSecureToken': true},
    );
    final token = '${session['idToken']}';
    try {
      final doc = await _json(
        client,
        'GET',
        'https://firestore.googleapis.com/v1/projects/$project/databases/'
            '(default)/documents/master_options/places',
        token: token,
        allowMissing: true,
      );
      final fields = doc['fields'] as Map?;
      if (fields == null) return const [];
      return (_value(fields['entries']) as List?) ?? const [];
    } finally {
      await _json(
        client,
        'POST',
        'https://identitytoolkit.googleapis.com/v1/accounts:delete?key=$apiKey',
        body: {'idToken': token},
      );
    }
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>> _json(
  HttpClient client,
  String method,
  String url, {
  Map<String, Object?>? body,
  String? token,
  bool allowMissing = false,
}) async {
  final request = await client.openUrl(method, Uri.parse(url));
  request.headers.contentType = ContentType.json;
  if (token != null) request.headers.set('Authorization', 'Bearer $token');
  if (body != null) request.write(jsonEncode(body));
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  if (response.statusCode == 404 && allowMissing) return const {};
  if (response.statusCode >= 300) {
    _fail('$method $url failed (${response.statusCode}): $text');
  }
  return jsonDecode(text) as Map<String, dynamic>;
}

/// A Firestore REST typed value → plain Dart.
Object? _value(Object? v) {
  if (v is! Map) return null;
  if (v.containsKey('stringValue')) return v['stringValue'];
  if (v.containsKey('integerValue')) return int.parse('${v['integerValue']}');
  if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
  if (v.containsKey('booleanValue')) return v['booleanValue'];
  if (v.containsKey('nullValue')) return null;
  if (v.containsKey('arrayValue')) {
    return [
      for (final e in ((v['arrayValue'] as Map)['values'] as List? ?? const []))
        _value(e),
    ];
  }
  if (v.containsKey('mapValue')) {
    final fields = (v['mapValue'] as Map)['fields'] as Map? ?? const {};
    return {for (final e in fields.entries) '${e.key}': _value(e.value)};
  }
  return null;
}
