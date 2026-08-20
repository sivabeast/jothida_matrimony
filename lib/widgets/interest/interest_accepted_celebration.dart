import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The celebration the SENDER sees on Home when their interest has been
/// ACCEPTED: paper/confetti pieces fall from the top of the screen behind a
/// success card telling them the request went through.
///
/// It is shown ONCE per accepted interest (see
/// `pendingAcceptedInterestsProvider`), overlays the Home page rather than
/// navigating, and closes on tap, on the button, or by itself.
Future<void> showInterestAcceptedCelebration(
  BuildContext context, {
  required String name,
  VoidCallback? onOpenInterests,
  Duration autoDismissAfter = const Duration(seconds: 6),
}) async {
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'interest-accepted',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 340),
      transitionBuilder: (context, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: child,
        ),
      ),
      pageBuilder: (context, _, __) => _AcceptedCelebration(
        name: name,
        onOpenInterests: onOpenInterests,
        autoDismissAfter: autoDismissAfter,
      ),
    );
  } catch (_) {
    // A celebration hiccup must never break the Home page.
  }
}

class _AcceptedCelebration extends StatefulWidget {
  final String name;
  final VoidCallback? onOpenInterests;
  final Duration autoDismissAfter;

  const _AcceptedCelebration({
    required this.name,
    required this.onOpenInterests,
    required this.autoDismissAfter,
  });

  @override
  State<_AcceptedCelebration> createState() => _AcceptedCelebrationState();
}

class _AcceptedCelebrationState extends State<_AcceptedCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fall = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  late final List<_Confetto> _pieces = _buildPieces();

  static List<_Confetto> _buildPieces() {
    // Fixed seed → the same pleasing spread every time, and no per-frame
    // allocation while the animation runs.
    final rnd = math.Random(11);
    return [
      for (var i = 0; i < 46; i++)
        _Confetto(
          x: rnd.nextDouble(),
          delay: rnd.nextDouble(),
          speed: 0.7 + rnd.nextDouble() * 0.7,
          size: 6 + rnd.nextDouble() * 8,
          drift: (rnd.nextDouble() - 0.5) * 0.22,
          spin: (rnd.nextDouble() - 0.5) * 8,
          color: _palette[i % _palette.length],
        ),
    ];
  }

  static const _palette = <Color>[
    AppColors.gold,
    AppColors.primary,
    Color(0xFFFF7BA9),
    Color(0xFF64D2A0),
    Color(0xFF6EC1FF),
    Colors.white,
  ];

  /// Held so it can be CANCELLED on dispose — closing the card early must not
  /// leave a timer running that later fires against a dead element.
  Timer? _dismiss;

  @override
  void initState() {
    super.initState();
    _dismiss = Timer(widget.autoDismissAfter, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    _fall.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Paper falling from the very top of the screen, behind the card.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _fall,
                builder: (context, _) => CustomPaint(
                  painter: _ConfettiPainter(
                      progress: _fall.value, pieces: _pieces),
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: _card(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.25), blurRadius: 30),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.15),
                    AppColors.gold.withValues(alpha: 0.28),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(Icons.favorite_rounded,
                  size: 38, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            const Text(
              'Your Interest Request Has Been Accepted!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                height: 1.3,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.name.trim().isEmpty
                  ? 'The interest you sent has been accepted. You are now '
                      'connected.'
                  : '${widget.name.trim()} received the interest you sent and '
                      'has accepted it. You are now connected.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5, height: 1.45, color: Colors.grey[700]),
            ),
            const SizedBox(height: 22),
            if (widget.onOpenInterests != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onOpenInterests!();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('View Interests',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text('Close',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13.5)),
            ),
          ],
        ),
      );
}

/// One falling paper piece.
class _Confetto {
  /// Horizontal position as a fraction of the width (0–1).
  final double x;

  /// Fraction of the loop to wait before this piece starts falling.
  final double delay;
  final double speed;
  final double size;

  /// Sideways sway amplitude as a fraction of the width.
  final double drift;
  final double spin;
  final Color color;

  const _Confetto({
    required this.x,
    required this.delay,
    required this.speed,
    required this.size,
    required this.drift,
    required this.spin,
    required this.color,
  });
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  final List<_Confetto> pieces;

  const _ConfettiPainter({required this.progress, required this.pieces});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in pieces) {
      // Each piece runs its own loop, offset by its delay, so the fall looks
      // continuous rather than pulsing in waves.
      final t = ((progress * p.speed) + p.delay) % 1.0;
      // Start just ABOVE the top edge so pieces enter from off-screen.
      final y = -p.size + t * (size.height + p.size * 2);
      final sway = math.sin(t * math.pi * 3) * p.drift * size.width;
      final x = p.x * size.width + sway;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * p.spin);
      paint.color = p.color.withValues(alpha: 0.92);
      // Small paper rectangles, not dots — this should read as confetti.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset.zero, width: p.size, height: p.size * 0.62),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}
