import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/dev_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/demo_data_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../core/utils/l10n_ext.dart';
import '../../widgets/common/dual_range_slider_field.dart';
import '../../widgets/common/location_picker_section.dart';
import '../../widgets/common/religion_caste_fields.dart';
import '../../widgets/common/searchable_multi_select_field.dart';

/// Partner Preferences — lets the user configure preferred match criteria.
/// Registered at `/partner-preferences`. Reached from the Home dashboard
/// "Partner Preferences" quick action (and Settings).
class PartnerPreferencesScreen extends ConsumerStatefulWidget {
  const PartnerPreferencesScreen({super.key});

  @override
  ConsumerState<PartnerPreferencesScreen> createState() =>
      _PartnerPreferencesScreenState();
}

class _PartnerPreferencesScreenState
    extends ConsumerState<PartnerPreferencesScreen> {
  static const String _any = 'Any';

  bool _loaded = false;
  bool _saving = false;

  // Form state
  int _minAge = 18;
  int _maxAge = 40;
  String _minHeight = "5'0\"";
  String _maxHeight = "5'10\"";
  // Location preference — State → District → City, always chosen from the
  // master datasets via [LocationPickerSection] (city is never typed).
  // Tamil Nadu is the default state when nothing is saved yet.
  static const String _defaultState = 'Tamil Nadu';
  String? _state = _defaultState;
  String? _district;
  String? _city;
  // Bumped on Reset so the (stateful) location picker rebuilds with defaults.
  int _locationEpoch = 0;
  final Set<String> _education = {};
  final Set<String> _occupation = {};
  String _income = _any;
  String _maritalStatus = _any;
  String _rasi = _any;
  String _nakshatra = _any;
  bool _horoMatch = true;
  String _language = _any;
  String _religion = _any;
  String? _religionId;
  String _caste = _any;
  String? _casteId;

  // Option lists
  List<String> get _incomeOpts => [_any, ...AppConstants.incomeList];
  List<String> get _maritalOpts => [_any, ...AppConstants.maritalStatusList];
  List<String> get _rasiOpts => [_any, ...AppConstants.rasiEnList];
  List<String> get _nakshatraOpts => [_any, ...AppConstants.nakshatraList];
  List<String> get _languageOpts => [_any, ...AppConstants.motherTongueList];

  void _populate(PartnerPreferences p) {
    var lo = p.minAge.clamp(18, 60);
    var hi = p.maxAge.clamp(18, 60);
    if (lo > hi) {
      final t = lo;
      lo = hi;
      hi = t;
    }
    _minAge = lo;
    _maxAge = hi;
    _minHeight =
        AppConstants.heightList.contains(p.minHeight) ? p.minHeight : "5'0\"";
    _maxHeight =
        AppConstants.heightList.contains(p.maxHeight) ? p.maxHeight : "5'10\"";
    _state = (p.state ?? '').trim().isNotEmpty ? p.state : _defaultState;
    _district = (p.district ?? '').trim().isNotEmpty ? p.district : null;
    _city = (p.city ?? '').trim().isNotEmpty ? p.city : null;
    _education
      ..clear()
      ..addAll(p.education);
    _occupation
      ..clear()
      ..addAll(p.occupation);
    _income = _safe(p.income, _incomeOpts);
    _maritalStatus = _safe(p.maritalStatus, _maritalOpts);
    _rasi = _safe(p.rasi, _rasiOpts);
    _nakshatra = _safe(p.nakshatra, _nakshatraOpts);
    _horoMatch = p.horoscopeMatchRequired;
    _language = _safe(p.motherTongue, _languageOpts);
    _religion = p.religion.isEmpty ? _any : p.religion;
    _religionId = p.religionId;
    _caste = (p.caste ?? '').isEmpty ? _any : p.caste!;
    _casteId = p.casteId;
  }

  String _safe(String? value, List<String> opts) =>
      (value != null && value.isNotEmpty && opts.contains(value)) ? value : _any;

  PartnerPreferences _buildPrefs() => PartnerPreferences(
        minAge: _minAge,
        maxAge: _maxAge,
        minHeight: _minHeight,
        maxHeight: _maxHeight,
        education: _education.toList(),
        occupation: _occupation.toList(),
        income: _income,
        religion: _religion,
        religionId: _religionId,
        caste: _caste == _any ? null : _caste,
        casteId: _casteId,
        city: (_city ?? '').trim().isEmpty ? null : _city!.trim(),
        state: (_state ?? '').trim().isEmpty ? null : _state!.trim(),
        district: (_district ?? '').trim().isEmpty ? null : _district!.trim(),
        rasi: _rasi == _any ? null : _rasi,
        nakshatra: _nakshatra == _any ? null : _nakshatra,
        maritalStatus: _maritalStatus,
        motherTongue: _language,
        horoscopeMatchRequired: _horoMatch,
      );

  Future<void> _save() async {
    final profile = ref.read(myProfileProvider).valueOrNull;
    debugPrint('[PartnerPreferences] save tapped (profile=${profile?.id})');
    if (profile == null) {
      _toast('Create your profile first to save preferences.');
      return;
    }
    setState(() => _saving = true);
    final prefs = _buildPrefs();
    try {
      if (kBypassAuth) {
        ref
            .read(demoProfilesProvider.notifier)
            .upsert(profile.copyWith(partnerPreferences: prefs));
      } else {
        await ref
            .read(profileRepositoryProvider)
            .updateProfile(profile.id, {'partnerPreferences': prefs.toMap()});
        ref.invalidate(myProfileProvider);
      }
      if (mounted) _toast('Preferences saved');
    } catch (e) {
      debugPrint('[PartnerPreferences] save error: $e');
      if (mounted) _toast('Could not save preferences. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() {
    setState(() {
      _populate(const PartnerPreferences());
      _loaded = true;
      _locationEpoch++; // recreate the location picker with the defaults
    });
    _toast('Preferences reset to defaults');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[PartnerPreferencesScreen] build — route /partner-preferences opened');
    final profileAsync = ref.watch(myProfileProvider);
    // Prefill once from the saved profile preferences. The body is held back
    // until then so [LocationPickerSection] (stateful) seeds with the SAVED
    // state/district/city instead of the defaults.
    profileAsync.whenData((p) {
      if (!_loaded) {
        _populate(p?.partnerPreferences ?? const PartnerPreferences());
        _loaded = true;
      }
    });

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Partner Preferences'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: !_loaded
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // Age & Height are dual range sliders — no wheel/scroll pickers and
          // no Minimum/Maximum dropdown pairs anywhere (spec §9–§11).
          _card(
            icon: Icons.cake_outlined,
            title: context.l10n.ageRangeLabel,
            child: DualRangeSliderField(
              label: context.l10n.age,
              min: 18,
              max: 60,
              startValue: _minAge,
              endValue: _maxAge,
              startCaption: context.l10n.minimumAge,
              endCaption: context.l10n.maximumAge,
              formatRange: (lo, hi) => context.l10n.ageRangeValue(lo, hi),
              onChanged: (lo, hi) => setState(() {
                _minAge = lo;
                _maxAge = hi;
              }),
            ),
          ),
          _card(
            icon: Icons.height,
            title: context.l10n.heightRangeLabel,
            child: Builder(builder: (context) {
              final heights = AppConstants.heightList;
              int idx(String v, int fallback) {
                final i = heights.indexOf(v);
                return i >= 0 ? i : fallback;
              }

              final lo = idx(_minHeight, 0);
              final hi = idx(_maxHeight, heights.length - 1);
              return DualRangeSliderField(
                label: context.l10n.height,
                min: 0,
                max: heights.length - 1,
                startValue: lo,
                endValue: hi < lo ? lo : hi,
                startCaption: context.l10n.minimumHeight,
                endCaption: context.l10n.maximumHeight,
                formatValue: (i) => heights[i.clamp(0, heights.length - 1)],
                formatRange: (a, b) =>
                    context.l10n.rangeValue(heights[a], heights[b]),
                onChanged: (a, b) => setState(() {
                  _minHeight = heights[a];
                  _maxHeight = heights[b];
                }),
              );
            }),
          ),
          _card(
            icon: Icons.location_on_outlined,
            title: 'Location Preference',
            subtitle: 'State → District → City, from the master data',
            child: LocationPickerSection(
              key: ValueKey('pref-location-$_locationEpoch'),
              // Tamil Nadu is pre-selected for a fresh preference; a saved
              // selection is restored as-is. City is never typed by hand.
              initialState: _state,
              initialDistrict: _district,
              initialCity: _city,
              isRequired: false,
              onChanged: (loc) => setState(() {
                _state = loc.state.isEmpty ? null : loc.state;
                _district = loc.district.isEmpty ? null : loc.district;
                _city = loc.city.isEmpty ? null : loc.city;
              }),
            ),
          ),
          _card(
            icon: Icons.school_outlined,
            title: 'Education Preference',
            subtitle: 'Search and select any number of qualifications',
            child: SearchableMultiSelectField(
              label: 'Education',
              items: AppConstants.educationList,
              selected: _education.toList(),
              onChanged: (v) => setState(() {
                _education
                  ..clear()
                  ..addAll(v);
              }),
            ),
          ),
          _card(
            icon: Icons.work_outline,
            title: 'Profession Preference',
            subtitle: 'Search and select any number of professions',
            child: SearchableMultiSelectField(
              label: 'Profession',
              items: AppConstants.occupationList,
              selected: _occupation.toList(),
              onChanged: (v) => setState(() {
                _occupation
                  ..clear()
                  ..addAll(v);
              }),
            ),
          ),
          _card(
            icon: Icons.currency_rupee,
            title: 'Salary Preference',
            child: _dropdown('Minimum annual income', _income, _incomeOpts,
                (v) => setState(() => _income = v!)),
          ),
          _card(
            icon: Icons.favorite_border,
            title: 'Marital Status Preference',
            child: _dropdown('Marital status', _maritalStatus, _maritalOpts,
                (v) => setState(() => _maritalStatus = v!)),
          ),
          _card(
            icon: Icons.auto_awesome_outlined,
            title: 'Horoscope Preferences',
            child: Column(
              children: [
                _dropdown('Rasi', _rasi, _rasiOpts,
                    (v) => setState(() => _rasi = v!)),
                const SizedBox(height: 12),
                _dropdown('Natchathiram (Nakshatra)', _nakshatra, _nakshatraOpts,
                    (v) => setState(() => _nakshatra = v!)),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.primary,
                  title: const Text('Horoscope Match Required',
                      style: TextStyle(fontSize: 14)),
                  subtitle: Text(_horoMatch ? 'Yes' : 'No',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  value: _horoMatch,
                  onChanged: (v) => setState(() => _horoMatch = v),
                ),
              ],
            ),
          ),
          _card(
            icon: Icons.translate,
            title: 'Language Preference',
            child: _dropdown('Mother tongue', _language, _languageOpts,
                (v) => setState(() => _language = v!)),
          ),
          _card(
            icon: Icons.diversity_3_outlined,
            title: 'Religion / Community Preference',
            child: ReligionCasteFields(
              religionId: _religionId,
              religionName: _religion == _any ? null : _religion,
              casteId: _casteId,
              casteName: _caste == _any ? null : _caste,
              subCasteId: null,
              subCasteName: null,
              showSubcaste: false,
              religionRequired: false,
              casteRequired: false,
              onReligionChanged: (id, name) => setState(() {
                _religionId = id;
                _religion = name ?? _any;
                _casteId = null;
                _caste = _any;
              }),
              onCasteChanged: (id, name) => setState(() {
                _casteId = id;
                _caste = name ?? _any;
              }),
              onSubcasteChanged: (_, __) {},
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Saving...' : 'Save Preferences'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _reset,
              icon: const Icon(Icons.refresh),
              label: const Text('Reset Preferences'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]);
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  Widget _card({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(subtitle,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      );

  Widget _dropdown(String label, String value, List<String> options,
      ValueChanged<String?> onChanged) {
    final safeValue = options.contains(value) ? value : options.first;
    return DropdownButtonFormField<String>(
      value: safeValue,
      isExpanded: true,
      decoration: _inputDecoration(label),
      items: options
          .map((o) => DropdownMenuItem(
                value: o,
                child: Text(o, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }

}
