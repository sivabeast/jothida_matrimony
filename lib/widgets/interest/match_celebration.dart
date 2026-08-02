import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';

/// Full-screen premium celebration played the moment an interest is ACCEPTED —
/// floating hearts, a scale-in badge and a clear "you are now connected"
/// message, with an optional one-tap jump into the new conversation.
///
/// Usage: `await showMatchCelebration(context, name: profile.fullName,
/// onStartChat: ...)`. Returns after the dialog closes; never throws.
Future<void> showMatchCelebration(
  BuildContext context, {
  required String name,
  String photoUrl = '',
  VoidCallback? onStartChat,
}) async {
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'match',
      barrierColor: Colors.black.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 380),
      transitionBuilder: (context, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: curved, child: child),
        );
      },
      pageBuilder: (context, _, __) => _MatchCelebrationDialog(
        name: name,
        photoUrl: photoUrl,
        onStartChat: onStartChat,
      ),
    );
  } catch (_) {/* a celebration hiccup must never break the accept flow */}
}

class _MatchCelebrationDialog extends StatefulWidget {
  final String name;
  final String photoUrl;
  final VoidCallback? onStartChat;

  const _MatchCelebrationDialog({
    required this.name,
    required this.photoUrl,
    this.onStartChat,
  });

  @override
  State<_MatchCelebrationDialog> createState() =>
      _MatchCelebrationDialogState();
}

class _MatchCelebrationDialogState extends State<_MatchCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hearts;

  @override
  void initState() {
    super.initState();
    _hearts = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600))
      ..repeat();
  }

  @override
  void dispose() {
    _hearts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = widget.name.trim();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Floating hearts behind the card.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _hearts,
                builder: (context, _) =>
                    CustomPaint(painter: _FloatingHeartsPainter(_hearts.value)),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkSurface
                  : Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.55), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.25),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            // Scrollable so landscape / large accessibility fonts can never
            // overflow the fixed-height dialog viewport.
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Heart badge (photo when available) with a soft double ring.
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.goldGradient,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Colors.white),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.08),
                      backgroundImage: widget.photoUrl.isNotEmpty
                          ? NetworkImage(widget.photoUrl)
                          : null,
                      child: widget.photoUrl.isEmpty
                          ? const Icon(Icons.favorite,
                              color: AppColors.primary, size: 40)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ShaderMask(
                  shaderCallback: (r) =>
                      AppColors.goldGradient.createShader(r),
                  child: Text(
                    l10n.matchCelebrationTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  name.isEmpty
                      ? l10n.interestAcceptedMatch
                      : l10n.matchCelebrationBody(name),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 22),
                if (widget.onStartChat != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onStartChat!.call();
                        },
                        icon: const Icon(Icons.chat_bubble_outline, size: 20),
                        label: Text(
                          l10n.startChatting,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary),
                  child: Text(l10n.keepBrowsing),
                ),
              ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight looping hearts — drawn with a painter (no per-heart widgets, no
/// external animation package). Each heart rises on its own phase/track and
/// fades out near the top.
class _FloatingHeartsPainter extends CustomPainter {
  final double t;
  _FloatingHeartsPainter(this.t);

  static const int _count = 9;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var i = 0; i < _count; i++) {
      // Deterministic pseudo-random per-heart constants.
      final seed = i * 137.508; // golden-angle spread
      final x0 = (math.sin(seed) * 0.5 + 0.5) * size.width;
      final phase = (t + i / _count) % 1.0;
      final y = size.height * (1.05 - 1.25 * phase);
      final sway = math.sin(phase * math.pi * 3 + seed) * 14;
      final scale = 8.0 + (i % 3) * 4.0;
      final opacity = phase < 0.15
          ? phase / 0.15
          : (phase > 0.75 ? math.max(0.0, (1.0 - phase) / 0.25) : 1.0);
      paint.color = (i.isEven ? AppColors.primaryLight : AppColors.gold)
          .withValues(alpha: 0.55 * opacity);
      _drawHeart(canvas, Offset(x0 + sway, y), scale, paint);
    }
  }

  void _drawHeart(Canvas canvas, Offset c, double s, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy + s * 0.35)
      ..cubicTo(c.dx + s, c.dy - s * 0.45, c.dx + s * 0.45, c.dy - s * 1.1,
          c.dx, c.dy - s * 0.4)
      ..cubicTo(c.dx - s * 0.45, c.dy - s * 1.1, c.dx - s, c.dy - s * 0.45,
          c.dx, c.dy + s * 0.35)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FloatingHeartsPainter old) => old.t != t;
}
