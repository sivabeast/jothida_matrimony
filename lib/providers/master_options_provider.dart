import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase/master_options_service.dart';

export '../services/firebase/master_options_service.dart'
    show MasterOption, MasterOptionsService;

/// Singleton service for the user-added "+ Add" dropdown values.
final masterOptionsServiceProvider =
    Provider<MasterOptionsService>((ref) => MasterOptionsService());

/// Live CUSTOM entries for a dropdown [type] — merged by callers into the
/// canonical (asset/constant) list. Streams, so a value added by ANY user
/// appears everywhere immediately.
final customOptionsProvider =
    StreamProvider.family<List<MasterOption>, String>((ref, type) {
  return ref.watch(masterOptionsServiceProvider).watch(type);
});

/// Convenience: the custom VALUES for [type] scoped to [parent] ('' = flat
/// list). Empty while loading / on error, so merging is always safe.
List<String> customValuesOf(Ref ref, String type, {String parent = ''}) {
  final entries = ref.watch(customOptionsProvider(type)).valueOrNull ??
      const <MasterOption>[];
  final p = parent.trim().toLowerCase();
  return [
    for (final e in entries)
      if (e.parent.trim().toLowerCase() == p) e.value,
  ];
}

/// Widget-side variant of [customValuesOf] for ConsumerWidgets.
List<String> customValues(WidgetRef ref, String type, {String parent = ''}) {
  final entries = ref.watch(customOptionsProvider(type)).valueOrNull ??
      const <MasterOption>[];
  final p = parent.trim().toLowerCase();
  return [
    for (final e in entries)
      if (e.parent.trim().toLowerCase() == p) e.value,
  ];
}

/// Merges [base] + [custom], de-duplicated case-insensitively (base spelling
/// wins) and with every "Other"/"Others" sentinel REMOVED — the "+ Add"
/// button replaces the old Others→textbox flow entirely.
List<String> mergeOptions(List<String> base, List<String> custom) {
  final seen = <String>{};
  final out = <String>[];
  for (final v in [...base, ...custom]) {
    final t = v.trim();
    if (t.isEmpty) continue;
    final k = t.toLowerCase();
    if (k == 'other' || k == 'others') continue;
    if (seen.add(k)) out.add(t);
  }
  return out;
}
