import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/dev_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/demo_data_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';

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
  RangeValues _age = const RangeValues(18, 40);
  String _minHeight = "5'0\"";
  String _maxHeight = "5'10\"";
  final TextEditingController _cityCtrl = TextEditingController();
  String _state = _any;
  String _country = _any;
  final Set<String> _education = {};
  final Set<String> _occupation = {};
  String _income = _any;
  String _maritalStatus = _any;
  String _rasi = _any;
  String _nakshatra = _any;
  bool _horoMatch = true;
  String _language = _any;
  String _religion = _any;

  // Option lists
  List<String> get _stateOpts => [_any, ...AppConstants.indianStates];
  List<String> get _countryOpts => [_any, ...AppConstants.countryList];
  List<String> get _incomeOpts => [_any, ...AppConstants.incomeList];
  List<String> get _maritalOpts => [_any, ...AppConstants.maritalStatusList];
  List<String> get _rasiOpts => [_any, ...AppConstants.rasiEnList];
  List<String> get _nakshatraOpts => [_any, ...AppConstants.nakshatraList];
  List<String> get _languageOpts => [_any, ...AppConstants.motherTongueList];
  List<String> get _religionOpts => [_any, ...AppConstants.religionList];

  @override
  void dispose() {
    _cityCtrl.dispose();
    super.dispose();
  }

  void _populate(PartnerPreferences p) {
    var lo = p.minAge.clamp(18, 60).toDouble();
    var hi = p.maxAge.clamp(18, 60).toDouble();
    if (lo > hi) {
      final t = lo;
      lo = hi;
      hi = t;
    }
    _age = RangeValues(lo, hi);
    _minHeight =
        AppConstants.heightList.contains(p.minHeight) ? p.minHeight : "5'0\"";
    _maxHeight =
        AppConstants.heightList.contains(p.maxHeight) ? p.maxHeight : "5'10\"";
    _cityCtrl.text = p.city ?? '';
    _state = _safe(p.state, _stateOpts);
    _country = _safe(p.country, _countryOpts);
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
    _religion = _safe(p.religion, _religionOpts);
  }

  String _safe(String? value, List<String> opts) =>
      (value != null && value.isNotEmpty && opts.contains(value)) ? value : _any;

  PartnerPreferences _buildPrefs() => PartnerPreferences(
        minAge: _age.start.round(),
        maxAge: _age.end.round(),
        minHeight: _minHeight,
        maxHeight: _maxHeight,
        education: _education.toList(),
        occupation: _occupation.toList(),
        income: _income,
        religion: _religion,
        city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        state: _state == _any ? null : _state,
        country: _country == _any ? null : _country,
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
    // Prefill once from the saved profile preferences.
    profileAsync.whenData((p) {
      if (!_loaded && p != null) {
        _populate(p.partnerPreferences);
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _card(
            icon: Icons.cake_outlined,
            title: 'Age Range',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_age.start.round()} - ${_age.end.round()} years',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                RangeSlider(
                  values: _age,
                  min: 18,
                  max: 60,
                  divisions: 42,
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.primary.withOpacity(0.15),
                  labels: RangeLabels(
                      '${_age.start.round()}', '${_age.end.round()}'),
                  onChanged: (v) => setState(() => _age = v),
                ),
              ],
            ),
          ),
          _card(
            icon: Icons.height,
            title: 'Height Preference',
            child: Row(
              children: [
                Expanded(
                    child: _dropdown('Min', _minHeight, AppConstants.heightList,
                        (v) => setState(() => _minHeight = v!))),
                const SizedBox(width: 12),
                Expanded(
                    child: _dropdown('Max', _maxHeight, AppConstants.heightList,
                        (v) => setState(() => _maxHeight = v!))),
              ],
            ),
          ),
          _card(
            icon: Icons.location_on_outlined,
            title: 'Location Preference',
            child: Column(
              children: [
                TextField(
                  controller: _cityCtrl,
                  decoration: _inputDecoration('City'),
                ),
                const SizedBox(height: 12),
                _dropdown('State', _state, _stateOpts,
                    (v) => setState(() => _state = v!)),
                const SizedBox(height: 12),
                _dropdown('Country', _country, _countryOpts,
                    (v) => setState(() => _country = v!)),
              ],
            ),
          ),
          _card(
            icon: Icons.school_outlined,
            title: 'Education Preference',
            subtitle: 'Select preferred qualifications',
            child: _chips(AppConstants.educationList, _education),
          ),
          _card(
            icon: Icons.work_outline,
            title: 'Profession Preference',
            subtitle: 'Select preferred professions',
            child: _chips(AppConstants.occupationList, _occupation),
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
            child: _dropdown('Religion', _religion, _religionOpts,
                (v) => setState(() => _religion = v!)),
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
        ],
      ),
    );
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

  Widget _chips(List<String> options, Set<String> selected) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: options.map((o) {
        final on = selected.contains(o);
        return FilterChip(
          label: Text(o),
          selected: on,
          showCheckmark: true,
          checkmarkColor: AppColors.primary,
          selectedColor: AppColors.primary.withOpacity(0.12),
          backgroundColor: Colors.grey[100],
          side: BorderSide(
              color: on ? AppColors.primary : Colors.grey[300]!),
          labelStyle: TextStyle(
            fontSize: 12.5,
            color: on ? AppColors.primary : Colors.black87,
            fontWeight: on ? FontWeight.w600 : FontWeight.normal,
          ),
          onSelected: (v) => setState(() {
            if (v) {
              selected.add(o);
            } else {
              selected.remove(o);
            }
          }),
        );
      }).toList(),
    );
  }
}
