import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/master_data.dart';
import '../../providers/master_data_provider.dart';
import '../../providers/master_options_provider.dart';
import 'searchable_field.dart';

/// Sentinel id stored for a user-added (custom) religion/caste/subcaste, so
/// the value round-trips: a non-empty name with this id means "custom".
/// (Kept as 'other' for backward compatibility with already-saved profiles.)
const String kOtherMasterId = 'other';

/// Dependent, searchable Religion → Caste → Sub-caste fields backed by the
/// master data (bundled JSON, with Firestore fallback — see [MasterDataService])
/// PLUS the `master_options` overlay of user-added values.
///
/// Controlled widget: the parent owns the six values (id + name for each level)
/// and passes three callbacks. The widget loads the correct scoped lists,
/// enforces the dependency rules (changing Religion clears Caste & Sub-caste;
/// changing Caste clears Sub-caste) and reports the selected **id + name**.
///
/// There is NO "Other → textbox" any more: each level has a **"+" Add**
/// button that saves the new value PERMANENTLY to the master database
/// (scoped to its parent), making it instantly available to every user,
/// the admin panel, search and filters.
class ReligionCasteFields extends ConsumerStatefulWidget {
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

  @override
  ConsumerState<ReligionCasteFields> createState() =>
      _ReligionCasteFieldsState();
}

class _ReligionCasteFieldsState extends ConsumerState<ReligionCasteFields> {
  bool get _religionCustom => widget.religionId == kOtherMasterId;
  bool get _casteCustom => widget.casteId == kOtherMasterId;

  bool get _hasReligion =>
      (widget.religionId ?? '').isNotEmpty ||
      (widget.religionName ?? '').isNotEmpty;
  bool get _hasCaste =>
      (widget.casteId ?? '').isNotEmpty || (widget.casteName ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final religionsAsync = ref.watch(religionsProvider);
    // A custom parent has no master children — only the overlay applies.
    final castesAsync = (_hasReligion && !_religionCustom &&
            (widget.religionId ?? '').isNotEmpty)
        ? ref.watch(castesProvider(widget.religionId!))
        : const AsyncValue<List<Caste>>.data(<Caste>[]);
    final subcastesAsync =
        (_hasCaste && !_casteCustom && (widget.casteId ?? '').isNotEmpty)
            ? ref.watch(subcastesProvider(widget.casteId!))
            : const AsyncValue<List<Subcaste>>.data(<Subcaste>[]);

    final religions = religionsAsync.valueOrNull ?? const <Religion>[];
    final castes = castesAsync.valueOrNull ?? const <Caste>[];
    final subcastes = subcastesAsync.valueOrNull ?? const <Subcaste>[];

    // Master names + user-added values (custom children are scoped by the
    // PARENT NAME, which works for both master and custom parents).
    final religionItems = _withSelected(
        mergeOptions(religions.map((r) => r.name).toList(),
            customValues(ref, MasterOptionsService.religion)),
        widget.religionName);
    final casteItems = _withSelected(
        mergeOptions(
            castes.map((c) => c.name).toList(),
            customValues(ref, MasterOptionsService.caste,
                parent: widget.religionName ?? '')),
        widget.casteName);
    final subcasteItems = _withSelected(
        mergeOptions(
            subcastes.map((s) => s.name).toList(),
            customValues(ref, MasterOptionsService.subcaste,
                parent: widget.casteName ?? '')),
        widget.subCasteName);

    final options = ref.read(masterOptionsServiceProvider);

    return Column(
      children: [
        // ── Religion ──
        SearchableField(
          label: 'Religion',
          prefixIcon: Icons.spa_outlined,
          isRequired: widget.religionRequired,
          enabled: !religionsAsync.isLoading,
          items: religionItems,
          selectedItem: _inList(widget.religionName, religionItems),
          onAddNew: (v) =>
              options.add(MasterOptionsService.religion, value: v),
          onChanged: (name) {
            final r = _byName(religions, name, (x) => x.name);
            if (r != null) {
              widget.onReligionChanged(r.id, r.name);
            } else if ((name ?? '').trim().isNotEmpty) {
              widget.onReligionChanged(kOtherMasterId, name!.trim());
            } else {
              widget.onReligionChanged(null, null);
            }
            // Religion changed → clear caste & sub-caste.
            widget.onCasteChanged(null, null);
            widget.onSubcasteChanged(null, null);
            setState(() {});
          },
        ),
        SizedBox(height: widget.gap),

        // ── Caste ──
        SearchableField(
          label: 'Caste',
          prefixIcon: Icons.groups_outlined,
          isRequired: widget.casteRequired,
          enabled: _hasReligion && !castesAsync.isLoading,
          items: casteItems,
          selectedItem: _inList(widget.casteName, casteItems),
          onAddNew: (v) => options.add(MasterOptionsService.caste,
              value: v, parent: widget.religionName ?? ''),
          onChanged: (name) {
            final c = _byName(castes, name, (x) => x.name);
            if (c != null) {
              widget.onCasteChanged(c.id, c.name);
            } else if ((name ?? '').trim().isNotEmpty) {
              widget.onCasteChanged(kOtherMasterId, name!.trim());
            } else {
              widget.onCasteChanged(null, null);
            }
            widget.onSubcasteChanged(null, null);
            setState(() {});
          },
        ),

        if (widget.showSubcaste) ...[
          SizedBox(height: widget.gap),
          // ── Sub Caste ──
          SearchableField(
            label: 'Sub Caste',
            prefixIcon: Icons.account_tree_outlined,
            isRequired: widget.subcasteRequired,
            enabled: _hasCaste && !subcastesAsync.isLoading,
            items: subcasteItems,
            selectedItem: _inList(widget.subCasteName, subcasteItems),
            onAddNew: (v) => options.add(MasterOptionsService.subcaste,
                value: v, parent: widget.casteName ?? ''),
            onChanged: (name) {
              final s = _byName(subcastes, name, (x) => x.name);
              if (s != null) {
                widget.onSubcasteChanged(s.id, s.name);
              } else if ((name ?? '').trim().isNotEmpty) {
                widget.onSubcasteChanged(kOtherMasterId, name!.trim());
              } else {
                widget.onSubcasteChanged(null, null);
              }
              setState(() {});
            },
          ),
        ],
      ],
    );
  }

  /// Keeps the currently-selected (possibly custom/legacy) value visible.
  static List<String> _withSelected(List<String> items, String? selected) {
    if ((selected ?? '').trim().isNotEmpty && !items.contains(selected)) {
      return [selected!, ...items];
    }
    return items;
  }

  /// dropdown_search requires the selected value to be present in [items];
  /// otherwise show nothing (e.g. while the list is still loading).
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
