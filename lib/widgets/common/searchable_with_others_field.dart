import 'package:flutter/material.dart';
import '../../core/data/master_option.dart';
import 'searchable_field.dart';
import 'searchable_with_add_field.dart';

export 'searchable_field.dart' show SearchablePopupMode;

/// A searchable dropdown that also accepts a value the list has never heard of.
///
/// The name is historical. It used to mean *"a dropdown with an **Others**
/// entry"*: picking "மற்றவை" revealed a second textbox underneath, and only
/// then could a member type the caste or degree that was missing. That is three
/// controls and a hidden mode for one question, and it was the single most
/// common place people got stuck — so the "Others" entry is gone everywhere.
///
/// What happens now is [SearchableWithAddField], the field the app already uses
/// for Profession Type and City: the search box IS the custom input. Type, and
/// either tap a matching option or tap **+ Add "…"** — one tap, immediately
/// selected, no confirmation step. This widget stays as the thin adapter so
/// every caller keeps its existing API and its stored values (a custom value
/// is, as before, just the typed string, kept only on this record and never
/// written back to the shared master data).
class SearchableWithOthersField extends StatelessWidget {
  final String label;
  final List<String> items;

  /// The stored value — a list item, or a custom string the member typed.
  final String? value;
  final ValueChanged<String?> onChanged;

  final bool isRequired;
  final bool enabled;
  final IconData? prefixIcon;

  /// Kept for source compatibility. The picker is now always the bottom sheet:
  /// an anchored menu has nowhere to put the "+ Add" row on a phone, and two
  /// presentations of the same control is one more thing to learn.
  final SearchablePopupMode popupMode;

  /// Historical: labelled the revealed "custom" textbox, which no longer
  /// exists. Ignored.
  final String? customLabel;

  /// Inline error rendered under the field (§10).
  final String? errorText;

  /// Bilingual catalogue backing [items] (§7/§9).
  final List<MasterOption>? options;

  /// Append the English name in brackets in Tamil mode (degrees, occupations).
  final bool showEnglishInBrackets;

  const SearchableWithOthersField({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    this.isRequired = false,
    this.enabled = true,
    this.prefixIcon,
    this.popupMode = SearchablePopupMode.menu,
    this.customLabel,
    this.errorText,
    this.options,
    this.showEnglishInBrackets = false,
  });

  /// Builds the field straight from a bilingual catalogue.
  SearchableWithOthersField.fromOptions({
    super.key,
    required this.label,
    required List<MasterOption> options,
    required this.value,
    required this.onChanged,
    this.isRequired = false,
    this.enabled = true,
    this.prefixIcon,
    this.popupMode = SearchablePopupMode.menu,
    this.customLabel,
    this.errorText,
    this.showEnglishInBrackets = false,
  })  : options = options,
        items = options.values;

  /// A literal "Other" / "Others" row inside a master list is dropped: it is a
  /// dead end now that anything can be typed, and two ways to say "not listed"
  /// is worse than none.
  static bool _isOtherLiteral(String v) {
    final s = v.trim().toLowerCase();
    return s == 'other' || s == 'others';
  }

  @override
  Widget build(BuildContext context) => SearchableWithAddField(
        label: label,
        items: [
          for (final i in items)
            if (i.trim().isNotEmpty && !_isOtherLiteral(i)) i,
        ],
        options: options,
        value: value,
        onChanged: onChanged,
        isRequired: isRequired,
        enabled: enabled,
        prefixIcon: prefixIcon,
        errorText: errorText,
        showEnglishInBrackets: showEnglishInBrackets,
        allowClear: !isRequired,
      );
}
