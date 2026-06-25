import 'package:flutter/material.dart';
import '../../core/services/match_score_service.dart';

/// A compact match-quality pill ("Excellent Match" / "Good Match" /
/// "Average Match"), coloured by the score tier. NO percentage is shown.
///
/// Pass a [MatchScore] (from [MatchScoreService.compute]). Renders nothing when
/// [score] is null (e.g. the signed-in user's own profile hasn't loaded yet),
/// so callers can drop it straight into a Stack/Row without null guards.
class MatchScoreBadge extends StatelessWidget {
  final MatchScore? score;
  final bool compact;

  const MatchScoreBadge({super.key, required this.score, this.compact = false});

  static const _excellent = Color(0xFF1B8A4B); // green
  static const _veryGood = Color(0xFF2E7D32); // deep green
  static const _good = Color(0xFF7CB342); // light green
  static const _average = Color(0xFFB8860B); // dark gold
  static const _low = Color(0xFF8A8A8A); // grey

  Color get _color {
    switch (score?.tier) {
      case 'excellent':
        return _excellent;
      case 'veryGood':
        return _veryGood;
      case 'good':
        return _good;
      case 'average':
        return _average;
      default:
        return _low;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = score;
    if (s == null) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_color, _color.withValues(alpha: 0.82)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: _color.withValues(alpha: 0.35), blurRadius: 5),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite,
              size: compact ? 11 : 13, color: Colors.white),
          SizedBox(width: compact ? 3 : 5),
          Text(
            compact ? s.shortQuality : s.quality,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 10 : 12.5,
              fontWeight: FontWeight.w700,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }
}
