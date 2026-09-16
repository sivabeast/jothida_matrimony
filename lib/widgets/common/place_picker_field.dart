import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/location_search.dart';
import '../../models/location_model.dart';
import '../../providers/locale_provider.dart';
import '../../providers/location_provider.dart';

/// The app's ONE place picker — used everywhere a location is asked for
/// (profile location, native place, birth place, the second person's birth
/// place, partner-preference location) so the search is identical throughout
/// (spec §31). All of them search the same [PlaceSearchIndex], built once from
/// the bundled location JSON.
///
/// A city/village name on its own is ambiguous: the same name occurs in
/// several districts. So the search results always read
///
/// ```
/// Virudhunagar
/// Virudhunagar District, Tamil Nadu
/// ```
///
/// and the flow is a plain search-and-select: **tap → search → tap a result →
/// the field is populated** with "City, District, State" and the sheet closes.
///
/// Nothing here is written to the shared master data. A place typed by hand
/// (`allowCustom`) lives only in the form that created it, so one member's
/// second-person entry can never appear in another member's suggestions
/// (spec §30).
class PlacePickerField extends ConsumerWidget {
  /// Field label, e.g. "Place of Birth".
  final String label;

  /// The currently stored value — the full "City, District, State" display
  /// text (or a legacy bare city name from an older profile).
  final String? value;

  final bool isRequired;
  final IconData prefixIcon;

  /// Validation message rendered under the field (null when valid).
  final String? errorText;

  /// Allows a free-typed place that is not in the master data.
  final bool allowCustom;

  /// When true a free-typed place is only accepted if it names a state
  /// (e.g. "Kochi, Kerala") — for the member's own location, where a place
  /// inside Tamil Nadu must be a recognised town (or the nearest one), never
  /// arbitrary text (spec §28).
  final bool customNeedsState;

  /// Fired with the chosen place.
  final ValueChanged<PlaceSelection> onChanged;

  const PlacePickerField({
    super.key,
    required this.label,
    required this.onChanged,
    this.value,
    this.isRequired = false,
    this.prefixIcon = Icons.location_on_outlined,
    this.errorText,
    this.allowCustom = true,
    this.customNeedsState = false,
  });

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final PlaceSearchIndex index;
    try {
      index = await ref.read(placeSearchIndexProvider.future);
    } catch (e) {
      debugPrint('[PlacePicker] location data unavailable: $e');
      // Never a silent no-op or an unexplained empty list (spec §39): say what
      // happened and offer the retry, which re-reads the data.
      ref.invalidate(placeSearchIndexProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(l10n.locationsLoadFailed),
          action: SnackBarAction(
              label: l10n.retry, onPressed: () => _open(context, ref)),
        ));
      return;
    }
    if (!context.mounted) return;
    final lang = ref.read(localeProvider)?.languageCode ?? 'en';
    final picked = await showModalBottomSheet<PlaceSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlaceSearchSheet(
        title: label,
        index: index,
        lang: lang,
        allowCustom: allowCustom,
        customNeedsState: customNeedsState,
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = (value ?? '').trim();
    // The location data is bundled with the app and read once per session, so
    // there is no loading state worth drawing: a tap simply waits for it (and
    // a failed load is reported with a retry — see [_open]).
    return InkWell(
      onTap: () => _open(context, ref),
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: isRequired ? '$label *' : label,
          // White, like every other input in the app — the old scaffold tint
          // made this read as a disabled box rather than a field.
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          errorText: errorText,
          prefixIcon: Icon(prefixIcon, size: 18),
          suffixIcon: const Icon(Icons.search, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        child: Text(
          text.isEmpty ? context.l10n.searchCityVillage : text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: text.isEmpty ? FontWeight.w400 : FontWeight.w600,
            color: text.isEmpty ? Colors.grey[600] : null,
          ),
        ),
      ),
    );
  }
}

/// The search sheet: type → matching places (City/Village + District + State)
/// → tap one → it is returned to the field and the sheet closes.
class _PlaceSearchSheet extends StatefulWidget {
  final String title;
  final PlaceSearchIndex index;
  final String lang;
  final bool allowCustom;
  final bool customNeedsState;

  const _PlaceSearchSheet({
    required this.title,
    required this.index,
    required this.lang,
    required this.allowCustom,
    required this.customNeedsState,
  });

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  final _query = TextEditingController();

