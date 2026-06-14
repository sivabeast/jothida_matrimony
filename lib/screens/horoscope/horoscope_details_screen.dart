import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/config/dev_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/demo_data_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';

/// Horoscope Details — a profile-management screen for the user's horoscope.
///
/// Every field has its own ✏️ that opens a small bottom-sheet editor pre-filled
/// with the current value. Saving performs a **partial** Firestore update (only
/// that field, via a `horoscope.<field>` dotted path) and refreshes here.
/// Editing never re-opens the onboarding/profile-creation wizard.
class HoroscopeDetailsScreen extends ConsumerWidget {
  const HoroscopeDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[HoroscopeDetailsScreen] build — route /horoscope');
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Horoscope Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: profileAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => _Message(
          icon: Icons.error_outline,
          title: 'Could not load horoscope',
          subtitle: '$e',
        ),
        data: (profile) {
          if (profile == null) {
            return _Message(
              icon: Icons.auto_awesome_outlined,
              title: 'No horoscope yet',
              subtitle:
                  'Complete your profile to generate your horoscope details.',
              actionLabel: 'Create Profile',
              onAction: () => context.push('/profile/create'),
            );
          }
          final h = profile.horoscope;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeaderCard(profile: profile),
              const SizedBox(height: 16),
              _Section(title: 'Birth Details', children: [
                _EditRow(
                  label: 'Date of Birth',
                  value: _fmtDate(profile.dateOfBirth),
                  onEdit: () => _editDob(context, ref, profile),
                ),
                _EditRow(
                  label: 'Birth Time',
                  value: h.birthTime,
                  onEdit: () => _openField(context, 'Edit Birth Time', h.birthTime,
                      null, (r, v) => _saveField(r, profile, 'birthTime', v,
                          h.copyWith(birthTime: v))),
                ),
                _EditRow(
                  label: 'Birth Place',
                  value: h.birthPlace,
                  onEdit: () => _openField(context, 'Edit Birth Place',
                      h.birthPlace, null, (r, v) => _saveField(
                          r, profile, 'birthPlace', v, h.copyWith(birthPlace: v))),
                ),
              ]),
              const SizedBox(height: 12),
              _Section(title: 'Horoscope', children: [
                _EditRow(
                  label: 'Rasi (Moon Sign)',
                  value: h.rasi,
                  onEdit: () => _openField(context, 'Edit Rasi', h.rasi,
                      _opts(AppConstants.rasiEnList, h.rasi),
                      (r, v) => _saveField(r, profile, 'rasi', v, h.copyWith(rasi: v))),
                ),
                _EditRow(
                  label: 'Nakshatra (Star)',
                  value: h.nakshatra,
                  onEdit: () => _openField(context, 'Edit Nakshatra', h.nakshatra,
                      _opts(AppConstants.nakshatraList, h.nakshatra),
                      (r, v) => _saveField(
                          r, profile, 'nakshatra', v, h.copyWith(nakshatra: v))),
                ),
                _EditRow(
                  label: 'Lagnam (Ascendant)',
                  value: h.lagnam,
                  onEdit: () => _openField(context, 'Edit Lagnam', h.lagnam,
                      _opts(AppConstants.lagnamList, h.lagnam),
                      (r, v) => _saveField(
                          r, profile, 'lagnam', v, h.copyWith(lagnam: v))),
                ),
                _EditRow(
                  label: 'Dosham',
                  value: h.dosham,
                  onEdit: () => _openField(context, 'Edit Dosham', h.dosham,
                      null, (r, v) => _saveField(
                          r, profile, 'dosham', v, h.copyWith(dosham: v))),
                ),
                _EditRow(
                  label: 'Dasa Balance',
                  value: h.dasaBalance,
                  onEdit: () => _openField(context, 'Edit Dasa Balance',
                      h.dasaBalance, null, (r, v) => _saveField(
                          r, profile, 'dasaBalance', v, h.copyWith(dasaBalance: v))),
                ),
                _EditRow(
                  label: 'Yogam',
                  value: h.yogam,
                  onEdit: () => _openField(context, 'Edit Yogam', h.yogam, null,
                      (r, v) => _saveField(r, profile, 'yogam', v, h.copyWith(yogam: v))),
                ),
                _EditRow(
                  label: 'Karanam',
                  value: h.karanam,
                  onEdit: () => _openField(context, 'Edit Karanam', h.karanam, null,
                      (r, v) => _saveField(
                          r, profile, 'karanam', v, h.copyWith(karanam: v))),
                ),
                _EditRow(
                  label: 'Sun Sign',
                  value: h.sunSign,
                  onEdit: () => _openField(context, 'Edit Sun Sign', h.sunSign,
                      _opts(AppConstants.rasiEnList, h.sunSign),
                      (r, v) => _saveField(
                          r, profile, 'sunSign', v, h.copyWith(sunSign: v))),
                ),
                _EditRow(
                  label: 'Moon Sign',
                  value: h.moonSign,
                  onEdit: () => _openField(context, 'Edit Moon Sign', h.moonSign,
                      _opts(AppConstants.rasiEnList, h.moonSign),
                      (r, v) => _saveField(
                          r, profile, 'moonSign', v, h.copyWith(moonSign: v))),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  // ── Date of Birth (date picker, updates dateOfBirth + age) ──────────────────
  Future<void> _editDob(
      BuildContext context, WidgetRef ref, ProfileModel profile) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: profile.dateOfBirth,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final age = _ageFromDob(picked);
    try {
      if (kBypassAuth) {
        ref
            .read(demoProfilesProvider.notifier)
            .upsert(profile.copyWith(dateOfBirth: picked, age: age));
      } else {
        await ref.read(profileRepositoryProvider).updateProfile(profile.id, {
          'dateOfBirth': Timestamp.fromDate(picked),
          'age': age,
        });
        ref.invalidate(myProfileProvider);
      }
      messenger.showSnackBar(
          const SnackBar(content: Text('Date of birth updated')));
    } catch (e) {
      debugPrint('[Horoscope] dob save error: $e');
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')));
    }
  }
}

// ── Save helper: partial Firestore update of one horoscope field ──────────────

Future<void> _saveField(
  WidgetRef ref,
  ProfileModel profile,
  String key,
  String value,
  HoroscopeDetails updatedHoroscope,
) async {
  final horo = updatedHoroscope.copyWith(isUserEdited: true);
  if (kBypassAuth) {
    ref.read(demoProfilesProvider.notifier).upsert(profile.copyWith(horoscope: horo));
  } else {
    // Dotted field paths update ONLY these keys inside the horoscope map —
    // the rest of the document is preserved.
    await ref.read(profileRepositoryProvider).updateProfile(profile.id, {
      'horoscope.$key': value,
      'horoscope.isUserEdited': true,
    });
    ref.invalidate(myProfileProvider);
  }
}

void _openField(
  BuildContext context,
  String title,
  String initial,
  List<String>? options,
  Future<void> Function(WidgetRef ref, String value) onSave,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) =>
        _FieldEditSheet(title: title, initial: initial, options: options, onSave: onSave),
  );
}

List<String> _opts(List<String> base, String current) {
  if (current.isEmpty || base.contains(current)) return base;
  return [current, ...base];
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

int _ageFromDob(DateTime dob) {
  final now = DateTime.now();
  var age = now.year - dob.year;
  if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
    age--;
  }
  return age < 0 ? 0 : age;
}

// ── Field edit bottom sheet ───────────────────────────────────────────────────

class _FieldEditSheet extends ConsumerStatefulWidget {
  final String title;
  final String initial;
  final List<String>? options; // dropdown when non-null, else a text field
  final Future<void> Function(WidgetRef ref, String value) onSave;
  const _FieldEditSheet({
    required this.title,
    required this.initial,
    required this.options,
    required this.onSave,
  });

