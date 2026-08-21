import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/location_model.dart';
import '../../providers/locale_provider.dart';
import '../../providers/location_provider.dart';

/// The app's ONE place picker — used everywhere a location is asked for
/// (native place, birth place, the second person's birth place, booking
/// location) so the UX is identical throughout (spec §31).
///
/// A city/village name on its own is ambiguous: the same name occurs in
/// several districts. So the search results always read
///
/// ```
/// அத்திக்கோலம்
/// Ramanathapuram, Tamil Nadu
/// ```
///
/// and the flow is: **Search → matching places → + to add → Save → the field
/// is populated** with "City, District, State" (spec §28/§29).
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

  /// Allows a free-typed place for a village that is not in the master data.
  final bool allowCustom;

  /// Fired with the chosen place once the member taps Save.
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
  });

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final options = await ref.read(allPlaceOptionsProvider.future);
    if (!context.mounted) return;
    final lang = ref.read(localeProvider)?.languageCode ?? 'en';
    final picked = await showModalBottomSheet<PlaceSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlaceSearchSheet(
        title: label,
        options: options,
        lang: lang,
        allowCustom: allowCustom,
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = (value ?? '').trim();
    final loading = ref.watch(allPlaceOptionsProvider).isLoading;
    return InkWell(
      onTap: loading ? null : () => _open(context, ref),
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: isRequired ? '$label *' : label,
          filled: true,
          fillColor: AppColors.scaffoldBg,
          isDense: true,
          errorText: errorText,
          helperText: context.l10n.locationNotListedNote,
          helperMaxLines: 2,
          prefixIcon: Icon(prefixIcon, size: 18),
          suffixIcon: loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : const Icon(Icons.search, size: 20),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
/// → **+** stages one → **Save** returns it to the field.
class _PlaceSearchSheet extends StatefulWidget {
  final String title;
  final List<PlaceOption> options;
  final String lang;
  final bool allowCustom;

  const _PlaceSearchSheet({
    required this.title,
    required this.options,
    required this.lang,
    required this.allowCustom,
  });

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  final _query = TextEditingController();

  /// The place staged by the + button. Nothing is returned until Save.
  PlaceSelection? _staged;

  static const _maxResults = 60;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String get _q => _query.text.trim();

  /// Matches against BOTH the displayed name and the canonical English name,
  /// so a Tamil-mode search still finds a place typed in English (and vice
  /// versa). Prefix matches rank above contains-matches.
  List<PlaceOption> get _results {
    final q = _q.toLowerCase();
    if (q.length < 2) return const [];
    final starts = <PlaceOption>[];
    final contains = <PlaceOption>[];
    for (final o in widget.options) {
      final shown = o.cityName(widget.lang).toLowerCase();
      final en = o.city.nameEn.toLowerCase();
      if (shown.startsWith(q) || en.startsWith(q)) {
        starts.add(o);
      } else if (shown.contains(q) || en.contains(q)) {
        contains.add(o);
      }
      if (starts.length >= _maxResults) break;
    }
    return [...starts, ...contains].take(_maxResults).toList();
  }

  void _stage(PlaceSelection s) {
    setState(() => _staged = s);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final results = _results;
    final showCustom = widget.allowCustom && _q.length >= 2;

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
                  onChanged: (_) => setState(() {}),
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
                    : (results.isEmpty && !showCustom)
                        ? _hint(l10n.noLocationsFound)
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: results.length + (showCustom ? 1 : 0),
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              if (i < results.length) {
                                final o = results[i];
                                final sel = o.toSelection(widget.lang);
                                return _row(
                                  title: o.cityName(widget.lang),
                                  subtitle: o.subtitle(widget.lang),
                                  selected: _staged?.cityId == o.city.id,
                                  onAdd: () => _stage(sel),
                                );
                              }
                              // Free-typed fallback for a place the master
                              // data does not carry. Stays inside this form.
                              return _row(
                                title: _q,
                                subtitle: l10n.othersOption,
                                selected:
                                    _staged?.custom == true &&
                                        _staged?.city == _q,
                                onAdd: () =>
                                    _stage(PlaceSelection.custom(_q)),
                              );
                            },
                          ),
              ),
              if (_staged != null) _stagedBar(l10n),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _staged == null
                          ? null
                          : () => Navigator.pop(context, _staged),
                      icon: const Icon(Icons.check, size: 20),
                      label: Text(l10n.saveLocation,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One search result: City/Village on top, "District, State" beneath, and a
  /// **+** to stage it (spec §28/§29).
  Widget _row({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onAdd,
  }) =>
      ListTile(
        onTap: onAdd,
        dense: true,
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
        trailing: IconButton(
          tooltip: context.l10n.addLocationTooltip,
          onPressed: onAdd,
          icon: Icon(
              selected ? Icons.check_circle : Icons.add_circle_outline,
              color: selected ? AppColors.success : AppColors.primary),
        ),
      );

  /// The staged selection, shown above Save so the member can see exactly what
  /// will land in the field.
  Widget _stagedBar(dynamic l10n) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.place, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.selectedLocationLabel,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[600])),
                  const SizedBox(height: 2),
                  Text(_staged!.display,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _staged = null),
              icon: const Icon(Icons.close, size: 18, color: AppColors.error),
              tooltip: l10n.remove,
            ),
          ],
        ),
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
