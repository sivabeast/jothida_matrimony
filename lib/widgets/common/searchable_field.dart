import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

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

  const SearchableField({
    super.key,
    required this.label,
    required this.items,
    required this.selectedItem,
    required this.onChanged,
    this.isRequired = false,
    this.enabled = true,
    this.prefixIcon,
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
      popupProps: PopupProps.menu(
        showSearchBox: true,
        fit: FlexFit.loose,
        constraints: const BoxConstraints(maxHeight: 360),
        searchFieldProps: TextFieldProps(
          decoration: InputDecoration(
            hintText: 'Search $label…',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        menuProps: const MenuProps(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        emptyBuilder: (_, __) => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: Text('No options found')),
        ),
      ),
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
}
