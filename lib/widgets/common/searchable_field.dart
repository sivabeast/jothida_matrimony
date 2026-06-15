import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

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
/// Used everywhere structured data is selected (Country, State, City, Religion,
/// Caste, Sub-caste, Education, Occupation, Rasi, Nakshatra…) instead of free
/// text. Supports dependent dropdowns: when the parent value changes, pass a
/// new [items] list (and reset [selectedItem]).
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
  });

  @override
  Widget build(BuildContext context) {
    return DropdownSearch<String>(
      items: items,
      selectedItem: selectedItem,
      enabled: enabled,
      onChanged: onChanged,
      validator: isRequired
          ? (v) => (v == null || v.isEmpty) ? '$label is required' : null
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

  PopupProps<String> _buildPopupProps(BuildContext context) {
    final searchField = TextFieldProps(
      autofocus: true,
      decoration: InputDecoration(
        hintText: 'Search $label…',
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    Widget empty(_, __) => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No options found')),
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
              'Select $label',
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
