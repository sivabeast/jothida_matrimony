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
import 'family_tree_screen.dart' show FamilyTreeView;

/// Family Details — a dedicated page (PROFILE group) for the signed-in user's
/// family information: father, mother, siblings, family type and status. The
/// data is rendered with the shared [FamilyTreeView]; the AppBar "Edit" action
/// opens a bottom sheet that performs a partial Firestore update of `family`.
class FamilyDetailsScreen extends ConsumerWidget {
  const FamilyDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Family Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (profileAsync.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Family Details',
              onPressed: () =>
                  _openEditSheet(context, profileAsync.valueOrNull!),
            ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => _Empty(
          icon: Icons.error_outline,
          title: 'Could not load family details',
          subtitle: '$e',
        ),
        data: (profile) {
          if (profile == null) {
            return _Empty(
              icon: Icons.person_off_outlined,
              title: 'No profile yet',
              subtitle: 'Create your profile to add family details.',
              actionLabel: 'Create Profile',
              onAction: () => context.push('/profile/create'),
            );
          }
          final family = profile.family;
          if (_isFamilyEmpty(family)) {
            return _Empty(
              icon: Icons.family_restroom_outlined,
              title: 'Family details not added',
              subtitle: 'Tap Edit to add your father, mother, siblings and '
                  'family background.',
              actionLabel: 'Add Family Details',
              onAction: () => _openEditSheet(context, profile),
            );
          }
          return FamilyTreeView(family: family, personName: profile.name);
        },
      ),
    );
  }

  static bool _isFamilyEmpty(FamilyDetails f) =>
      f.fatherName.trim().isEmpty &&
      f.motherName.trim().isEmpty &&
      f.fatherOccupation.trim().isEmpty &&
      f.motherOccupation.trim().isEmpty &&
      f.brothersCount == 0 &&
      f.sistersCount == 0 &&
      f.familyType.trim().isEmpty &&
      f.familyStatus.trim().isEmpty;

  void _openEditSheet(BuildContext context, ProfileModel profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FamilyEditSheet(profile: profile),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit sheet
// ─────────────────────────────────────────────────────────────────────────────

class _FamilyEditSheet extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _FamilyEditSheet({required this.profile});

  @override
  ConsumerState<_FamilyEditSheet> createState() => _FamilyEditSheetState();
}

class _FamilyEditSheetState extends ConsumerState<_FamilyEditSheet> {
  late final FamilyDetails _f = widget.profile.family;
  late final TextEditingController _fatherName =
      TextEditingController(text: _f.fatherName);
  late final TextEditingController _fatherOcc =
      TextEditingController(text: _f.fatherOccupation);
  late final TextEditingController _motherName =
      TextEditingController(text: _f.motherName);
  late final TextEditingController _motherOcc =
      TextEditingController(text: _f.motherOccupation);
  late final TextEditingController _brothers =
      TextEditingController(text: _f.brothersCount.toString());
  late final TextEditingController _sisters =
      TextEditingController(text: _f.sistersCount.toString());
  late String _familyType = _f.familyType;
  late String _familyStatus = _f.familyStatus;
  bool _saving = false;

  @override
  void dispose() {
    _fatherName.dispose();
    _fatherOcc.dispose();
    _motherName.dispose();
    _motherOcc.dispose();
    _brothers.dispose();
    _sisters.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final family = FamilyDetails(
      fatherName: _fatherName.text.trim(),
      fatherOccupation: _fatherOcc.text.trim(),
      motherName: _motherName.text.trim(),
      motherOccupation: _motherOcc.text.trim(),
      brothersCount: int.tryParse(_brothers.text.trim()) ?? 0,
      sistersCount: int.tryParse(_sisters.text.trim()) ?? 0,
      familyType: _familyType,
      familyStatus: _familyStatus,
    );
    final updated = widget.profile.copyWith(family: family);
    try {
      if (kBypassAuth) {
        ref.read(demoProfilesProvider.notifier).upsert(updated);
      } else {
        await ref
            .read(profileRepositoryProvider)
            .updateProfile(widget.profile.id, {'family': family.toMap()});
        ref.invalidate(myProfileProvider);
      }
      navigator.pop();
      messenger.showSnackBar(
          const SnackBar(content: Text('Family details updated')));
    } catch (e) {
      debugPrint('[FamilyDetails] save error: $e');
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
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
            const Text('Edit Family Details',
                style: TextStyle(
                    fontSize: 18,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _tf(_fatherName, "Father's Name"),
            _tf(_fatherOcc, "Father's Occupation"),
            _tf(_motherName, "Mother's Name"),
            _tf(_motherOcc, "Mother's Occupation"),
            Row(
              children: [
                Expanded(
                    child: _tf(_brothers, 'Brothers',
                        keyboard: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(
                    child: _tf(_sisters, 'Sisters',
                        keyboard: TextInputType.number)),
              ],
            ),
            _drop('Family Type', _familyType,
                _optsWith(AppConstants.familyTypeList, _familyType),
                (v) => setState(() => _familyType = v!)),
            _drop('Family Status', _familyStatus,
                _optsWith(AppConstants.familyStatusList, _familyStatus),
                (v) => setState(() => _familyStatus = v!)),
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
      ),
    );
  }

  // ── Small field helpers (self-contained) ─────────────────────────────────
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

  Widget _tf(TextEditingController c, String label, {TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
            controller: c, keyboardType: keyboard, decoration: _dec(label)),
      );

  Widget _drop(String label, String value, List<String> opts,
      ValueChanged<String?> onChanged) {
    final safe =
        opts.contains(value) ? value : (opts.isNotEmpty ? opts.first : value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: safe,
        isExpanded: true,
        decoration: _dec(label),
        items: opts
            .map((o) => DropdownMenuItem(
                value: o, child: Text(o, overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  List<String> _optsWith(List<String> base, String? current) {
    if (current == null || current.isEmpty || base.contains(current)) {
      return base;
    }
    return [current, ...base];
  }
}

// ── Empty / error state ───────────────────────────────────────────────────────
class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Empty({
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
            Icon(icon, size: 64, color: AppColors.primary.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 13.5)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
