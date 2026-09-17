import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/location_catalog.dart';
import '../../core/data/master_option.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/location_search.dart';
import '../../core/utils/place_additions.dart';
import '../../l10n/app_localizations.dart';
import '../../models/location_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/location_provider.dart';
import '../../services/firebase/place_additions_service.dart';

/// The app's ONE place picker — used everywhere a location is asked for
/// (profile location, native place, birth place, the second person's birth
/// place, partner-preference location) so the search is identical throughout
/// (spec §31). All of them search the same [PlaceSearchIndex], built from the
/// bundled location JSON plus the places members have added.
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
/// A place that is NOT listed is added from the same sheet: a pinned
/// **+ Add "…"** row (it sits directly under the search box, so the keyboard
/// never covers it) opens a short form that asks where the place is — a Tamil
/// Nadu district, another state, or another country — and saves it to the
/// shared list (`master_options/places`) for every member. The new place is
/// selected straight away. A duplicate (same name under the same parent,
/// ignoring case, spacing and transliteration) is never created: the existing
/// place is offered instead.
///
/// Why the old sheet left members stuck: the member's own City field refused
/// any free-typed place unless it named a state OUTSIDE Tamil Nadu, and the
/// other fields kept a typed place only inside the form, so an unlisted Tamil
/// Nadu village could neither be chosen nor added. The results area also
/// shrank to a sliver once the keyboard opened.
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

  /// Offers "+ Add" for a place that is not listed.
  final bool allowCustom;

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
  });

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    // The field subscribed to the member-added places when it was shown (see
    // [build]); only a tap in the first moments of a session can beat their
    // snapshot. Wait for it briefly so the first search includes them —
    // capped, so a missing connection never holds the picker back.
    if (!ref.read(placeAdditionsProvider).hasValue) {
      try {
        await ref
            .read(placeAdditionsProvider.future)
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        // Unavailable — the bundled places still open at once.
      }
      if (!context.mounted) return;
    }
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
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.locationsLoadFailed),
            action: SnackBarAction(
              label: l10n.retry,
              onPressed: () => _open(context, ref),
            ),
          ),
        );
      return;
    }
    if (!context.mounted) return;
    final lang = ref.read(localeProvider)?.languageCode ?? 'en';
    final picked = await showModalBottomSheet<PlacePick>(
      context: context,
      isScrollControlled: true,
      // Keeps the tall sheet below the status bar.
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlaceSearchSheet(
        title: label,
        index: index,
        lang: lang,
        allowCustom: allowCustom,
      ),
    );
    if (picked == null) return;
    onChanged(picked.selection);
    final message = picked.message;
    if (message != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  picked.saved
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: picked.saved ? AppColors.success : null,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start listening for member-added places as soon as a place field is on
    // screen, so they are ready by the time it is tapped.
    ref.watch(placeAdditionsProvider);
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 16,
          ),
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

/// What the sheet hands back: the place, plus the confirmation to show once it
/// has closed (null for an ordinary pick).
class PlacePick {
  final PlaceSelection selection;
  final String? message;

  /// True when the place was saved to (or found on) the shared list.
  final bool saved;

  const PlacePick(this.selection, {this.message, this.saved = false});
}

/// The search sheet: type → matching places (City/Village + District + State)
/// → tap one → it is returned to the field and the sheet closes. Or, for a
/// place that is not listed: + Add → choose where it is → Add place.
class PlaceSearchSheet extends ConsumerStatefulWidget {
  final String title;
  final PlaceSearchIndex index;
  final String lang;
  final bool allowCustom;

  const PlaceSearchSheet({
    super.key,
    required this.title,
    required this.index,
    required this.lang,
    required this.allowCustom,
  });

