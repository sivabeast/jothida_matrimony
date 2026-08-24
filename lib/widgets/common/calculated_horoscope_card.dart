import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import 'searchable_field.dart';

/// The **Calculated Horoscope** card — Rasi, Nakshatra and Lagnam, each one
/// directly editable inside the card itself (§12).
///
/// Automatic calculation stays the default: the three values are filled in
/// from Date of Birth + Time of Birth + Place of Birth by the Vedic engine.
/// The member can then change any of them right here, in place. There is no
/// "Override automatically calculated horoscope" switch and no separate edit
/// mode or override screen — the toggle was removed (§11); tapping a value IS
/// the edit.
///
/// Pass [onRasiChanged] / [onNakshatraChanged] / [onLagnamChanged] together
/// with the matching option lists to make the card editable. With none of them
/// the card renders read-only, which is what the overflow regression test
/// (`test/horoscope_layout_test.dart`) pumps.
///
/// The three lists come from the fixed Vedic master data and deliberately have
/// NO "Others" entry: a free-text value would break porutham (star
/// compatibility) matching.
class CalculatedHoroscopeCard extends StatelessWidget {
  final String rasi;
  final String nakshatra;
  final String lagnam;

  final List<String> rasiOptions;
  final List<String> nakshatraOptions;
  final List<String> lagnamOptions;

  final ValueChanged<String?>? onRasiChanged;
  final ValueChanged<String?>? onNakshatraChanged;
  final ValueChanged<String?>? onLagnamChanged;

  const CalculatedHoroscopeCard({
    super.key,
    required this.rasi,
    required this.nakshatra,
    required this.lagnam,
    this.rasiOptions = const [],
    this.nakshatraOptions = const [],
    this.lagnamOptions = const [],
    this.onRasiChanged,
    this.onNakshatraChanged,
    this.onLagnamChanged,
  });

  bool get _editable =>
      onRasiChanged != null ||
      onNakshatraChanged != null ||
      onLagnamChanged != null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Every child is either fixed-width or bounded, so this header can
          // never overflow — the title wraps to a second line on narrow phones
          // instead (unbounded Texts around a Spacer used to overflow by a few
          // pixels once the labels were translated).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child:
                    Icon(Icons.auto_awesome, size: 18, color: Colors.amber),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.calculatedHoroscope,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (_editable) ...[
                      const SizedBox(height: 2),
                      Text(l10n.editHoroscopeValueHint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.grey[700])),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          _field(
            context,
            label: l10n.rasiMoonSign,
            value: rasi,
            icon: Icons.brightness_3_outlined,
            items: rasiOptions,
            onChanged: onRasiChanged,
          ),
          const SizedBox(height: 12),
          _field(
            context,
            label: l10n.nakshatraStar,
            value: nakshatra,
            icon: Icons.star_outline,
            items: nakshatraOptions,
            onChanged: onNakshatraChanged,
          ),
          const SizedBox(height: 12),
          _field(
            context,
            label: l10n.lagnamAscendant,
            value: lagnam,
            icon: Icons.wb_twilight_outlined,
            items: lagnamOptions,
            onChanged: onLagnamChanged,
          ),
        ],
      ),
    );
  }

  /// One horoscope value. Editable → the app's standard searchable picker,
  /// opened as a modal bottom sheet so the list never covers the card.
  /// Read-only → a plain label/value row.
  Widget _field(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required List<String> items,
    required ValueChanged<String?>? onChanged,
  }) {
    if (onChanged == null || items.isEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(label,
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ),
          Expanded(
            flex: 6,
            child: Text(value.isEmpty ? '—' : value,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      );
    }
    return SearchableField(
      label: label,
      isRequired: true,
      items: items,
      selectedItem: value.isEmpty ? null : value,
      prefixIcon: icon,
      // Modal sheet, not an anchored menu: the list must never be drawn over
      // the other two values in this card.
      popupMode: SearchablePopupMode.modalBottomSheet,
      onChanged: onChanged,
    );
  }
}

/// Themed error box for horoscope generation failures. Shared by the wizard
/// step and the standalone Horoscope Details screen so a failure reads the
/// same in both.
class HoroscopeErrorBox extends StatelessWidget {
  final String message;
  const HoroscopeErrorBox({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(color: Colors.red[700], fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
