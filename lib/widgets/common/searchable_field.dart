import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/value_l10n.dart';

/// How the searchable popup is presented.
///
/// * [menu] — anchored dropdown drawn over the page (default; compact).
/// * [modalBottomSheet] — a modal sheet that slides up from the bottom and
///   dims the page behind it. Use this when the field sits among other content
///   that the anchored menu would otherwise overlap (e.g. the Horoscope
///   Details screen, where the list must NOT cover the result cards).
enum SearchablePopupMode { menu, modalBottomSheet }

/// A searchable single-select dropdown with a built-in search box.
///
/// Used everywhere structured data is selected (State, City, Religion,
/// Caste, Sub-caste, Education, Occupation, Rasi, Nakshatra…) instead of free
/// text. Supports dependent dropdowns: when the parent value changes, pass a
/// new [items] list (and reset [selectedItem]).
///
/// There is NO "+" Add button any more: a value missing from the list is
/// entered through the "Others" option — see [SearchableWithOthersField],
/// which wraps this field and reveals a custom textbox below it.
class SearchableField extends StatelessWidget {
  final String label;
  final List<String> items;
  final String? selectedItem;
  final ValueChanged<String?> onChanged;
  final bool isRequired;
  final bool enabled;
  final IconData? prefixIcon;

  /// Presentation mode for the options popup. Defaults to the anchored [menu].
  /// Pass [SearchablePopupMode.modalBottomSheet] to avoid overlapping
  /// surrounding widgets.
  final SearchablePopupMode popupMode;

  /// Optional display-text override for an item, applied BEFORE the standard
  /// value localization. Used by [SearchableWithOthersField] to render its
  /// "Others" sentinel with the localized label.
  final String Function(String item)? itemLabel;

  const SearchableField({
    super.key,
    required this.label,
    required this.items,
    required this.selectedItem,
    required this.onChanged,
    this.isRequired = false,
    this.enabled = true,
    this.prefixIcon,
    this.popupMode = SearchablePopupMode.menu,
    this.itemLabel,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownSearch<String>(
      items: items,
      selectedItem: selectedItem,
      enabled: enabled,
      onChanged: onChanged,
      // Storage stays English; only the DISPLAYED text is localized (Tamil
      // mode). Unmapped values (cities, castes not in the map) pass through
      // unchanged, so this is safe for every field.
      itemAsString: (item) => _display(context, item),
      // Keep search working in Tamil mode: match the user's query against BOTH
      // the stored English value and its localized display text.
      filterFn: (item, query) {
        final q = query.trim().toLowerCase();
        if (q.isEmpty) return true;
        return item.toLowerCase().contains(q) ||
            _display(context, item).toLowerCase().contains(q);
      },
      validator: isRequired
          ? (v) => (v == null || v.isEmpty)
              ? context.l10n.fieldRequired(label)
              : null
          : null,
      popupProps: _buildPopupProps(context),
      dropdownDecoratorProps: DropDownDecoratorProps(
        dropdownSearchDecoration: InputDecoration(
          labelText: isRequired ? '$label *' : label,
          prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
          filled: true,
          fillColor: enabled ? Colors.grey[50] : Colors.grey[200],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
  }

  /// Display text for [item]: the [itemLabel] override first, then the standard
  /// English-value → Tamil display mapping.
  String _display(BuildContext context, String item) =>
      itemLabel != null ? itemLabel!(item) : context.localizeValue(item);

  PopupProps<String> _buildPopupProps(BuildContext context) {
    final searchField = TextFieldProps(
      autofocus: true,
      decoration: InputDecoration(
        hintText: context.l10n.searchFieldHint(label),
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    Widget empty(_, __) => Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(context.l10n.noOptionsFound)),
        );

    switch (popupMode) {
      case SearchablePopupMode.modalBottomSheet:
        final maxH = MediaQuery.of(context).size.height * 0.75;
        return PopupProps.modalBottomSheet(
          showSearchBox: true,
          searchDelay: Duration.zero,
          title: _SheetTitle(label: label),
          constraints: BoxConstraints(maxHeight: maxH),
          searchFieldProps: searchField,
          modalBottomSheetProps: const ModalBottomSheetProps(
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            backgroundColor: Colors.white,
          ),
          emptyBuilder: empty,
        );
      case SearchablePopupMode.menu:
        return PopupProps.menu(
          showSearchBox: true,
          fit: FlexFit.loose,
          constraints: const BoxConstraints(maxHeight: 360),
          searchDelay: Duration.zero,
          searchFieldProps: searchField,
          menuProps: const MenuProps(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          emptyBuilder: empty,
        );
    }
  }
}

/// Header shown at the top of the modal-bottom-sheet popup.
class _SheetTitle extends StatelessWidget {
  final String label;
  const _SheetTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.selectFieldTitle(label),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
