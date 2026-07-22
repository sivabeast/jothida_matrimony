import 'package:flutter/material.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/value_l10n.dart';
import 'app_text_field.dart';
import 'searchable_field.dart';

export 'searchable_field.dart' show SearchablePopupMode;

/// Sentinel value for the single "Others" entry appended to every dropdown.
/// It is never stored — picking it only reveals the custom textbox.
const String kOthersSentinel = '__others__';

/// A [SearchableField] with exactly ONE **"Others"** entry pinned to the top
/// of the list. Picking it reveals a plain text input directly below the
/// dropdown; whatever the member types becomes the stored value.
///
/// This replaced the old "+" Add button: a typed value is kept ONLY on this
/// profile and is never written back to the shared master data. A saved value
/// that isn't one of [items] is automatically treated as an "Others" value, so
/// drafts and edit-mode restore straight into the custom textbox.
///
/// [onChanged] emits `''` while "Others" is selected but nothing has been typed
/// yet, so a `isRequired` step validation still catches it (spec §4).
class SearchableWithOthersField extends StatefulWidget {
  final String label;
  final List<String> items;

  /// The stored value — a list item, or a custom string typed under "Others".
  final String? value;
  final ValueChanged<String?> onChanged;

  final bool isRequired;
  final bool enabled;
  final IconData? prefixIcon;
  final SearchablePopupMode popupMode;

  /// Label of the revealed textbox. Defaults to "Custom <label>".
  final String? customLabel;

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
  });

  @override
  State<SearchableWithOthersField> createState() =>
      _SearchableWithOthersFieldState();
}

class _SearchableWithOthersFieldState extends State<SearchableWithOthersField> {
  late final TextEditingController _custom =
      TextEditingController(text: _isKnown(widget.value) ? '' : (widget.value ?? ''));

  /// Explicit "Others" pick — kept even before anything has been typed.
  bool _othersPicked = false;

  /// A literal "Other" / "Others" entry inside a master list is dropped: the
  /// pinned sentinel is the ONE way to enter a custom value, so members never
  /// see two near-identical options.
  static bool _isOtherLiteral(String v) {
    final s = v.trim().toLowerCase();
    return s == 'other' || s == 'others';
  }

  List<String> get _cleanItems =>
      widget.items.where((i) => !_isOtherLiteral(i)).toList();

  bool _isKnown(String? v) {
    final value = (v ?? '').trim().toLowerCase();
    if (value.isEmpty) return false;
    return _cleanItems.any((i) => i.trim().toLowerCase() == value);
  }

  bool get _othersMode =>
      _othersPicked || ((widget.value ?? '').isNotEmpty && !_isKnown(widget.value));

  @override
  void didUpdateWidget(covariant SearchableWithOthersField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A parent-driven reset (e.g. Religion changed → Caste cleared) must drop
    // the custom text as well, otherwise a stale value would linger.
    if (widget.value != oldWidget.value &&
        (widget.value ?? '').isEmpty &&
        !_othersPicked) {
      _custom.clear();
    }
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final othersMode = _othersMode;
    // "Others" is pinned FIRST so it stays reachable in long, scrollable lists.
    final items = <String>[kOthersSentinel, ..._cleanItems];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SearchableField(
          label: widget.label,
          isRequired: widget.isRequired,
          enabled: widget.enabled,
          prefixIcon: widget.prefixIcon,
          popupMode: widget.popupMode,
          items: items,
          itemLabel: (item) => item == kOthersSentinel
              ? l10n.othersOption
              : context.localizeValue(item),
          selectedItem: othersMode
              ? kOthersSentinel
              : (_isKnown(widget.value) ? widget.value : null),
          onChanged: (v) {
            if (v == kOthersSentinel) {
              // Re-tapping "Others" while already in custom mode must not wipe
              // what has been typed so far.
              if (othersMode) return;
              setState(() {
                _othersPicked = true;
                _custom.clear();
              });
              // Cleared until specified, so a required check still fires.
              widget.onChanged('');
              return;
            }
            setState(() {
              _othersPicked = false;
              _custom.clear();
            });
            widget.onChanged(v);
          },
        ),
        if (othersMode) ...[
          const SizedBox(height: 12),
          AppTextField(
            controller: _custom,
            label: widget.isRequired
                ? '${widget.customLabel ?? l10n.customField(widget.label)} *'
                : (widget.customLabel ?? l10n.customField(widget.label)),
            hint: l10n.typeHere,
            enabled: widget.enabled,
            textCapitalization: TextCapitalization.words,
            onChanged: (v) => widget.onChanged(v.trim()),
            validator: widget.isRequired
                ? (v) => (v == null || v.trim().isEmpty)
                    ? l10n.pleaseEnterField(widget.label)
                    : null
                : null,
          ),
        ],
      ],
    );
  }
}
