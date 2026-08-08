import 'package:flutter/material.dart';
import '../../core/data/master_option.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/value_l10n.dart';

/// A searchable **multi-select** field (used wherever more than one value can
/// be chosen — Education / Profession preferences, and the multiple degrees a
/// member holds, §4).
///
/// Behaviour:
///  • Selected values appear as deletable chips ABOVE the field;
///  • tapping the field opens a modal bottom sheet with a search box —
///    type to filter, tap an item to toggle it, keep searching and adding;
///  • removing a chip (✕) deselects instantly;
///  • [maxSelection] caps how many can be on at once (the rest grey out).
///
/// Every string here is localized and every row is rendered through the
/// bilingual catalogue when one is supplied, so nothing English leaks into
/// Tamil mode (§8/§12) and search works in either language (§9).
class SearchableMultiSelectField extends StatelessWidget {
  final String label;
  final List<String> items;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final IconData? prefixIcon;
  final bool enabled;

  /// Placeholder shown inside the field while nothing is selected. Defaults to
  /// the localized "Any — tap to select".
  final String? hint;

  /// Bilingual catalogue backing [items] — drives both the displayed text and
  /// alias-aware search.
  final List<MasterOption>? options;

  /// Append the English name in brackets in Tamil mode (degrees, occupations).
  final bool showEnglishInBrackets;

  /// Maximum number of simultaneously selected values; null means unlimited.
  final int? maxSelection;

  const SearchableMultiSelectField({
    super.key,
    required this.label,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.prefixIcon,
    this.enabled = true,
    this.hint,
    this.options,
    this.showEnglishInBrackets = false,
    this.maxSelection,
  });

  /// Builds the field straight from a bilingual catalogue.
  SearchableMultiSelectField.fromOptions({
    super.key,
    required this.label,
    required List<MasterOption> options,
    required this.selected,
    required this.onChanged,
    this.prefixIcon,
    this.enabled = true,
    this.hint,
    this.showEnglishInBrackets = false,
    this.maxSelection,
  })  : options = options,
        items = options.values;

  void _remove(String value) =>
      onChanged(selected.where((v) => v != value).toList());

  /// Display text for a stored value.
  String _display(BuildContext context, String value) {
    final option = options?.byValue(value);
    if (option != null) {
      return option.display(
          tamil: context.isTamil, withEnglish: showEnglishInBrackets);
    }
    return context.localizeValue(value);
  }

  Future<void> _openSheet(BuildContext context) async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _MultiSelectSheet(
        label: label,
        items: items,
        initiallySelected: selected,
        options: options,
        showEnglishInBrackets: showEnglishInBrackets,
        maxSelection: maxSelection,
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Selected chips (deletable) ─────────────────────────────────────
        if (selected.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: selected
                .map((v) => Chip(
                      label: Text(_display(context, v),
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                      backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                      side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                      deleteIcon: const Icon(Icons.close,
                          size: 16, color: AppColors.primary),
                      onDeleted: enabled ? () => _remove(v) : null,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
        ],
        // ── Tap-to-search field ────────────────────────────────────────────
        InkWell(
          onTap: enabled ? () => _openSheet(context) : null,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
              suffixIcon: const Icon(Icons.arrow_drop_down),
              filled: true,
              fillColor: enabled ? Colors.grey[50] : Colors.grey[200],
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Text(
              selected.isEmpty
                  ? (hint ?? l10n.anyTapToSelect)
                  : l10n.countSelected(selected.length),
              style: TextStyle(
                fontSize: 14,
                color: selected.isEmpty ? Colors.grey[600] : Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The search + toggle sheet. Selection state lives here while open; the final
/// list is returned on close (either the ✓ Done button or dismissing the
/// sheet backdrop returns via [Navigator.pop] with the current selection).
class _MultiSelectSheet extends StatefulWidget {
  final String label;
  final List<String> items;
  final List<String> initiallySelected;
  final List<MasterOption>? options;
  final bool showEnglishInBrackets;
  final int? maxSelection;

  const _MultiSelectSheet({
    required this.label,
    required this.items,
    required this.initiallySelected,
    required this.options,
    required this.showEnglishInBrackets,
    required this.maxSelection,
  });

  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late final Set<String> _selected = {...widget.initiallySelected};
  String _query = '';

  bool get _atCap =>
      widget.maxSelection != null && _selected.length >= widget.maxSelection!;

  String _display(String value) {
    final option = widget.options?.byValue(value);
    if (option != null) {
      return option.display(
          tamil: context.isTamil, withEnglish: widget.showEnglishInBrackets);
    }
    return context.localizeValue(value);
  }

  /// Bilingual + alias matching (§9), falling back to plain text for a field
  /// that has no catalogue behind it.
  List<String> get _filtered {
    final q = _query.trim();
    if (q.isEmpty) return widget.items;
    return widget.items.where((i) {
      final option = widget.options?.byValue(i);
      if (option != null) return option.matches(q);
      return i.toLowerCase().contains(q.toLowerCase()) ||
          _display(i).toLowerCase().contains(q.toLowerCase());
    }).toList();
  }

  void _done() => Navigator.of(context).pop(_selected.toList());

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final maxH = MediaQuery.of(context).size.height * 0.75;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // Backdrop tap / back gesture also returns the current selection so a
        // toggle is never silently lost.
        if (!didPop) _done();
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.selectFieldTitle(widget.label),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _done,
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(l10n.doneCount(_selected.length)),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary),
                    ),
                  ],
                ),
              ),
              if (widget.maxSelection != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.selectUpTo(widget.maxSelection!),
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: l10n.searchFieldHint(widget.label),
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Flexible(
                child: _filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text(l10n.noOptionsFound)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final item = _filtered[i];
                          final on = _selected.contains(item);
                          // At the cap, unticked rows go inert rather than
                          // disappearing, so the limit is visible not magic.
                          final locked = !on && _atCap;
                          return CheckboxListTile(
                            dense: true,
                            value: on,
                            enabled: !locked,
                            activeColor: AppColors.primary,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(_display(item),
                                style: TextStyle(
                                    fontSize: 14,
                                    color: locked ? Colors.grey : null)),
                            onChanged: locked
                                ? null
                                : (_) => setState(() {
                                      on
                                          ? _selected.remove(item)
                                          : _selected.add(item);
                                    }),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
