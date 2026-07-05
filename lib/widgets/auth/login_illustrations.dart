import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Decorative illustrations for the role-based [LoginScreen], built as vector
/// widgets/CustomPainters rather than raster assets — a zodiac-ring couple
/// emblem, a Taj Mahal skyline silhouette, corner ribbon badges, and circular
/// couple/family "photo" illustrations with floating hearts. This keeps the
/// premium look from the reference design without shipping new image assets.

// ── Zodiac couple logo (Welcome screen) ─────────────────────────────────────

class ZodiacCoupleLogo extends StatelessWidget {
  final double size;
  const ZodiacCoupleLogo({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size(size, size), painter: _ZodiacRingPainter()),
          Container(
            width: size * 0.64,
            height: size * 0.64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF8A0F26), Color(0xFF4A0512)],
              ),
              border: Border.all(color: AppColors.gold, width: 1.4),
            ),
          ),
          SizedBox(
            width: size * 0.5,
            height: size * 0.5,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: const Alignment(-0.55, -0.05),
                  child: Icon(Icons.person,
                      color: AppColors.gold.withOpacity(0.95),
                      size: size * 0.22),
                ),
                Align(
                  alignment: const Alignment(0.55, -0.05),
                  child: Icon(Icons.person,
                      color: AppColors.goldLight.withOpacity(0.95),
                      size: size * 0.22),
                ),
                Align(
                  alignment: const Alignment(0, 0.5),
                  child: Icon(Icons.favorite,
                      color: AppColors.gold, size: size * 0.15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ZodiacRingPainter extends CustomPainter {
  static const _symbols = [
    '♈', '♉', '♊', '♋', '♌', '♍', '♎', '♏', '♐', '♑', '♒', '♓',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;

    canvas.drawCircle(
      center,
      r - 1.5,
      Paint()
        ..color = AppColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      center,
      r - 9,
      Paint()
        ..color = AppColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    for (var i = 0; i < 12; i++) {
      final angle = i * 30 * math.pi / 180;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + dir * (r - 3),
        center + dir * (r - 9),
        Paint()
          ..color = AppColors.gold
          ..strokeWidth = 1.2,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: _symbols[i],
          style: TextStyle(
              color: AppColors.gold,
              fontSize: r * 0.15,
              fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final gp = center + dir * (r - 19);
      tp.paint(canvas, gp - Offset(tp.width / 2, tp.height / 2));
    }

    for (final o in [
      Offset(-r * 0.72, -r * 0.62),
      Offset(r * 0.78, -r * 0.5),
      Offset(-r * 0.8, r * 0.58),
      Offset(r * 0.7, r * 0.68),
    ]) {
      _star(canvas, center + o, r * 0.05, AppColors.goldLight.withOpacity(0.9));
    }
  }

  void _star(Canvas canvas, Offset c, double s, Color color) {
    final path = Path()
      ..moveTo(c.dx, c.dy - s)
      ..lineTo(c.dx + s * 0.28, c.dy - s * 0.28)
      ..lineTo(c.dx + s, c.dy)
      ..lineTo(c.dx + s * 0.28, c.dy + s * 0.28)
      ..lineTo(c.dx, c.dy + s)
      ..lineTo(c.dx - s * 0.28, c.dy + s * 0.28)
      ..lineTo(c.dx - s, c.dy)
      ..lineTo(c.dx - s * 0.28, c.dy - s * 0.28)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ZodiacRingPainter oldDelegate) => false;
}

// ── Taj Mahal skyline silhouette (Welcome screen footer) ────────────────────

class TajMahalSkyline extends StatelessWidget {
  final double height;
  const TajMahalSkyline({super.key, this.height = 100});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(painter: _SkylinePainter(), size: Size.infinite),
    );
  }
}

class _SkylinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF3A0410).withOpacity(0.85);
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.6)
      ..lineTo(w * 0.07, h * 0.6)
      ..lineTo(w * 0.07, h * 0.32)
      ..lineTo(w * 0.115, h * 0.32)
      ..lineTo(w * 0.115, h * 0.6)
      ..lineTo(w * 0.27, h * 0.6)
      ..lineTo(w * 0.27, h * 0.4)
      ..lineTo(w * 0.315, h * 0.4)
      ..lineTo(w * 0.315, h * 0.6)
      ..lineTo(w * 0.39, h * 0.6)
      ..lineTo(w * 0.39, h * 0.34)
      ..quadraticBezierTo(w * 0.5, h * 0.02, w * 0.61, h * 0.34)
      ..lineTo(w * 0.61, h * 0.6)
      ..lineTo(w * 0.685, h * 0.6)
      ..lineTo(w * 0.685, h * 0.4)
      ..lineTo(w * 0.73, h * 0.4)
      ..lineTo(w * 0.73, h * 0.6)
      ..lineTo(w * 0.885, h * 0.6)
      ..lineTo(w * 0.885, h * 0.32)
      ..lineTo(w * 0.93, h * 0.32)
      ..lineTo(w * 0.93, h * 0.6)
      ..lineTo(w, h * 0.6)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SkylinePainter oldDelegate) => false;
}

