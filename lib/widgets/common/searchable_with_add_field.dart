import 'package:flutter/material.dart';

import '../../core/data/master_option.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/value_l10n.dart';

/// A searchable single-select field that also lets the member **add a value the
/// list does not have** — search, then `+ Add "…"`.
///
/// This is the replacement for an "Others" entry (spec §6): rather than forcing
/// someone whose profession is "Coconut Farmer" to pick a catch-all, they type
/// it and tap `+`, the value is added, selected immediately, and stored on
/// their profile like any other. Used for the Profession Type field (§6) and
/// the City field (§11).
///
/// A custom value lives ONLY on the profile that created it — nothing is
/// written back to the shared master catalogues, so one member's entry never
/// shows up in another member's suggestions.
///
/// Search is cross-language for free: the query is matched against the stored
/// value, its Tamil rendering and its English rendering, plus any catalogue
/// aliases (spec §9).
class SearchableWithAddField extends StatelessWidget {
  final String label;
  final List<String> items;

  /// The stored value — a list item, or a value added through `+`.
  final String? value;
  final ValueChanged<String?> onChanged;

  final bool isRequired;
  final bool enabled;
  final IconData? prefixIcon;

  /// Inline error rendered under the field (§10).
  final String? errorText;

  /// Bilingual catalogue backing [items], for alias search + Tamil display.
  final List<MasterOption>? options;

  /// Helper line under the field. Defaults to the "can't find it?" hint.
  final String? helperText;

  /// Append the English name in brackets in Tamil mode — "இளங்கலை அறிவியல்
  /// (B.Sc)". On for degrees and occupations, where the English term is what
  /// people actually say out loud; off for ordinary vocabulary.
  final bool showEnglishInBrackets;

  /// Offer a × that empties the field. On for anything optional — a Nakshatra
  /// picked by mistake has to be removable, and on a required field the only
  /// way out is another value anyway.
  final bool allowClear;

  const SearchableWithAddField({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    this.isRequired = false,
    this.enabled = true,
    this.prefixIcon,
    this.errorText,
    this.options,
    this.helperText,
    this.showEnglishInBrackets = false,
    this.allowClear = false,
  });

  /// What the member reads for [item]: the catalogue's bilingual name when
  /// there is one, otherwise the standard value → Tamil mapping. A value added
  /// through `+` has no catalogue record and simply shows as typed.
  static String displayOf(
    BuildContext context,
    String item, {
    List<MasterOption>? options,
    bool withEnglish = false,
  }) {
    final option = options?.byValue(item);
    if (option != null) {
      return option.display(tamil: context.isTamil, withEnglish: withEnglish);
    }
    return context.localizeValue(item);
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddableSearchSheet(
        title: label,
        items: items,
        options: options,
        selected: value,
        showEnglishInBrackets: showEnglishInBrackets,
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final shown = (value ?? '').trim();
    return InkWell(
      onTap: enabled ? () => _open(context) : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: isRequired ? '$label *' : label,
          filled: true,
          fillColor: enabled ? Colors.grey[50] : Colors.grey[200],
          isDense: true,
          errorText: (errorText ?? '').isEmpty ? null : errorText,
          helperText: helperText ?? context.l10n.addYourOwnHint,
          helperMaxLines: 2,
          prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (shown.isNotEmpty && allowClear && enabled)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  splashRadius: 18,
                  tooltip: context.l10n.clear,
                  onPressed: () => onChanged(null),
                ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.search, size: 20),
              ),
            ],
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          shown.isEmpty
              ? context.l10n.searchOrTypeHint
              : displayOf(context, shown,
                  options: options, withEnglish: showEnglishInBrackets),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: shown.isEmpty ? FontWeight.w400 : FontWeight.w600,
            color: shown.isEmpty ? Colors.grey[600] : null,
          ),
        ),
      ),
    );
  }
}

/// Search sheet: filtered options, plus a `+ Add "<query>"` row whenever what
/// was typed is not already an option.
class _AddableSearchSheet extends StatefulWidget {
  final String title;
  final List<String> items;
  final List<MasterOption>? options;
  final String? selected;
  final bool showEnglishInBrackets;

  const _AddableSearchSheet({
    required this.title,
    required this.items,
    required this.options,
    required this.selected,
    required this.showEnglishInBrackets,
  });

  @override
  State<_AddableSearchSheet> createState() => _AddableSearchSheetState();
}

class _AddableSearchSheetState extends State<_AddableSearchSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String get _q => _query.text.trim();

  /// Cross-language match: stored value, Tamil form, English form, catalogue
  /// aliases, and the text currently displayed (§9).
  bool _matches(BuildContext context, String item, String q) {
    final option = widget.options?.byValue(item);
    if (option != null && option.matches(q)) return true;
    if (_display(context, item).toLowerCase().contains(q)) return true;
    return searchableFormsOf(item).any((f) => f.contains(q));
  }

  String _display(BuildContext context, String item) =>
      SearchableWithAddField.displayOf(context, item,
          options: widget.options,
          withEnglish: widget.showEnglishInBrackets);

  List<String> _results(BuildContext context) {
    final q = _q.toLowerCase();
    if (q.isEmpty) return widget.items;
    return widget.items.where((i) => _matches(context, i, q)).toList();
  }

  /// True when what was typed is not already an option — the only case where
  /// adding makes sense. Compared case-insensitively across both languages so
  /// "coconut farmer" never duplicates "Coconut Farmer".
  bool _canAdd(BuildContext context) {
    if (_q.length < 2) return false;
    final q = _q.toLowerCase();
    return !widget.items.any((i) =>
        i.toLowerCase() == q ||
        _display(context, i).toLowerCase() == q ||
        searchableFormsOf(i).contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final results = _results(context);
    final canAdd = _canAdd(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        // A Material, not a decorated box: the rows are ListTiles and paint
        // their ink on the nearest Material ancestor.
        builder: (_, scrollController) => Material(
          color: Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(widget.title,
                          style: const TextStyle(
                              fontSize: 16,
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      tooltip: l10n.close,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: l10n.searchOrTypeHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.scaffoldBg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              Expanded(
                child: (results.isEmpty && !canAdd)
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(l10n.noOptionsFound,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[600])),
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          // `+ Add "<what they typed>"` sits at the TOP so it
                          // is obvious when nothing in the list fits.
                          if (canAdd)
                            ListTile(
                              onTap: () => Navigator.pop(context, _q),
                              leading: const Icon(Icons.add_circle,
                                  color: AppColors.primary),
                              title: Text(l10n.addValueLabel(_q),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary)),
                            ),
                          if (canAdd && results.isNotEmpty)
                            const Divider(height: 1),
                          for (final item in results)
                            ListTile(
                              onTap: () => Navigator.pop(context, item),
                              dense: true,
                              title: Text(_display(context, item),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14.5, height: 1.3)),
                              trailing: item == widget.selected
                                  ? const Icon(Icons.check_circle,
                                      color: AppColors.success, size: 20)
                                  : null,
                            ),
                        ],
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
