import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The centred "Interest Sent" confirmation played the moment an interest is
/// successfully recorded.
///
/// A filled circle scales in, a tick draws itself inside it, and the label
/// fades up underneath. It is an OVERLAY on the current page — nothing
/// navigates — and it dismisses itself after [visibleFor].
///
/// Only ever call this AFTER the write has been confirmed: a network failure
/// must never show this animation.
Future<void> showInterestSentOverlay(
  BuildContext context, {
  String label = 'Interest Sent',
  Duration visibleFor = const Duration(milliseconds: 1500),
}) async {
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'interest-sent',
      barrierColor: Colors.black.withValues(alpha: 0.30),
      transitionDuration: const Duration(milliseconds: 260),
      transitionBuilder: (context, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      pageBuilder: (context, _, __) =>
          _InterestSentDialog(label: label, visibleFor: visibleFor),
    );
  } catch (_) {
    // A confirmation animation must never be able to break the send flow.
  }
}

class _InterestSentDialog extends StatefulWidget {
  final String label;
  final Duration visibleFor;

  const _InterestSentDialog({required this.label, required this.visibleFor});

  @override
  State<_InterestSentDialog> createState() => _InterestSentDialogState();
}

class _InterestSentDialogState extends State<_InterestSentDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  /// The circle pops in first…
  late final Animation<double> _circle = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 0.45, curve: Curves.easeOutBack),
  );

  /// …then the tick strokes itself in…
  late final Animation<double> _tick = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
  );

  /// …and the label fades up last.
  late final Animation<double> _text = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.6, 1, curve: Curves.easeOut),
  );

  /// Held so it can be CANCELLED on dispose — an uncancelled auto-dismiss
  /// timer outlives the dialog and fires against a dead element.
  Timer? _dismiss;

  @override
  void initState() {
    super.initState();
    _c.forward();
    // Auto-dismiss: the member never has to close this.
    _dismiss = Timer(widget.visibleFor, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: _circle.value,
                child: Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.success,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.45),
                        blurRadius: 26,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    painter: _TickPainter(progress: _tick.value),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Opacity(
                opacity: _text.value,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - _text.value)),
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws the tick stroke-by-stroke as [progress] runs 0 → 1.
class _TickPainter extends CustomPainter {
  final double progress;
  const _TickPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final w = size.width, h = size.height;
    // Classic check: down-stroke to the low point, then up to the right.
    final start = Offset(w * 0.28, h * 0.52);
    final mid = Offset(w * 0.44, h * 0.68);
    final end = Offset(w * 0.74, h * 0.36);

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // The two segments are drawn in sequence so the tick reads as one stroke.
    final firstLen = (mid - start).distance;
    final secondLen = (end - mid).distance;
    final total = firstLen + secondLen;
    final drawn = total * progress;

    final path = Path()..moveTo(start.dx, start.dy);
    if (drawn <= firstLen) {
      final t = firstLen == 0 ? 1.0 : drawn / firstLen;
      path.lineTo(start.dx + (mid.dx - start.dx) * t,
          start.dy + (mid.dy - start.dy) * t);
    } else {
      path.lineTo(mid.dx, mid.dy);
      final t = secondLen == 0 ? 1.0 : (drawn - firstLen) / secondLen;
      path.lineTo(
          mid.dx + (end.dx - mid.dx) * t, mid.dy + (end.dy - mid.dy) * t);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.progress != progress;
}
