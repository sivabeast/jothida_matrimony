import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/master_data.dart';
import '../../providers/master_data_provider.dart';
import 'searchable_field.dart';

/// Dependent, searchable Religion → Caste → Sub-caste fields backed by the
/// Firestore master data (master_religions / master_castes / master_subcastes).
///
/// Controlled widget: the parent owns the six values (id + name for each level)
/// and passes three callbacks. The widget loads the correct scoped lists from
/// Firestore, enforces the dependency rules (changing Religion clears Caste &
/// Sub-caste; changing Caste clears Sub-caste) and reports the selected
/// **id + name** for each level. Replaces all hardcoded religion/caste lists.
class ReligionCasteFields extends ConsumerWidget {
  final String? religionId;
  final String? religionName;
  final String? casteId;
  final String? casteName;
  final String? subCasteId;
  final String? subCasteName;

  /// Each callback delivers the selected (id, name) — both null when cleared.
  final void Function(String? id, String? name) onReligionChanged;
  final void Function(String? id, String? name) onCasteChanged;
  final void Function(String? id, String? name) onSubcasteChanged;

  final bool religionRequired;
  final bool casteRequired;
  final bool subcasteRequired;
  /// Set false to render only Religion + Caste (e.g. Partner Preferences, which
  /// has no sub-caste field).
  final bool showSubcaste;
  final double gap;

  const ReligionCasteFields({
    super.key,
    required this.religionId,
    required this.religionName,
    required this.casteId,
    required this.casteName,
    required this.subCasteId,
    required this.subCasteName,
    required this.onReligionChanged,
    required this.onCasteChanged,
    required this.onSubcasteChanged,
    this.religionRequired = true,
    this.casteRequired = true,
    this.subcasteRequired = false,
    this.showSubcaste = true,
    this.gap = 16,
  });

  bool get _hasReligion => religionId != null && religionId!.isNotEmpty;
  bool get _hasCaste => casteId != null && casteId!.isNotEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final religionsAsync = ref.watch(religionsProvider);
    final castesAsync = _hasReligion
        ? ref.watch(castesProvider(religionId!))
        : const AsyncValue<List<Caste>>.data(<Caste>[]);
    final subcastesAsync = _hasCaste
        ? ref.watch(subcastesProvider(casteId!))
        : const AsyncValue<List<Subcaste>>.data(<Subcaste>[]);

    final religions = religionsAsync.valueOrNull ?? const <Religion>[];
    final castes = castesAsync.valueOrNull ?? const <Caste>[];
    final subcastes = subcastesAsync.valueOrNull ?? const <Subcaste>[];

    final religionNames = religions.map((r) => r.name).toList();
    final casteNames = castes.map((c) => c.name).toList();
    final subcasteNames = subcastes.map((s) => s.name).toList();

    return Column(
      children: [
        SearchableField(
          label: 'Religion',
          prefixIcon: Icons.spa_outlined,
          isRequired: religionRequired,
          enabled: !religionsAsync.isLoading,
          items: religionNames,
          selectedItem: _inList(religionName, religionNames),
          onChanged: (name) {
            final r = _byName(religions, name, (x) => x.name);
            onReligionChanged(r?.id, r?.name);
            // Dependency reset.
            onCasteChanged(null, null);
            onSubcasteChanged(null, null);
          },
        ),
        SizedBox(height: gap),
        SearchableField(
          label: 'Caste',
          prefixIcon: Icons.groups_outlined,
          isRequired: casteRequired,
          enabled: _hasReligion && !castesAsync.isLoading,
          items: casteNames,
          selectedItem: _inList(casteName, casteNames),
          onChanged: (name) {
            final c = _byName(castes, name, (x) => x.name);
            onCasteChanged(c?.id, c?.name);
            onSubcasteChanged(null, null);
          },
        ),
        if (showSubcaste) ...[
          SizedBox(height: gap),
          SearchableField(
            label: 'Sub Caste',
            prefixIcon: Icons.account_tree_outlined,
            isRequired: subcasteRequired,
            enabled: _hasCaste && !subcastesAsync.isLoading,
            items: subcasteNames,
            selectedItem: _inList(subCasteName, subcasteNames),
            onChanged: (name) {
              final s = _byName(subcastes, name, (x) => x.name);
              onSubcasteChanged(s?.id, s?.name);
            },
          ),
        ],
      ],
    );
  }

  /// dropdown_search requires the selected value to be present in [items];
  /// otherwise show nothing (e.g. while the list is still loading, or for a
  /// legacy free-text value not in the master list).
  static String? _inList(String? name, List<String> items) =>
      (name != null && name.isNotEmpty && items.contains(name)) ? name : null;

  static T? _byName<T>(List<T> list, String? name, String Function(T) nameOf) {
    if (name == null) return null;
    for (final x in list) {
      if (nameOf(x) == name) return x;
    }
    return null;
  }
}