  @override
  ConsumerState<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends ConsumerState<PlaceSearchSheet> {
  final _query = TextEditingController();
  final _name = TextEditingController();

  /// The query [_result] was computed for. The search is an in-memory pass
  /// over ~1,100 pre-normalised rows (well under a millisecond), so it runs
  /// once per distinct query — no debounce delay is needed, and none is added
  /// between the member's typing and the results.
  String? _searched;
  PlaceSearchResult _result = const PlaceSearchResult([]);
  List<PlaceAddition> _others = const [];

  // ── "+ Add" form state ────────────────────────────────────────────────────
  bool _adding = false;
  PlaceParentKind _kind = PlaceParentKind.district;
  int? _districtId;
  String? _stateId;
  String? _countryId;

  /// True while the new place is being written — the form is locked and the
  /// button shows progress, so it cannot be submitted twice.
  bool _saving = false;
  String? _nameError;
  String? _parentError;
  String? _saveError;

  /// The listed place the member is about to duplicate — offered instead.
  PlaceSelection? _existing;
  String? _existingName;

  @override
  void dispose() {
    _query.dispose();
    _name.dispose();
    super.dispose();
  }

  String get _q => _query.text.trim();
  bool get _tamil => widget.lang == 'ta';

  void _onChanged(String _) => setState(() {});

  void _searchFor(String q) {
    if (_searched == q) return;
    _searched = q;
    _result = widget.index.search(q);
    _others = widget.index.searchOthers(q);
  }

  /// A result was tapped: hand it straight back to the field and close.
  void _select(PlaceSelection s, {String? message, bool saved = false}) {
    FocusScope.of(context).unfocus();
    Navigator.pop(context, PlacePick(s, message: message, saved: saved));
  }

  bool get _showAddRow =>
      widget.allowCustom && _q.length >= 2 && !widget.index.hasExactPlace(_q);

  // ── Add flow ──────────────────────────────────────────────────────────────

  /// Opens the add form for what was typed, pre-choosing the parent the member
  /// already named ("Kovilpatti, Thoothukudi" → that district; "Kochi, Kerala"
  /// → Kerala; "Dubai, UAE" → UAE).
  void _startAdding() {
    final typed = _q;
    final comma = typed.indexOf(',');
    final rest = comma > 0 ? typed.substring(comma + 1) : '';
    _name.text = checkPlaceName(placePartOf(typed)).name;

    final district = rest.isEmpty ? null : widget.index.districtNamed(rest);
    final country = rest.isEmpty ? null : countryNamedIn(rest);
    final state = rest.isEmpty ? null : stateNamedIn(rest);
    _districtId = district?.id;
    _stateId = null;
    _countryId = null;
    if (district != null) {
      _kind = PlaceParentKind.district;
    } else if (country != null) {
      _kind = PlaceParentKind.country;
      _countryId = country.id;
    } else if (state != null && state != TnState.nameEn) {
      _kind = PlaceParentKind.state;
      _stateId = LocationCatalog.indianStates.byValue(state)?.id;
    } else {
      _kind = PlaceParentKind.district;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _adding = true;
      _nameError = null;
      _parentError = null;
      _saveError = null;
      _existing = null;
    });
  }

  List<TnDistrict> get _districts => [...widget.index.districts]
    ..sort((a, b) => a.nameFor(widget.lang).compareTo(b.nameFor(widget.lang)));

  List<MasterOption> get _states => [
    for (final s in LocationCatalog.indianStates)
      if (s.id != 'st_tn' && s.id != 'st_other') s,
  ];

  List<MasterOption> get _countries => [
    for (final c in LocationCatalog.countries)
      if (c.id != 'ctry_india' && c.id != 'ctry_other') c,
  ];

  /// The chosen parent, or null when the member has not chosen one yet.
  PlaceParent? get _parent {
    switch (_kind) {
      case PlaceParentKind.district:
        for (final d in widget.index.districts) {
          if (d.id == _districtId) return PlaceParent.district(d);
        }
        return null;
      case PlaceParentKind.state:
        for (final s in _states) {
          if (s.id == _stateId) return PlaceParent.state(s);
        }
        return null;
      case PlaceParentKind.country:
        for (final c in _countries) {
          if (c.id == _countryId) return PlaceParent.country(c);
        }
        return null;
    }
  }

