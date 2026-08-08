// Exports the in-code bilingual catalogues to JSON, in the exact shape
// `master_data/{key}` documents use in Firestore (§7).
//
// The catalogues live in Dart (lib/core/data/*_catalog.dart) because the
// profile wizard reads them synchronously while the member types — an async
// fetch there would mean an empty dropdown on a cold start. This script is the
// bridge to the database: run it whenever a catalogue changes, then seed the
// generated files the same way the religion/caste datasets are seeded.
//
// Run:  dart run tool/export_master_data.dart
// Out:  assets/master_data/career/*.json, assets/master_data/location/*.json
import 'dart:convert';
import 'dart:io';

import '../lib/core/data/education_catalog.dart';
import '../lib/core/data/location_catalog.dart';
import '../lib/core/data/master_option.dart';
import '../lib/core/data/occupation_catalog.dart';

const _careerDir = 'assets/master_data/career';
const _locationDir = 'assets/master_data/location';

void _write(String path, List<MasterOption> options) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  final json = const JsonEncoder.withIndent('  ')
      .convert([for (final o in options) o.toMap()]);
  file.writeAsStringSync('$json\n');
  stdout.writeln('  ${options.length.toString().padLeft(4)}  $path');
}

void main() {
  stdout.writeln('Exporting bilingual master data…');

  // ── Education ────────────────────────────────────────────────────────────
  _write('$_careerDir/education_levels.json', EducationCatalog.levels);
  _write('$_careerDir/degrees.json', [
    for (final entry in EducationCatalog.degreesByLevel.entries)
      for (final d in entry.value)
        MasterOption(
          id: d.id,
          en: d.en,
          ta: d.ta,
          aliases: d.aliases,
          parentId: EducationCatalog.levels.byValue(entry.key)?.id,
        ),
  ]);

  // ── Employment ───────────────────────────────────────────────────────────
  _write('$_careerDir/employment_statuses.json', OccupationCatalog.statuses);
  _write('$_careerDir/employment_types.json', [
    for (final status in OccupationCatalog.statuses)
      for (final t in OccupationCatalog.typesFor(status.en))
        MasterOption(
          id: '${status.id}__${t.id}',
          en: t.en,
          ta: t.ta,
          aliases: t.aliases,
          parentId: status.id,
        ),
  ]);
  // Occupations belong to several employment types at once, so the export
  // carries the type list and the education tier rather than a single parent.
  final occFile = File('$_careerDir/occupations.json');
  occFile.parent.createSync(recursive: true);
  occFile.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert([
        for (final e in OccupationCatalog.all)
          {
            ...e.option.toMap(),
            'types': e.types.toList()..sort(),
            'educationTier': e.tier,
          },
      ])}\n');
  stdout.writeln('  ${OccupationCatalog.all.length.toString().padLeft(4)}  '
      '$_careerDir/occupations.json');

  // ── Location ─────────────────────────────────────────────────────────────
  _write('$_locationDir/countries.json', LocationCatalog.countries);
  _write('$_locationDir/states.json', [
    for (final s in LocationCatalog.indianStates)
      MasterOption(
        id: s.id,
        en: s.en,
        ta: s.ta,
        aliases: s.aliases,
        parentId: 'ctry_india',
      ),
  ]);

  stdout.writeln('\nDONE. Seed these alongside the religion/caste datasets; '
      'MasterDataService reads master_data/{key} first and falls back to the '
      'bundled asset.');
}