  @override
  ConsumerState<_FieldEditSheet> createState() => _FieldEditSheetState();
}

class _FieldEditSheetState extends ConsumerState<_FieldEditSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);
  late String _selected = widget.initial;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final value =
        widget.options != null ? _selected : _ctrl.text.trim();
    setState(() => _saving = true);
    try {
      await widget.onSave(ref, value);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      debugPrint('[Horoscope] field save error: $e');
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final opts = widget.options;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text(widget.title,
              style: const TextStyle(
                  fontSize: 18,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (opts != null)
            DropdownButtonFormField<String>(
              value: opts.contains(_selected) ? _selected : opts.first,
              isExpanded: true,
              decoration: _dec('Value'),
              items: opts
                  .map((o) => DropdownMenuItem(
                      value: o, child: Text(o, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() => _selected = v ?? _selected),
            )
          else
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: _dec('Value'),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: BorderSide(color: Colors.grey[400]!),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      );
}

// ── Presentation widgets ──────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final ProfileModel profile;
  const _HeaderCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final h = profile.horoscope;
    final rasi = h.rasi.trim().isEmpty ? '—' : h.rasi;
    final star = h.nakshatra.trim().isEmpty ? '—' : h.nakshatra;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(Icons.auto_awesome, color: AppColors.gold, size: 40),
          const SizedBox(height: 8),
          Text(profile.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('$rasi  •  $star',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(h.badgeText,
                style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
          ),
          const Divider(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _EditRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onEdit;
  const _EditRow(
      {required this.label, required this.value, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: Text(label,
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ),
          Expanded(
            flex: 6,
            child: Text(value.trim().isEmpty ? '—' : value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
            tooltip: 'Edit $label',
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.primary.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600])),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