  /// "Thoothukudi District, Tamil Nadu" / "Kerala" / "UAE", in the viewer's
  /// language.
  String _parentLabel(AppLocalizations l10n, PlaceParent parent) {
    switch (parent.kind) {
      case PlaceParentKind.district:
        final d = widget.index.districts.firstWhere(
          (d) => d.id == parent.districtId,
        );
        return '${d.nameFor(widget.lang)} ${l10n.district}, '
            '${TnState.nameFor(widget.lang)}';
      case PlaceParentKind.state:
        return LocationCatalog.indianStates
                .byValue(parent.state)
                ?.display(tamil: _tamil) ??
            parent.state;
      case PlaceParentKind.country:
        return LocationCatalog.countries
                .byValue(parent.country)
                ?.display(tamil: _tamil) ??
            parent.country;
    }
  }

  String? _nameProblemText(AppLocalizations l10n, PlaceNameProblem? p) =>
      switch (p) {
        null => null,
        PlaceNameProblem.empty => l10n.placeNameEmpty,
        PlaceNameProblem.tooShort => l10n.placeNameTooShort,
        PlaceNameProblem.tooLong => l10n.placeNameTooLong,
        PlaceNameProblem.invalidCharacters => l10n.placeNameInvalid,
      };

  /// The member's uid, or null for a guest session (which the rules do not let
  /// write to the shared list).
  String? _memberUid() {
    try {
      return ref.read(memberUidProvider);
    } catch (_) {
      return null;
    }
  }

  /// The place as a selection WITHOUT a shared-list row behind it.
  PlaceSelection _formOnlySelection(String name, PlaceParent parent) {
    switch (parent.kind) {
      case PlaceParentKind.district:
        final d = widget.index.districts.firstWhere(
          (d) => d.id == parent.districtId,
        );
        return PlaceSelection(
          city: name,
          cityEn: name,
          district: d.nameFor(widget.lang),
          districtEn: d.nameEn,
          districtId: d.id,
          state: TnState.nameFor(widget.lang),
          custom: true,
        );
      case PlaceParentKind.state:
        return PlaceSelection(
          city: name,
          cityEn: name,
          state: parent.state,
          custom: true,
        );
      case PlaceParentKind.country:
        return PlaceSelection(
          city: name,
          cityEn: name,
          state: '',
          country: parent.country,
          custom: true,
        );
    }
  }

  /// The selection for a place on the shared list.
  PlaceSelection _selectionFor(PlaceAddition place) {
    final city = place.toTnCity();
    if (city != null) {
      for (final d in widget.index.districts) {
        if (d.id == city.districtId) {
          return PlaceOption(city: city, district: d).toSelection(widget.lang);
        }
      }
    }
    return place.toSelection(widget.lang);
  }