  /// The query [_result] was computed for. The search is an in-memory pass
  /// over ~1,100 pre-normalised rows (well under a millisecond), so it runs
  /// once per distinct query — no debounce delay is needed, and none is added
  /// between the member's typing and the results.
  String? _searched;
  PlaceSearchResult _result = const PlaceSearchResult([]);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String get _q => _query.text.trim();

  void _onChanged(String _) => setState(() {});

  PlaceSearchResult _resultFor(String q) {
    if (_searched != q) {
      _searched = q;
      _result = widget.index.search(q);
    }
    return _result;
  }

  /// A result was tapped: hand it straight back to the field and close.
  void _select(PlaceSelection s) {
    FocusScope.of(context).unfocus();
    Navigator.pop(context, s);
  }

  /// The free-typed selection for the current text, or null when one is not
  /// allowed.
  PlaceSelection? get _customSelection {
    if (!widget.allowCustom || _q.length < 2) return null;
    final state = stateNamedIn(_q);
    if (widget.customNeedsState &&
        (state == null || state == TnState.nameEn)) {
      return null;
    }
    if (state == null) return PlaceSelection.custom(_q);
    final place = _q
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && stateNamedIn(p) == null)
        .join(', ');
    return PlaceSelection(
      city: place.isEmpty ? _q : place,
      state: state,
      custom: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = _resultFor(_q);
    final hits = result.hits;
    final custom = _customSelection;
    final showStateHint = widget.allowCustom &&
        widget.customNeedsState &&
        _q.length >= 2 &&
        (hits.isEmpty || result.isFallback) &&
        custom == null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        // A Material (not a decorated Container): the result rows are
        // ListTiles, which paint their background and ink on the nearest
        // Material ancestor — a plain coloured box would hide both.
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
                    const Icon(Icons.location_on_outlined,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: 8),
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
                  onChanged: _onChanged,
                  decoration: InputDecoration(
                    hintText: l10n.searchCityVillage,
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
                child: _q.length < 2
                    ? _hint(l10n.searchLocationHint)
                    : (hits.isEmpty && custom == null)
                            ? _hint(showStateHint
                                ? '${l10n.noLocationsFound}\n\n${l10n.placeWithStateHint}'
                                : l10n.noLocationsFound)
                            : ListView(
                                controller: scrollController,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                children: [
                                  if (result.isFallback && hits.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          8, 4, 8, 8),
                                      child: Text(l10n.nearestTownHint,
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              color: Colors.grey[700])),
                                    ),
                                  for (final h in hits) ...[
                                    _row(
                                      title: h.option.cityName(widget.lang),
                                      subtitle:
                                          '${h.option.districtName(widget.lang)} '
                                          '${l10n.district}, '
                                          '${TnState.nameFor(widget.lang)}',
                                      onTap: () => _select(
                                          h.option.toSelection(widget.lang)),
                                    ),
                                    const Divider(height: 1),
                                  ],
                                  // Free-typed fallback for a place the master
                                  // data does not carry. Stays inside this form.
                                  if (custom != null)
                                    _row(
                                      title: custom.city,
                                      subtitle: custom.state.isEmpty
                                          ? l10n.addThisPlace
                                          : '${l10n.addThisPlace} · ${custom.state}',
                                      leading: const Icon(
                                          Icons.add_location_alt_outlined,
                                          size: 20,
                                          color: AppColors.primary),
                                      onTap: () => _select(custom),
                                    ),
                                  if (showStateHint)
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(l10n.placeWithStateHint,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600])),
                                    ),
                                ],
                              ),
              ),
              const SafeArea(top: false, child: SizedBox(height: 6)),
            ],
          ),
        ),
      ),
    );
  }

  /// One search result: City/Village on top, "District, State" beneath.
  /// Tapping the row IS the selection — the chevron only signals that.
  Widget _row({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? leading,
  }) =>
      ListTile(
        onTap: onTap,
        dense: true,
        leading: leading,
        title: Text(title,
            maxLines: 2,
            style: const TextStyle(
                fontSize: 14.5, height: 1.3, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            maxLines: 2,
            style: TextStyle(
                fontSize: 12.5, height: 1.3, color: Colors.grey[600])),
        trailing: const Icon(Icons.chevron_right,
            size: 20, color: AppColors.primary),
      );

  Widget _hint(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.travel_explore_outlined,
                  size: 46, color: AppColors.primary.withValues(alpha: 0.35)),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ],
          ),
        ),
      );
}
