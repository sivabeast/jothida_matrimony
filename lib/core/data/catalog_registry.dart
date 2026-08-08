import '../utils/value_l10n.dart';
import 'education_catalog.dart';
import 'location_catalog.dart';
import 'master_option.dart';
import 'occupation_catalog.dart';

/// Feeds every bilingual catalogue into the value localizer, so a stored value
/// renders in Tamil **everywhere** — profile cards, the view screen, search
/// results, exported PDFs — and not just inside the picker that produced it
/// (§8).
///
/// Call once during app start-up. It is synchronous and cheap (the catalogues
/// are `const`), and re-running it is harmless.
///
/// This lives apart from the catalogues themselves on purpose: the catalogues
/// stay free of any Flutter import so `tool/export_master_data.dart` can run
/// them under plain `dart run`, and only this file bridges them to
/// `value_l10n.dart`.
void registerCatalogTamilNames() {
  // Degrees and occupations keep the English term in brackets, matching how
  // the pickers render them — "இளங்கலை அறிவியல் (B.Sc)". The English form is
  // what people say out loud, so dropping it would make a profile card harder
  // to read, not easier.
  final withEnglish = <String, String>{
    for (final d in EducationCatalog.allDegrees)
      if (d.ta.isNotEmpty) d.en: '${d.ta} (${d.en})',
    for (final o in OccupationCatalog.allOccupations)
      if (o.ta.isNotEmpty) o.en: '${o.ta} (${o.en})',
  };

  // Ordinary vocabulary is pure Tamil.
  final plain = <String, String>{
    for (final l in EducationCatalog.levels)
      if (l.ta.isNotEmpty) l.en: l.ta,
    for (final s in OccupationCatalog.statuses)
      if (s.ta.isNotEmpty) s.en: s.ta,
    for (final status in OccupationCatalog.statuses)
      for (final t in OccupationCatalog.typesFor(status.en))
        if (t.ta.isNotEmpty) t.en: t.ta,
    for (final c in LocationCatalog.countries)
      if (c.ta.isNotEmpty) c.en: c.ta,
    for (final s in LocationCatalog.indianStates)
      if (s.ta.isNotEmpty) s.en: s.ta,
  };

  registerMasterTamilNames({...plain, ...withEnglish});
}

/// Every value the catalogues can produce, for tests and admin filters.
List<MasterOption> get allCatalogOptions => [
      ...EducationCatalog.levels,
      ...EducationCatalog.allDegrees,
      ...OccupationCatalog.statuses,
      ...OccupationCatalog.allOccupations,
      ...LocationCatalog.countries,
      ...LocationCatalog.indianStates,
    ];