  Future<void> _save() async {
    if (_saving) return; // one submission at a time
    final l10n = context.l10n;
    final check = checkPlaceName(_name.text);
    final parent = _parent;
    setState(() {
      _nameError = _nameProblemText(l10n, check.problem);
      _parentError = parent != null
          ? null
          : switch (_kind) {
              PlaceParentKind.district => l10n.chooseDistrict,
              PlaceParentKind.state => l10n.chooseState,
              PlaceParentKind.country => l10n.chooseCountry,
            };
      _saveError = null;
      _existing = null;
    });
    if (check.problem != null || parent == null) return;
    final name = check.name;
    if (_name.text != name) _name.text = name;

    // Already listed under the same parent? Offer it — never a duplicate.
    if (parent.kind == PlaceParentKind.district) {
      final existing = widget.index.exactMatch(
        name,
        districtId: parent.districtId!,
      );
      if (existing != null) {
        setState(() {
          _existing = existing.toSelection(widget.lang);
          _existingName = existing.cityName(widget.lang);
        });
        return;
      }
    } else {
      final existing = widget.index.otherWithKey(
        placeAdditionKey(name, parent),
      );
      if (existing != null) {
        setState(() {
          _existing = existing.toSelection(widget.lang);
          _existingName = existing.nameFor(widget.lang);
        });
        return;
      }
    }

    final uid = _memberUid();
    if (uid == null) {
      // A guest cannot add to the shared list; the place still fills the form.
      _select(
        _formOnlySelection(name, parent),
        message: l10n.placeUsedForFormOnly(name),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await ref
          .read(placeAdditionsServiceProvider)
          .add(name: name, parent: parent, uid: uid);
      // Usable at once — by the location field resolving the new id, and by
      // the next search — without waiting for the live list to catch up.
      ref.read(locationRepositoryProvider).addAdditionLocally(result.place);
      ref.invalidate(allPlaceOptionsProvider);
      if (!mounted) return;
      final shown = result.place.nameFor(widget.lang);
      _select(
        _selectionFor(result.place),
        message: result.alreadyExisted
            ? l10n.placeAlreadyListedSelected(shown)
            : l10n.placeAddedSuccess(shown),
        saved: true,
      );
    } on PlaceSaveException catch (e) {
      if (!mounted) return;
      setState(
        () => _saveError = switch (e.reason) {
          PlaceSaveFailure.offline => l10n.placeSaveOffline,
          PlaceSaveFailure.notAllowed => l10n.placeSaveNotAllowed,
          PlaceSaveFailure.unknown => l10n.placeSaveFailed,
        },
      );
    } catch (e) {
      debugPrint('[PlacePicker] add place failed: $e');
      if (mounted) setState(() => _saveError = l10n.placeSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _useWithoutSaving() {
    final check = checkPlaceName(_name.text);
    final parent = _parent;
    if (check.problem != null || parent == null) return;
    _select(
      _formOnlySelection(check.name, parent),
      message: context.l10n.placeUsedForFormOnly(check.name),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // The keyboard overlays the bottom of this tall sheet; scrollable content
    // is padded by its height so every row and button can be scrolled above
    // it. (The sheet itself no longer shrinks with the keyboard, which is what
    // squeezed the results into a sliver.)
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return DraggableScrollableSheet(
      // Fixed height: dragging the results list must scroll it, not collapse
      // the sheet under the keyboard. Swipe the handle to dismiss.
      initialChildSize: 0.94,
      minChildSize: 0.94,
      maxChildSize: 0.94,
      expand: false,
      // A Material (not a decorated Container): the result rows are
      // ListTiles, which paint their background and ink on the nearest
      // Material ancestor — a plain coloured box would hide both.
      builder: (_, scrollController) => Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Row(
                children: [
                  if (_adding)
                    IconButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _adding = false),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: l10n.back,
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 8, 0),
                      child: Icon(
                        Icons.location_on_outlined,
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      _adding ? l10n.addNewPlaceTitle : widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: l10n.close,
                  ),
                ],
              ),
            ),
            if (_adding)
              Expanded(child: _addForm(l10n, scrollController, keyboard))
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  decoration: InputDecoration(
                    hintText: l10n.searchCityVillage,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            tooltip: l10n.clear,
                            onPressed: () => setState(_query.clear),
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.scaffoldBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              // Pinned right under the search box — above the results, so the
              // keyboard can never hide it.
              if (_showAddRow) _addRow(l10n),
              Expanded(child: _results(l10n, scrollController, keyboard)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _results(
    AppLocalizations l10n,
    ScrollController controller,
    double keyboard,
  ) {
    if (_q.length < 2) return _hint(l10n.searchLocationHint, keyboard);
    _searchFor(_q);
    final hits = _result.hits;
    if (hits.isEmpty && _others.isEmpty) {
      return _hint(
        _showAddRow
            ? '${l10n.noLocationsFound}\n\n${l10n.placeNotListedHint}'
            : l10n.noLocationsFound,
        keyboard,
      );
    }
    return ListView(
      controller: controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + keyboard),
      children: [
        if (_result.isFallback && hits.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Text(
              l10n.nearestTownHint,
              style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
            ),
          ),
        for (final h in hits) ...[
          _row(
            title: h.option.cityName(widget.lang),
            subtitle:
                '${h.option.districtName(widget.lang)} '
                '${l10n.district}, '
                '${TnState.nameFor(widget.lang)}',
            onTap: () => _select(h.option.toSelection(widget.lang)),
          ),
          const Divider(height: 1),
        ],
        // Member-added places outside Tamil Nadu.
        for (final o in _others) ...[
          _row(
            title: o.nameFor(widget.lang),
            subtitle: [
              if (o.state.isNotEmpty)
                LocationCatalog.indianStates
                        .byValue(o.state)
                        ?.display(tamil: _tamil) ??
                    o.state,
              LocationCatalog.countries
                      .byValue(o.country)
                      ?.display(tamil: _tamil) ??
                  o.country,
            ].join(', '),
            onTap: () => _select(o.toSelection(widget.lang)),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }

  /// The "+ Add" row: a plus in a filled circle, `Add "typed name"` and a
  /// one-line explanation, tinted in the app's primary colour.
  Widget _addRow(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
    child: Material(
      key: const ValueKey('place-add-row'),
      color: AppColors.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        onTap: _startAdding,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.addPlaceNamed(placePartOf(_q)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.addPlaceRowHint,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _addForm(
    AppLocalizations l10n,
    ScrollController controller,
    double keyboard,
  ) {
    final parent = _parent;
    final check = checkPlaceName(_name.text);
    final preview = parent != null && check.problem == null
        ? '${check.name}, ${_parentLabel(l10n, parent)}'
        : null;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(12));

    return ListView(
      controller: controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + keyboard),
      children: [
        TextField(
          key: const ValueKey('place-add-name'),
          controller: _name,
          enabled: !_saving,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {
            _nameError = null;
            _existing = null;
            _saveError = null;
          }),
          decoration: InputDecoration(
            labelText: l10n.placeNameLabel,
            errorText: _nameError,
            prefixIcon: const Icon(Icons.edit_location_alt_outlined),
            isDense: true,
            filled: true,
            fillColor: AppColors.scaffoldBg,
            border: border,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          l10n.placeWhereIsIt,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in PlaceParentKind.values)
              ChoiceChip(
                label: Text(switch (kind) {
                  PlaceParentKind.district => l10n.placeInTamilNadu,
                  PlaceParentKind.state => l10n.placeOtherState,
                  PlaceParentKind.country => l10n.placeOutsideIndia,
                }),
                selected: _kind == kind,
                selectedColor: AppColors.primary.withValues(alpha: 0.12),
                labelStyle: TextStyle(
                  color: _kind == kind ? AppColors.primary : null,
                  fontWeight: _kind == kind ? FontWeight.w600 : null,
                ),
                onSelected: _saving
                    ? null
                    : (_) => setState(() {
                        _kind = kind;
                        _parentError = null;
                        _existing = null;
                        _saveError = null;
                      }),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _parentDropdown(l10n, border),
        if (_parentError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              _parentError!,
              style: const TextStyle(color: AppColors.error, fontSize: 12.5),
            ),
          ),
        if (preview != null)
          Padding(
            padding: const EdgeInsets.only(top: 12, left: 4),
            child: Text(
              l10n.placeSavedAs(preview),
              style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
            ),
          ),
        if (_existing != null && parent != null)
          _notice(
            icon: Icons.info_outline,
            color: AppColors.info,
            text: l10n.placeAlreadyListed(
              _existingName ?? check.name,
              _parentLabel(l10n, parent),
            ),
            actions: [
              FilledButton.tonal(
                onPressed: () => _select(_existing!),
                child: Text(
                  l10n.selectExistingPlace(_existingName ?? check.name),
                ),
              ),
            ],
          ),
        if (_saveError != null)
          _notice(
            icon: Icons.error_outline,
            color: AppColors.error,
            text: _saveError!,
            actions: [
              TextButton(
                onPressed: _saving ? null : _save,
                child: Text(l10n.tryAgain),
              ),
              TextButton(
                onPressed: _saving ? null : _useWithoutSaving,
                child: Text(l10n.useWithoutSaving),
              ),
            ],
          ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving
                    ? null
                    : () => setState(() => _adding = false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(l10n.cancel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                key: const ValueKey('place-add-save'),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_location_alt_outlined),
                label: Text(_saving ? l10n.savingPlace : l10n.addPlaceButton),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withValues(
                    alpha: 0.7,
                  ),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _parentDropdown(AppLocalizations l10n, InputBorder border) {
    InputDecoration decoration(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: border,
    );
    void changed(VoidCallback update) => setState(() {
      update();
      _parentError = null;
      _existing = null;
      _saveError = null;
    });

    switch (_kind) {
      case PlaceParentKind.district:
        return DropdownButtonFormField<int>(
          key: const ValueKey('place-parent-district'),
          initialValue: _districtId,
          isExpanded: true,
          menuMaxHeight: 360,
          decoration: decoration(l10n.district, Icons.map_outlined),
          hint: Text(l10n.chooseDistrict),
          items: [
            for (final d in _districts)
              DropdownMenuItem(
                value: d.id,
                child: Text(d.nameFor(widget.lang)),
              ),
          ],
          onChanged: _saving ? null : (v) => changed(() => _districtId = v),
        );
      case PlaceParentKind.state:
        return DropdownButtonFormField<String>(
          key: const ValueKey('place-parent-state'),
          initialValue: _stateId,
          isExpanded: true,
          menuMaxHeight: 360,
          decoration: decoration(l10n.state, Icons.map_outlined),
          hint: Text(l10n.chooseState),
          items: [
            for (final s in _states)
              DropdownMenuItem(
                value: s.id,
                child: Text(s.display(tamil: _tamil)),
              ),
          ],
          onChanged: _saving ? null : (v) => changed(() => _stateId = v),
        );
      case PlaceParentKind.country:
        return DropdownButtonFormField<String>(
          key: const ValueKey('place-parent-country'),
          initialValue: _countryId,
          isExpanded: true,
          menuMaxHeight: 360,
          decoration: decoration(l10n.country, Icons.public),
          hint: Text(l10n.chooseCountry),
          items: [
            for (final c in _countries)
              DropdownMenuItem(
                value: c.id,
                child: Text(c.display(tamil: _tamil)),
              ),
          ],
          onChanged: _saving ? null : (v) => changed(() => _countryId = v),
        );
    }
  }

  Widget _notice({
    required IconData icon,
    required Color color,
    required String text,
    required List<Widget> actions,
  }) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
            ),
          ],
        ),
        Wrap(alignment: WrapAlignment.end, spacing: 4, children: actions),
      ],
    ),
  );

  /// One search result: City/Village on top, "District, State" beneath.
  /// Tapping the row IS the selection — the chevron only signals that.
  Widget _row({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => ListTile(
    onTap: onTap,
    dense: true,
    title: Text(
      title,
      maxLines: 2,
      style: const TextStyle(
        fontSize: 14.5,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
    ),
    subtitle: Text(
      subtitle,
      maxLines: 2,
      style: TextStyle(fontSize: 12.5, height: 1.3, color: Colors.grey[600]),
    ),
    trailing: const Icon(
      Icons.chevron_right,
      size: 20,
      color: AppColors.primary,
    ),
  );

  Widget _hint(String text, double keyboard) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(28, 28, 28, 28 + keyboard),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.travel_explore_outlined,
            size: 46,
            color: AppColors.primary.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ],
      ),
    ),
  );
}
