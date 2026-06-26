import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/working_hours.dart';

/// Live "Time Remaining" pill for a pending match-analysis booking (spec §7).
///
/// Shows the WORKING hours left to accept (the 00:00–07:00 band is excluded, so
/// the timer visibly pauses overnight), recolouring as the deadline nears:
///   • green  — normal      ( > 6h left )
///   • orange — medium       ( 3–6h left )
///   • red    — critical     ( < 3h left )
/// Once the deadline lapses it reads "Acceptance Expired".
class BookingCountdown extends StatefulWidget {
  /// The booking's hard acceptance deadline (already a working-hours instant).
  final DateTime? expiresAt;

  /// When true, renders just the coloured text (no pill background) for tight
  /// rows.
  final bool compact;

  const BookingCountdown({super.key, required this.expiresAt, this.compact = false});

  @override
  State<BookingCountdown> createState() => _BookingCountdownState();
}

class _BookingCountdownState extends State<BookingCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Re-evaluate every 30s — minutes resolution updates smoothly without
    // burning a per-second rebuild.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expiresAt = widget.expiresAt;
    if (expiresAt == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final expired = !expiresAt.isAfter(now);
    final remaining = expired
        ? Duration.zero
        : workingTimeBetween(now, expiresAt);

    final Color color;
    final IconData icon;
    final String label;
    if (expired || remaining <= Duration.zero) {
      color = AppColors.error;
      icon = Icons.timer_off_outlined;
      label = 'Acceptance Expired';
    } else {
      if (remaining.inMinutes > 6 * 60) {
        color = AppColors.success;
      } else if (remaining.inMinutes > 3 * 60) {
        color = AppColors.warning;
      } else {
        color = AppColors.error;
      }
      icon = Icons.timer_outlined;
      label = '${formatWorkingRemaining(remaining)} remaining';
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11.5, color: color, fontWeight: FontWeight.w700)),
      ],
    );

    if (widget.compact) return content;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: content,
    );
  }
}
