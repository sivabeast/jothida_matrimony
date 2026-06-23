import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';

/// A traditional **South-Indian Rasi chart** (4×4 grid, signs in fixed cells)
/// that marks the **Lagnam** (ascendant) and **Moon / Rasi** placements derived
/// from the stored horoscope. The app's engine computes Rasi, Nakshatra and
/// Lagnam (not a full planetary ephemeris), so the chart shows those two
/// placements — enough for the astrologer to orient and compare two charts.
///
/// Sign cells are fixed in the South-Indian style:
/// ```
///  Meenam  | Mesham | Rishabam | Mithunam
///  Kumbam  |        |          | Kadagam
///  Magaram |        |          | Simmam
///  Dhanusu | Viruch.| Thulam   | Kanni
/// ```
class RasiChart extends StatelessWidget {
  /// Sign name as stored on the horoscope (Tamil or English; either is matched).
  final String rasi; // Moon sign
  final String lagnam; // Ascendant
  final String title;

  const RasiChart({
    super.key,
    required this.rasi,
    required this.lagnam,
    this.title = 'Rasi Chart',
  });

  // (row, col) for each sign index (0 = Mesham … 11 = Meenam).
  static const Map<int, List<int>> _cell = {
    11: [0, 0], 0: [0, 1], 1: [0, 2], 2: [0, 3],
    3: [1, 3], 4: [2, 3], 5: [3, 3],
    6: [3, 2], 7: [3, 1], 8: [3, 0],
    9: [2, 0], 10: [1, 0],
  };

  /// Resolves a stored sign string to an index 0–11, matching against the Tamil
  /// and English master lists (exact, then contains). Returns -1 if unknown.
  static int resolveIndex(String raw) {
    final n = raw.trim().toLowerCase();
    if (n.isEmpty) return -1;
    for (var i = 0; i < AppConstants.rasiList.length; i++) {
      if (AppConstants.rasiList[i].toLowerCase() == n) return i;
    }
    for (var i = 0; i < AppConstants.rasiEnList.length; i++) {
      final en = AppConstants.rasiEnList[i].toLowerCase();
      if (en == n || en.contains(n) || n.contains(en.split(' ').first)) {
        return i;
      }
    }
    // Partial match against the Tamil list.
    for (var i = 0; i < AppConstants.rasiList.length; i++) {
      final ta = AppConstants.rasiList[i].toLowerCase();
      if (ta.contains(n) || n.contains(ta)) return i;
    }
    return -1;
  }

  int? _signAt(int row, int col) {
    for (final e in _cell.entries) {
      if (e.value[0] == row && e.value[1] == col) return e.key;
    }
    return null; // a center cell
  }

  @override
  Widget build(BuildContext context) {
    final moonIdx = resolveIndex(rasi);
    final lagnaIdx = resolveIndex(lagnam);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary)),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.6)),
              color: Colors.white,
            ),
            child: Stack(
              children: [
                Column(
                  children: List.generate(4, (row) {
                    return Expanded(
                      child: Row(
                        children: List.generate(4, (col) {
                          final sign = _signAt(row, col);
                          if (sign == null) {
                            return const Expanded(child: SizedBox.shrink());
                          }
                          return Expanded(
                            child: _cellWidget(
                              signIndex: sign,
                              isLagna: sign == lagnaIdx,
                              isMoon: sign == moonIdx,
                            ),
                          );
                        }),
                      ),
                    );
                  }),
                ),
                // Center 2×2 title block.
                const Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.5,
                    heightFactor: 0.5,
                    child: Center(
                      child: Icon(Icons.auto_awesome,
                          color: AppColors.primary, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _legend('La', 'Lagnam', AppColors.primary),
            const SizedBox(width: 12),
            _legend('Ch', 'Moon (Rasi)', AppColors.gold),
          ],
        ),
      ],
    );
  }

  Widget _cellWidget({
    required int signIndex,
    required bool isLagna,
    required bool isMoon,
  }) {
    final name = AppConstants.rasiList[signIndex];
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.4)),
        color: isLagna
            ? AppColors.primary.withValues(alpha: 0.10)
            : isMoon
                ? AppColors.gold.withValues(alpha: 0.14)
                : Colors.transparent,
      ),
      padding: const EdgeInsets.all(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 8.5, color: Colors.black54)),
          const Spacer(),
          Row(
            children: [
              if (isLagna) _marker('La', AppColors.primary),
              if (isMoon) _marker('Ch', AppColors.gold),
            ],
          ),
        ],
      ),
    );
  }

  Widget _marker(String text, Color color) => Container(
        margin: const EdgeInsets.only(right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 8.5,
                fontWeight: FontWeight.bold)),
      );

  Widget _legend(String code, String label, Color color) => Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(4)),
            child: Text(code,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.black54)),
        ],
      );
}