// ── Corner ribbon badge (role cards) ────────────────────────────────────────

class CornerRibbon extends StatelessWidget {
  final Color color;
  const CornerRibbon({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: SizedBox(
        width: 60,
        height: 60,
        child: ClipRect(
          child: Align(
            alignment: Alignment.topRight,
            child: Transform.translate(
              offset: const Offset(18, -14),
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 90,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withOpacity(0.75)],
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Floating heart helper ───────────────────────────────────────────────────

class _FloatHeart extends StatelessWidget {
  final double size;
  final Color color;
  const _FloatHeart({required this.size, required this.color});
  @override
  Widget build(BuildContext context) =>
      Icon(Icons.favorite, size: size, color: color);
}

// ── Couple illustration circle (Matrimony login) ────────────────────────────

class CoupleIllustrationCircle extends StatelessWidget {
  final double size;
  final bool showFloatingHearts;
  const CoupleIllustrationCircle(
      {super.key, this.size = 200, this.showFloatingHearts = true});

  Widget _circle() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE3EC), Color(0xFFFFF6F8)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 26,
              offset: const Offset(0, 12)),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: const Alignment(-0.42, 0.05),
            child:
                Icon(Icons.person, size: size * 0.34, color: AppColors.primary),
          ),
          Align(
            alignment: const Alignment(0.42, 0.05),
            child: Icon(Icons.person,
                size: size * 0.34, color: AppColors.primaryLight),
          ),
          Align(
            alignment: const Alignment(0, 0.55),
            child:
                Icon(Icons.favorite, size: size * 0.13, color: AppColors.gold),
          ),
          Positioned(
            top: size * 0.06,
            child: Icon(Icons.local_florist,
                size: size * 0.11, color: const Color(0xFFE8A6BC)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!showFloatingHearts) return _circle();
    return SizedBox(
      width: size * 1.3,
      height: size * 1.3,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
              top: size * 0.02,
              left: size * 0.06,
              child: _FloatHeart(
                  size: size * 0.09,
                  color: const Color(0xFFEF5DA8).withOpacity(0.55))),
          Positioned(
              top: size * 0.16,
              right: 0,
              child:
                  _FloatHeart(size: size * 0.13, color: const Color(0xFFF48FB1))),
          Positioned(
              bottom: size * 0.08,
              left: 0,
              child: _FloatHeart(
                  size: size * 0.08,
                  color: const Color(0xFFEC407A).withOpacity(0.6))),
          Positioned(
              bottom: size * 0.2,
              right: size * 0.02,
              child:
                  _FloatHeart(size: size * 0.1, color: const Color(0xFFF06292))),
          _circle(),
        ],
      ),
    );
  }
}

// ── Family illustration circle (Family Member login) ────────────────────────

class FamilyIllustrationCircle extends StatelessWidget {
  final double size;
  final bool showFloatingHearts;
  const FamilyIllustrationCircle(
      {super.key, this.size = 200, this.showFloatingHearts = true});

  Widget _circle() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF3D6), Color(0xFFFFFAF0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 26,
              offset: const Offset(0, 12)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Icon(Icons.person, size: size * 0.26, color: const Color(0xFF4CAF50)),
          Icon(Icons.person, size: size * 0.3, color: const Color(0xFFE8735B)),
          Icon(Icons.person, size: size * 0.2, color: const Color(0xFF5C9BD1)),
          Icon(Icons.person, size: size * 0.18, color: const Color(0xFFEF5DA8)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!showFloatingHearts) return _circle();
    return SizedBox(
      width: size * 1.3,
      height: size * 1.3,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
              top: size * 0.02,
              left: size * 0.08,
              child: _FloatHeart(
                  size: size * 0.09,
                  color: const Color(0xFFEF5DA8).withOpacity(0.5))),
          Positioned(
              top: size * 0.14,
              right: 0,
              child: _FloatHeart(size: size * 0.11, color: AppColors.gold)),
          Positioned(
              bottom: size * 0.1,
              right: size * 0.04,
              child: _FloatHeart(
                  size: size * 0.08,
                  color: const Color(0xFFEC407A).withOpacity(0.55))),
          _circle(),
        ],
      ),
    );
  }
}

// ── Bottom wave clip (login step background) ─────────────────────────────────

class LoginWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()..moveTo(0, size.height * 0.22);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.05,
        size.width * 0.5, size.height * 0.14);
    path.quadraticBezierTo(
        size.width * 0.78, size.height * 0.24, size.width, size.height * 0.08);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
