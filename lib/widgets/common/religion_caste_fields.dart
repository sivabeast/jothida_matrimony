import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/master_data.dart';
import '../../providers/master_data_provider.dart';
import 'searchable_field.dart';

/// Sentinel id stored for a user-entered ("Other") religion/caste/subcaste, so
/// the value round-trips: a non-empty name with this id means "custom".
const String kOtherMasterId = 'other';
const String _otherLabel = 'Other';

/// Dependent, searchable Religion → Caste → Sub-caste fields backed by the
/// master data (bundled JSON, with Firestore fallback — see [MasterDataService]).
///
/// Controlled widget: the parent owns the six values (id + name for each level)
/// and passes three callbacks. The widget loads the correct scoped lists,
/// enforces the dependency rules (changing Religion clears Caste & Sub-caste;
/// changing Caste clears Sub-caste) and reports the selected **id + name**.
///
/// Each level also offers an **"Other"** option at the bottom; selecting it
/// reveals a text field for a custom value, which is reported with id
/// [kOtherMasterId] and saved/displayed like any other value.
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
  late final TextEditingController _religionOtherCtl;
  late final TextEditingController _casteOtherCtl;
  late final TextEditingController _subcasteOtherCtl;

  bool get _religionOther => widget.religionId == kOtherMasterId;
  bool get _casteOther => widget.casteId == kOtherMasterId;
  bool get _subcasteOther => widget.subCasteId == kOtherMasterId;

  bool get _hasReligion => (widget.religionId ?? '').isNotEmpty;
  bool get _hasCaste => (widget.casteId ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _religionOtherCtl = TextEditingController(
        text: _religionOther ? (widget.religionName ?? '') : '');
    _casteOtherCtl = TextEditingController(
        text: _casteOther ? (widget.casteName ?? '') : '');
    _subcasteOtherCtl = TextEditingController(
        text: _subcasteOther ? (widget.subCasteName ?? '') : '');
  }

  @override
  void dispose() {
    _religionOtherCtl.dispose();
    _casteOtherCtl.dispose();
    _subcasteOtherCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final religionsAsync = ref.watch(religionsProvider);
    // Don't query children for a custom ("Other") parent — there are none.
    final castesAsync = (_hasReligion && !_religionOther)
        ? ref.watch(castesProvider(widget.religionId!))
        : const AsyncValue<List<Caste>>.data(<Caste>[]);
    final subcastesAsync = (_hasCaste && !_casteOther)
        ? ref.watch(subcastesProvider(widget.casteId!))
        : const AsyncValue<List<Subcaste>>.data(<Subcaste>[]);

    final religions = religionsAsync.valueOrNull ?? const <Religion>[];
    final castes = castesAsync.valueOrNull ?? const <Caste>[];
    final subcastes = subcastesAsync.valueOrNull ?? const <Subcaste>[];

    // Master names + an "Other" option at the bottom of each dropdown.
    final religionItems = [...religions.map((r) => r.name), _otherLabel];
    final casteItems = [...castes.map((c) => c.name), _otherLabel];
    final subcasteItems = [...subcastes.map((s) => s.name), _otherLabel];

    return Column(
      children: [
        // ── Religion ──
        SearchableField(
          label: 'Religion',
          prefixIcon: Icons.spa_outlined,
          isRequired: widget.religionRequired,
          enabled: !religionsAsync.isLoading,
          items: religionItems,
          selectedItem: _religionOther
              ? _otherLabel
              : _inList(widget.religionName, religionItems),
          onChanged: (name) {
            if (name == _otherLabel) {
              widget.onReligionChanged(kOtherMasterId, _religionOtherCtl.text.trim());
            } else {
              final r = _byName(religions, name, (x) => x.name);
              widget.onReligionChanged(r?.id, r?.name);
            }
            // Religion changed → clear caste & sub-caste (incl. custom text).
            _casteOtherCtl.clear();
            _subcasteOtherCtl.clear();
            widget.onCasteChanged(null, null);
            widget.onSubcasteChanged(null, null);
            setState(() {});
          },
        ),
        if (_religionOther)
          _otherField(
            label: 'Enter Religion',
            controller: _religionOtherCtl,
            required: widget.religionRequired,
            onChanged: (v) => widget.onReligionChanged(kOtherMasterId, v.trim()),
          ),
        SizedBox(height: widget.gap),

        // ── Caste ──
        SearchableField(
          label: 'Caste',
          prefixIcon: Icons.groups_outlined,
          isRequired: widget.casteRequired,
          enabled: _hasReligion && !castesAsync.isLoading,
          items: casteItems,
          selectedItem:
              _casteOther ? _otherLabel : _inList(widget.casteName, casteItems),
          onChanged: (name) {
            if (name == _otherLabel) {
              widget.onCasteChanged(kOtherMasterId, _casteOtherCtl.text.trim());
            } else {
              final c = _byName(castes, name, (x) => x.name);
              widget.onCasteChanged(c?.id, c?.name);
            }
            _subcasteOtherCtl.clear();
            widget.onSubcasteChanged(null, null);
            setState(() {});
          },
        ),
        if (_casteOther)
          _otherField(
            label: 'Enter Caste',
            controller: _casteOtherCtl,
            required: widget.casteRequired,
            onChanged: (v) => widget.onCasteChanged(kOtherMasterId, v.trim()),
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
            selectedItem: _subcasteOther
                ? _otherLabel
                : _inList(widget.subCasteName, subcasteItems),
            onChanged: (name) {
              if (name == _otherLabel) {
                widget.onSubcasteChanged(
                    kOtherMasterId, _subcasteOtherCtl.text.trim());
              } else {
                final s = _byName(subcastes, name, (x) => x.name);
                widget.onSubcasteChanged(s?.id, s?.name);
              }
              setState(() {});
            },
          ),
          if (_subcasteOther)
            _otherField(
              label: 'Enter Sub Caste',
              controller: _subcasteOtherCtl,
              required: widget.subcasteRequired,
              onChanged: (v) =>
                  widget.onSubcasteChanged(kOtherMasterId, v.trim()),
            ),
        ],
      ],
    );
  }

  /// The text input revealed under a dropdown when "Other" is chosen.
  Widget _otherField({
    required String label,
    required TextEditingController controller,
    required bool required,
    required ValueChanged<String> onChanged,
  }) =>
      Padding(
        padding: EdgeInsets.only(top: widget.gap * 0.6),
        child: TextFormField(
          controller: controller,
          onChanged: onChanged,
          textCapitalization: TextCapitalization.words,
          validator: required
              ? (v) =>
                  (v == null || v.trim().isEmpty) ? '$label is required' : null
              : null,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.edit_outlined),
            filled: true,
            fillColor: Colors.grey[50],
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      );

  /// dropdown_search requires the selected value to be present in [items];
  /// otherwise show nothing (e.g. while the list is still loading, or a legacy
  /// free-text value not in the master list).
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
