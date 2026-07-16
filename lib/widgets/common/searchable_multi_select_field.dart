import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A searchable **multi-select** field (replaces plain dropdowns wherever more
/// than one value can be chosen — e.g. Education / Profession preferences).
///
/// Behaviour (per spec):
///  • Selected values appear as deletable chips ABOVE the field;
///  • tapping the field opens a modal bottom sheet with a search box —
///    type to filter, tap an item to toggle it, keep searching and adding;
///  • removing a chip (✕) deselects instantly;
///  • Material look consistent with [SearchableField].
class SearchableMultiSelectField extends StatelessWidget {
  final String label;
  final List<String> items;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final IconData? prefixIcon;
  final bool enabled;

  /// Placeholder shown inside the field while nothing is selected.
  final String? hint;

  const SearchableMultiSelectField({
    super.key,
    required this.label,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.prefixIcon,
    this.enabled = true,
    this.hint,
  });

  void _remove(String value) =>
      onChanged(selected.where((v) => v != value).toList());

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
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
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
                      label: Text(v,
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
                  ? (hint ?? 'Any — tap to select')
                  : '${selected.length} selected',
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

  const _MultiSelectSheet({
    required this.label,
    required this.items,
    required this.initiallySelected,
  });

  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late final Set<String> _selected = {...widget.initiallySelected};
  String _query = '';

  List<String> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return widget.items.where((i) => i.toLowerCase().contains(q)).toList();
  }

  void _done() => Navigator.of(context).pop(_selected.toList());

  @override
  Widget build(BuildContext context) {
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
                        'Select ${widget.label}',
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
                      label: Text('Done (${_selected.length})'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search ${widget.label}…',
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
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No options found')),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final item = _filtered[i];
                          final on = _selected.contains(item);
                          return CheckboxListTile(
                            dense: true,
                            value: on,
                            activeColor: AppColors.primary,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(item,
                                style: const TextStyle(fontSize: 14)),
                            onChanged: (_) => setState(() {
                              on ? _selected.remove(item) : _selected.add(item);
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
