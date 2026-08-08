import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Decorative illustrations for the role-based [LoginScreen], built as vector
/// widgets/CustomPainters rather than raster assets — a Taj Mahal skyline
/// silhouette, corner ribbon badges, and circular couple/family "photo"
/// illustrations with floating hearts. This keeps the premium look from the
/// reference design without shipping new image assets.
///
/// Deliberately NOT here: a brand mark. This file used to also carry a
/// hand-painted `ZodiacCoupleLogo` — a second, slightly different version of
/// the company logo. The real logo is the one asset behind
/// `AppLogo`/`AppLauncherLogo` (lib/widgets/common/app_logo.dart); use those.

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

/// Anime-style family portrait, painted as vectors — father, mother and child
/// in chibi proportions (oversized heads, closed "happy" eyes, blush cheeks,
/// and the child's little ahoge hair tuft).
///
/// Everything is laid out in a normalised 0..1 space and multiplied by the
/// canvas width, so the SAME artwork stays crisp at the 76px role card and the
/// 200px role-login circle — no raster asset, no second file to ship, and it
/// never pixelates. This replaces the four stacked `Icons.person` glyphs that
/// used to stand in for the family.
///
/// Public (not `_`-private) so it can be dropped into other screens later.
class AnimeFamilyPainter extends CustomPainter {
  const AnimeFamilyPainter();

  static const _skin = Color(0xFFF8D3B3);
  static const _hair = Color(0xFF3A2A21);
  static const _hairSoft = Color(0xFF5A4034);
  static const _fatherWear = Color(0xFF33518A);
  static const _motherWear = Color(0xFFC2185B);
  static const _childWear = Color(0xFFF2B33D);
  static const _blush = Color(0x59F1857D);
  static const _ink = Color(0xFF4A3428);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    Offset p(double x, double y) => Offset(x * w, y * w);
    double u(double v) => v * w;

    final fill = Paint()..style = PaintingStyle.fill;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = _ink;

    // Soft contact shadow so the group sits on the circle instead of floating.
    fill.color = const Color(0x14000000);
    canvas.drawOval(
        Rect.fromCenter(
            center: p(0.5, 0.88), width: u(0.66), height: u(0.075)),
        fill);

    // A torso is a trapezoid with curved shoulders — narrow at the neck,
    // flaring to the hem.
    void torso(double cx, double topY, double hemY, double hemHalf, Color c) {
      fill.color = c;
      canvas.drawPath(
        Path()
          ..moveTo(u(cx - hemHalf), u(hemY))
          ..quadraticBezierTo(
              u(cx - hemHalf * 0.72), u(topY), u(cx), u(topY))
          ..quadraticBezierTo(
              u(cx + hemHalf * 0.72), u(topY), u(cx + hemHalf), u(hemY))
          ..close(),
        fill,
      );
    }

    // Closed, upturned "happy" eyes + a small smile — the anime shorthand that
    // reads as warmth even when the whole face is only a few pixels wide.
    void face(double cx, double cy, double r) {
      line.strokeWidth = (r * 0.16).clamp(0.9, 3.0);
      for (final dx in [-r * 0.40, r * 0.40]) {
        canvas.drawArc(
            Rect.fromCenter(
                center: p(cx, cy) + Offset(dx, -r * 0.06),
                width: r * 0.44,
                height: r * 0.34),
            math.pi,
            math.pi,
            false,
            line);
      }
      canvas.drawArc(
          Rect.fromCenter(
              center: p(cx, cy) + Offset(0, r * 0.34),
              width: r * 0.34,
              height: r * 0.26),
          math.pi * 0.15,
          math.pi * 0.7,
          false,
          line);
      fill.color = _blush;
      for (final dx in [-r * 0.66, r * 0.66]) {
        canvas.drawOval(
            Rect.fromCenter(
                center: p(cx, cy) + Offset(dx, r * 0.24),
                width: r * 0.34,
                height: r * 0.20),
            fill);
      }
    }

    void head(double cx, double cy, double r) {
      fill.color = _skin;
      canvas.drawCircle(p(cx, cy), r, fill);
    }

    // ── Father (left) ────────────────────────────────────────────────────
    torso(0.29, 0.50, 0.84, 0.15, _fatherWear);
    final fr = u(0.115);
    head(0.29, 0.375, fr);
    fill.color = _hair; // short side-parted crop
    canvas.drawPath(
      Path()
        ..moveTo(u(0.29) - fr, u(0.375) - fr * 0.10)
        ..quadraticBezierTo(
            u(0.29) - fr * 1.02, u(0.375) - fr * 1.30, u(0.29) + fr * 0.16, u(0.375) - fr * 1.16)
        ..quadraticBezierTo(
            u(0.29) + fr * 1.06, u(0.375) - fr * 1.00, u(0.29) + fr, u(0.375) - fr * 0.06)
        ..quadraticBezierTo(
            u(0.29) + fr * 0.60, u(0.375) - fr * 0.72, u(0.29) - fr * 0.10, u(0.375) - fr * 0.60)
        ..quadraticBezierTo(
            u(0.29) - fr * 0.72, u(0.375) - fr * 0.52, u(0.29) - fr, u(0.375) - fr * 0.10)
        ..close(),
      fill,
    );
    face(0.29, 0.375, fr);

