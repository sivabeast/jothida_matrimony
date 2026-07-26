import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_edit_provider.dart';
import '../../providers/profile_provider.dart';

/// The kind of input a single profile field needs.
enum ProfileFieldKind { text, number, options, date }

/// One editable profile field for the field-level editor.
///
/// [apply] returns a copy of the profile with just this field changed and
/// [patch] the matching Firestore field subset — so saving updates ONLY this
/// field and leaves everything else untouched.
class ProfileEditableField {
  final String label;
  final ProfileFieldKind kind;

  /// Current display value (also pre-fills the editor).
  final String value;

  /// Options for [ProfileFieldKind.options].
  final List<String> options;

  /// For [ProfileFieldKind.date] — the current date (e.g. date of birth).
  final DateTime? dateValue;

  /// Builds the updated model for the new value (String, or DateTime for dates).
  final ProfileModel Function(ProfileModel profile, Object newValue) apply;

  /// Builds the Firestore patch (only this field's keys) for the new value.
  final Map<String, dynamic> Function(Object newValue) patch;

  const ProfileEditableField({
    required this.label,
    required this.kind,
    required this.value,
    required this.apply,
    required this.patch,
    this.options = const [],
    this.dateValue,
  });
}

/// Opens a premium bottom sheet listing a section's fields. Tapping a field
/// opens an editor for ONLY that field; saving patches just that field and the
/// My Profile page refreshes instantly (via the live `myProfileProvider`).
Future<void> showProfileFieldSheet(
  BuildContext context, {
  required String sectionTitle,
  required List<ProfileEditableField> Function(ProfileModel profile)
      fieldsBuilder,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) =>
        _FieldListSheet(sectionTitle: sectionTitle, fieldsBuilder: fieldsBuilder),
  );
}

class _FieldListSheet extends ConsumerWidget {
  final String sectionTitle;
  final List<ProfileEditableField> Function(ProfileModel) fieldsBuilder;
  const _FieldListSheet(
      {required this.sectionTitle, required this.fieldsBuilder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching the live profile means every saved field is reflected here
    // immediately without closing the sheet.
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final fields = profile == null ? <ProfileEditableField>[] : fieldsBuilder(profile);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(sectionTitle,
                        style: const TextStyle(
                            fontSize: 17,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 22),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text('Tap a field to edit only that field.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                itemCount: fields.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (_, i) {
                  final f = fields[i];
                  return ListTile(
                    title: Text(f.label,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black54)),
                    subtitle: Text(
                      f.value.trim().isEmpty ? 'Not added' : f.value,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: f.value.trim().isEmpty
                            ? Colors.grey
                            : Colors.black87,
                      ),
                    ),
                    trailing: const Icon(Icons.edit_outlined,
                        size: 19, color: AppColors.primary),
                    onTap: () => _editField(context, ref, profile!, f),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editField(BuildContext context, WidgetRef ref,
      ProfileModel profile, ProfileEditableField f) async {
    Object? newValue;
    switch (f.kind) {
      case ProfileFieldKind.text:
      case ProfileFieldKind.number:
        newValue = await _promptText(context, f);
        break;
      case ProfileFieldKind.options:
        newValue = await _promptOption(context, f);
        break;
      case ProfileFieldKind.date:
        newValue = await _promptDate(context, f);
        break;
    }
    if (newValue == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(profileEditControllerProvider.notifier).save(
            updated: f.apply(profile, newValue),
            patch: f.patch(newValue),
          );
      messenger.showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')));
    }
  }

  /// Text / number single-field editor.
  Future<String?> _promptText(
      BuildContext context, ProfileEditableField f) async {
    final ctrl = TextEditingController(text: f.value);
    final isNumber = f.kind == ProfileFieldKind.number;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit ${f.label}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          inputFormatters:
              isNumber ? [FilteringTextInputFormatter.digitsOnly] : null,
          decoration: InputDecoration(
            labelText: f.label,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Unchanged → no save.
    if (result == null || result == f.value.trim()) return null;
    return result;
  }

  /// Options single-field editor — a searchable list; tapping an option saves.
  Future<String?> _promptOption(
      BuildContext context, ProfileEditableField f) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _OptionPicker(field: f),
    );
  }

  /// Date single-field editor (e.g. Date of Birth).
  Future<DateTime?> _promptDate(
      BuildContext context, ProfileEditableField f) {
    final now = DateTime.now();
    final initial = f.dateValue ?? DateTime(now.year - 25, 1, 1);
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: 'Select ${f.label}',
    );
  }
}

/// Searchable option picker used by the field editor.
class _OptionPicker extends StatefulWidget {
  final ProfileEditableField field;
  const _OptionPicker({required this.field});

  @override
  State<_OptionPicker> createState() => _OptionPickerState();
}

class _OptionPickerState extends State<_OptionPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = widget.field.options;
    final filtered = _query.trim().isEmpty
        ? all
        : all
            .where((o) => o.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Text('Select ${widget.field.label}',
                  style: const TextStyle(
                      fontSize: 16,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700)),
            ),
            if (all.length > 6)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final o = filtered[i];
                  final selected = o == widget.field.value;
                  return ListTile(
                    title: Text(o),
                    trailing: selected
                        ? const Icon(Icons.check_circle,
                            color: AppColors.primary, size: 20)
                        : null,
                    onTap: () => Navigator.pop(context, o),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
