import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// User-facing availability pill: 🟢 "Available Today" / 🔴 "Not Available
/// Today". Use [compact] on dense cards (shorter label, smaller padding).
class AvailabilityBadge extends StatelessWidget {
  final bool available;
  final bool compact;

  const AvailabilityBadge({
    super.key,
    required this.available,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = available ? AppColors.success : Colors.grey.shade600;
    final label = available
        ? (compact ? 'Available' : 'Available Today')
        : (compact ? 'Unavailable' : 'Not Available Today');
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 4),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 7 : 8,
            height: compact ? 7 : 8,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
          ),
          SizedBox(width: compact ? 4 : 5),
          Text(label,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 9.5 : 11,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