    // ── Mother (right) ───────────────────────────────────────────────────
    torso(0.71, 0.50, 0.84, 0.155, _motherWear);
    final mr = u(0.115);
    // Long hair falls behind the shoulders, so it is painted before the face.
    fill.color = _hair;
    canvas.drawPath(
      Path()
        ..moveTo(u(0.71) - mr * 1.06, u(0.375) + mr * 1.55)
        ..quadraticBezierTo(u(0.71) - mr * 1.30, u(0.375) - mr * 0.60,
            u(0.71), u(0.375) - mr * 1.22)
        ..quadraticBezierTo(u(0.71) + mr * 1.30, u(0.375) - mr * 0.60,
            u(0.71) + mr * 1.06, u(0.375) + mr * 1.55)
        ..quadraticBezierTo(
            u(0.71), u(0.375) + mr * 0.98, u(0.71) - mr * 1.06, u(0.375) + mr * 1.55)
        ..close(),
      fill,
    );
    head(0.71, 0.375, mr);
    fill.color = _hair; // fringe
    canvas.drawPath(
      Path()
        ..moveTo(u(0.71) - mr, u(0.375) - mr * 0.06)
        ..quadraticBezierTo(u(0.71) - mr * 1.04, u(0.375) - mr * 1.34,
            u(0.71), u(0.375) - mr * 1.20)
        ..quadraticBezierTo(u(0.71) + mr * 1.04, u(0.375) - mr * 1.34,
            u(0.71) + mr, u(0.375) - mr * 0.06)
        ..quadraticBezierTo(u(0.71) + mr * 0.30, u(0.375) - mr * 0.46,
            u(0.71) - mr * 0.30, u(0.375) - mr * 0.50)
        ..quadraticBezierTo(u(0.71) - mr * 0.78, u(0.375) - mr * 0.52,
            u(0.71) - mr, u(0.375) - mr * 0.06)
        ..close(),
      fill,
    );
    face(0.71, 0.375, mr);
    fill.color = AppColors.gold; // flower tucked into her hair
    for (var i = 0; i < 5; i++) {
      final a = i * math.pi * 0.4;
      canvas.drawCircle(
          p(0.71, 0.375) +
              Offset(-mr * 0.98 + math.cos(a) * mr * 0.16,
                  -mr * 0.62 + math.sin(a) * mr * 0.16),
          mr * 0.13,
          fill);
    }

    // ── Child (front centre, smaller and overlapping the parents) ────────
    torso(0.50, 0.665, 0.88, 0.105, _childWear);
    final cr = u(0.082);
    head(0.50, 0.585, cr);
    fill.color = _hairSoft;
    canvas.drawPath(
      Path()
        ..moveTo(u(0.50) - cr, u(0.585) - cr * 0.04)
        ..quadraticBezierTo(u(0.50) - cr * 1.06, u(0.585) - cr * 1.34,
            u(0.50), u(0.585) - cr * 1.20)
        ..quadraticBezierTo(u(0.50) + cr * 1.06, u(0.585) - cr * 1.34,
            u(0.50) + cr, u(0.585) - cr * 0.04)
        ..quadraticBezierTo(u(0.50) + cr * 0.36, u(0.585) - cr * 0.54,
            u(0.50) - cr * 0.36, u(0.585) - cr * 0.54)
        ..quadraticBezierTo(u(0.50) - cr * 0.80, u(0.585) - cr * 0.50,
            u(0.50) - cr, u(0.585) - cr * 0.04)
        ..close(),
      fill,
    );
    // Ahoge — the single stray strand that makes it read as anime.
    line
      ..color = _hairSoft
      ..strokeWidth = (cr * 0.20).clamp(1.0, 3.0);
    canvas.drawPath(
      Path()
        ..moveTo(u(0.50) + cr * 0.06, u(0.585) - cr * 1.16)
        ..quadraticBezierTo(u(0.50) + cr * 0.62, u(0.585) - cr * 1.86,
            u(0.50) + cr * 0.92, u(0.585) - cr * 1.30),
      line,
    );
    line.color = _ink;
    face(0.50, 0.585, cr);
  }

  @override
  bool shouldRepaint(covariant AnimeFamilyPainter oldDelegate) => false;
}

// ── Family illustration circle (Family Member login) ────────────────────────

class FamilyIllustrationCircle extends StatelessWidget {
  /// Optional artwork for the Family Member role. Drop a square-ish PNG here
  /// and BOTH the welcome role card and the family login screen pick it up —
  /// they share this widget, so there is only one file to replace.
  ///
  /// If the file is absent the [AnimeFamilyPainter] vector artwork is drawn
  /// instead, so a missing asset can never break the build or leave a blank
  /// circle. That makes the image genuinely optional.
  static const String assetPath = 'assets/images/family_login.png';

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
      // ClipOval keeps a rectangular photo inside the circular frame; cover
      // crops the edges rather than squashing the family out of proportion.
      child: ClipOval(
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => CustomPaint(
            size: Size.square(size),
            painter: const AnimeFamilyPainter(),
          ),
        ),
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
