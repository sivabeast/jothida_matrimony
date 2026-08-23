import 'package:flutter/material.dart';

import '../../core/data/master_option.dart';
import '../../core/data/occupation_catalog.dart';
import '../../core/utils/l10n_ext.dart';
import 'searchable_with_add_field.dart';

/// **Profession Type** ("பணி வகை") — the admin-curated sector list, plus the
/// ability to add one that is missing (spec §6).
///
/// The catalogue is kept because it is genuinely useful (and carries Tamil
/// names + search aliases), but it is no longer a closed list and there is
/// deliberately NO "Others" entry: someone whose sector is "Coconut Farming"
/// types it and taps `+`, and that becomes their stored value.
///
/// A custom type is stored on the member's own profile only — nothing is
/// written back to the shared catalogue.
class ProfessionTypeField extends StatelessWidget {
  final String label;
  final String? status;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? errorText;
  final bool isRequired;

  const ProfessionTypeField({
    super.key,
    required this.label,
    required this.status,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.isRequired = true,
  });

  @override
  Widget build(BuildContext context) {
    final options = OccupationCatalog.typesFor(status);
    return SearchableWithAddField(
      label: label,
      isRequired: isRequired,
      prefixIcon: Icons.account_balance_outlined,
      options: options,
      items: options.values,
      value: value,
      errorText: errorText,
      onChanged: onChanged,
    );
  }
}

/// **Occupation / Profession** — searchable catalogue OR whatever the member
/// actually does (spec §5).
///
/// Nobody is forced to pick from a predefined list: a farmer, tailor, driver,
/// electrician or mechanic types their real occupation and adds it with `+`.
/// The typed value is stored, displayed and edited exactly like a catalogue
/// one, so it survives profile view/edit and comes back through the APIs
/// unchanged.
class OccupationField extends StatelessWidget {
  final String label;

  /// Catalogue rows to offer, already ordered for this member.
  final List<MasterOption> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final String? errorText;
  final bool isRequired;

  const OccupationField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.errorText,
    this.isRequired = true,
  });

  @override
  Widget build(BuildContext context) => SearchableWithAddField(
        label: label,
        isRequired: isRequired,
        enabled: enabled,
        prefixIcon: Icons.work_outline,
        options: options,
        items: options.values,
        value: value,
        errorText: errorText,
        helperText: context.l10n.occupationFreeTextHelper,
        onChanged: onChanged,
      );
}
