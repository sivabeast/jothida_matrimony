import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/banner_model.dart';
import '../common/app_logo.dart';
import '../common/network_photo.dart';

/// Renders ONE admin-managed Home banner — shared by the Home carousel and the
/// admin Banner Management live preview, so what the admin sees is EXACTLY what
/// users get.
///
///  • IMAGE banner → the uploaded artwork, edge-to-edge (offers/posters carry
///    their own text inside the image).
///  • TEXT banner  → a professionally generated advertisement: a premium
///    template background (gradient/solid/pattern base + texture, light
///    effects, overlay and astrology design elements that are ALWAYS painted,
///    whatever colours the admin picks), a fixed layout — LEFT ~62% for
///    title/subtitle/description (with solid or gradient text), RIGHT ~38% for
///    the built-in company logo + astrology illustration.
class HomeBannerSlide extends StatelessWidget {
  final HomeBannerModel banner;
  const HomeBannerSlide({super.key, required this.banner});

  @override
  Widget build(BuildContext context) {
    if (banner.isImage) {
      return NetworkPhoto(
        url: banner.imageUrl,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        fallbackIcon: Icons.image_outlined,
        showLoadingSpinner: true,
      );
    }
    return _TextBannerAd(banner: banner);
  }
}

// ── Professional text-banner advertisement ────────────────────────────────────

class _TextBannerAd extends StatelessWidget {
  final HomeBannerModel banner;
  const _TextBannerAd({required this.banner});

  @override
  Widget build(BuildContext context) {
    final b = banner;
    final primary = b.effectivePrimary;
    final secondary = b.effectiveSecondary;
    final accent = b.templateEnum.accent;

    // Background base per the selected style. The decorative design layer is
    // painted ON TOP of every base, so changing colours or picking "Solid"
    // never strips the professional look.
    final BoxDecoration base = switch (b.backgroundStyleEnum) {
      BannerBackgroundStyle.solid => BoxDecoration(color: primary),
      _ => BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primary, secondary],
          ),
        ),
    };

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
      final scale = (w / 360).clamp(0.7, 1.6);

      return Container(
        decoration: base,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Texture + light effects + astrology backdrop elements.
            CustomPaint(
              painter: _BannerBackdropPainter(
                accent: accent,
                pattern:
                    b.backgroundStyleEnum == BannerBackgroundStyle.pattern,
              ),
            ),
            // Soft dark overlay along the bottom-left keeps text readable on
            // any colour combination.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.18),
                  ],
                ),
              ),
            ),
            // Fixed advertisement layout: text left (~62%) · graphics right.
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: 18 * scale, vertical: 14 * scale),
              child: Row(
                children: [
                  Expanded(flex: 62, child: _textColumn(scale)),
                  SizedBox(width: 8 * scale),
                  Expanded(flex: 38, child: _graphicColumn(accent, scale)),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  // ── Left side: title / subtitle / description ─────────────────────────────

  Widget _textColumn(double scale) {
    final b = banner;
    final titleSize = (b.fontSize > 0 ? b.fontSize : 21.0) * scale;
    final subtitleSize = (titleSize * 0.60).clamp(10.0, 20.0);
    final bodySize = (titleSize * 0.52).clamp(9.5, 17.0);
    final family = b.fontFamily.trim().isEmpty ? null : b.fontFamily.trim();

    Widget title = Text(
      b.title,
      textAlign: b.textAlignment,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        // ShaderMask needs a solid base colour to mask over.
        color: Colors.white,
        fontSize: titleSize,
        fontFamily: family,
        fontWeight: FontWeight.w800,
        height: 1.15,
        letterSpacing: 0.2,
      ),
    );
    if (b.textFillEnum == BannerTextFill.solid) {
      title = Text(
        b.title,
        textAlign: b.textAlignment,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: b.fgColor,
          fontSize: titleSize,
          fontFamily: family,
          fontWeight: FontWeight.w800,
          height: 1.15,
          letterSpacing: 0.2,
        ),
      );
    } else {
      // Two-colour / multi-colour gradient text.
      title = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: banner.effectiveTextGradient,
        ).createShader(bounds),
        child: title,
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: b.crossAlignment,
      children: [
        if (b.title.trim().isNotEmpty) title,
        if (b.subtitle.trim().isNotEmpty) ...[
          SizedBox(height: 5 * scale),
          Text(
            b.subtitle,
            textAlign: b.textAlignment,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: b.fgColor.withOpacity(0.95),
              fontSize: subtitleSize,
              fontFamily: family,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
        if (b.description.trim().isNotEmpty) ...[
          SizedBox(height: 7 * scale),
          Text(
            b.description,
            textAlign: b.textAlignment,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: b.fgColor.withOpacity(0.82),
              fontSize: bodySize,
              fontFamily: family,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  // ── Right side: built-in logo + astrology illustration ────────────────────

  Widget _graphicColumn(Color accent, double scale) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: accent.withOpacity(0.75), width: 1.6),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.35),
                blurRadius: 14 * scale,
                spreadRadius: 1,
              ),
            ],
          ),
          child: AppLogo(size: 40 * scale),
        ),
        SizedBox(height: 8 * scale),
        Expanded(
          child: AspectRatio(
            aspectRatio: 1,
            child: CustomPaint(
              painter: _AstroGraphicPainter(
                style: banner.logoStyleEnum,
                accent: accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Backdrop painter — texture · light effects · astrology elements ──────────

class _BannerBackdropPainter extends CustomPainter {
  final Color accent;
  final bool pattern;
  const _BannerBackdropPainter({required this.accent, required this.pattern});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // 1) Corner light effects (soft radial glows).
    final glow = Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withOpacity(0.16),
        Colors.transparent,
      ]).createShader(
          Rect.fromCircle(center: Offset(w * 0.92, h * 0.10), radius: w * 0.32));
    canvas.drawCircle(Offset(w * 0.92, h * 0.10), w * 0.32, glow);

    final glow2 = Paint()
      ..shader = RadialGradient(colors: [
        accent.withOpacity(0.14),
        Colors.transparent,
      ]).createShader(
          Rect.fromCircle(center: Offset(w * 0.06, h * 0.95), radius: w * 0.30));
    canvas.drawCircle(Offset(w * 0.06, h * 0.95), w * 0.30, glow2);

    // 2) Decorative concentric arcs (top-right), a classic premium texture.
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.white.withOpacity(0.10);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
          Offset(w * 1.02, -h * 0.10), w * (0.22 + i * 0.09), arc);
    }
    final arcAccent = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = accent.withOpacity(0.22);
    canvas.drawCircle(Offset(-w * 0.04, h * 1.06), w * 0.26, arcAccent);
    canvas.drawCircle(Offset(-w * 0.04, h * 1.06), w * 0.34, arc);

    // 3) Scattered stars + dots (astrology sky).
    final rnd = math.Random(7); // fixed seed → stable design
    for (var i = 0; i < 14; i++) {
      final p = Offset(rnd.nextDouble() * w, rnd.nextDouble() * h);
      final r = 0.8 + rnd.nextDouble() * 1.4;
      canvas.drawCircle(
          p,
          r,
          Paint()
            ..color = Colors.white.withOpacity(0.10 + rnd.nextDouble() * 0.16));
    }
    _star(canvas, Offset(w * 0.30, h * 0.16), 5.5,
        accent.withOpacity(0.55));
    _star(canvas, Offset(w * 0.52, h * 0.82), 4.5,
        Colors.white.withOpacity(0.40));
    _star(canvas, Offset(w * 0.08, h * 0.28), 3.5,
        Colors.white.withOpacity(0.35));

    // 4) Optional repeating diamond PATTERN (background style "Pattern").
    if (pattern) {
      final pat = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = Colors.white.withOpacity(0.07);
      const step = 26.0;
      for (double x = -h; x < w + h; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x + h, h), pat);
        canvas.drawLine(Offset(x + h, 0), Offset(x, h), pat);
      }
    }
  }

  /// A 4-point sparkle star.
  void _star(Canvas canvas, Offset c, double r, Color color) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BannerBackdropPainter old) =>
      old.accent != accent || old.pattern != pattern;
}

// ── Right-side astrology illustration painter ─────────────────────────────────

class _AstroGraphicPainter extends CustomPainter {
  final BannerLogoStyle style;
  final Color accent;
  const _AstroGraphicPainter({required this.style, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;
    switch (style) {
      case BannerLogoStyle.zodiacWheel:
        _zodiacWheel(canvas, c, r);
        break;
      case BannerLogoStyle.sunMoon:
        _sunMoon(canvas, c, r);
        break;
      case BannerLogoStyle.starSparkle:
        _starSparkle(canvas, c, r);
        break;
      case BannerLogoStyle.orbitRings:
        _orbitRings(canvas, c, r);
        break;
    }
  }

  Paint _stroke(double width, Color color) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..color = color;

  void _zodiacWheel(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(c, r * 0.92, _stroke(1.6, accent.withOpacity(0.85)));
    canvas.drawCircle(c, r * 0.72, _stroke(1.0, accent.withOpacity(0.55)));
    canvas.drawCircle(c, r * 0.30, _stroke(1.2, accent.withOpacity(0.75)));
    // 12 zodiac segment ticks between the two outer rings.
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final p1 = c + Offset(math.cos(a), math.sin(a)) * r * 0.72;
      final p2 = c + Offset(math.cos(a), math.sin(a)) * r * 0.92;
      canvas.drawLine(p1, p2, _stroke(1.0, accent.withOpacity(0.55)));
    }
    // Small dots on the inner ring positions.
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6 + math.pi / 12;
      final p = c + Offset(math.cos(a), math.sin(a)) * r * 0.82;
      canvas.drawCircle(p, 1.5, Paint()..color = accent.withOpacity(0.8));
    }
    // Centre star.
    _spark(canvas, c, r * 0.16, accent);
  }

  void _sunMoon(Canvas canvas, Offset c, double r) {
    // Sun rays.
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final p1 = c + Offset(math.cos(a), math.sin(a)) * r * 0.62;
      final p2 = c + Offset(math.cos(a), math.sin(a)) * r * 0.88;
      canvas.drawLine(p1, p2, _stroke(1.6, accent.withOpacity(0.75)));
    }
    canvas.drawCircle(c, r * 0.48, _stroke(1.6, accent.withOpacity(0.9)));
    // Crescent moon inside: full disc + offset punch-out drawn with the
    // background-ish translucent overlay (approximation: draw arc crescent).
    final moon = Path()
      ..addArc(Rect.fromCircle(center: c, radius: r * 0.34), -math.pi / 2,
          math.pi)
      ..arcTo(
          Rect.fromCircle(
              center: c + Offset(-r * 0.12, 0), radius: r * 0.30),
          math.pi / 2,
          -math.pi,
          false)
      ..close();
    canvas.drawPath(moon, Paint()..color = accent.withOpacity(0.85));
    _spark(canvas, c + Offset(r * 0.30, -r * 0.30), r * 0.09, accent);
  }

  void _starSparkle(Canvas canvas, Offset c, double r) {
    _spark(canvas, c, r * 0.52, accent.withOpacity(0.95));
    _spark(canvas, c + Offset(-r * 0.55, -r * 0.45), r * 0.20,
        accent.withOpacity(0.75));
    _spark(canvas, c + Offset(r * 0.55, r * 0.50), r * 0.16,
        accent.withOpacity(0.65));
    _spark(canvas, c + Offset(r * 0.60, -r * 0.55), r * 0.12,
        Colors.white.withOpacity(0.6));
    canvas.drawCircle(c, r * 0.86, _stroke(1.0, accent.withOpacity(0.35)));
  }

  void _orbitRings(Canvas canvas, Offset c, double r) {
    // Planet.
    canvas.drawCircle(c, r * 0.26,
        Paint()..color = accent.withOpacity(0.85));
    canvas.drawCircle(c, r * 0.26, _stroke(1.2, Colors.white.withOpacity(0.5)));
    // Two tilted elliptical orbits.
    for (final tilt in [0.5, -0.6]) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(tilt);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset.zero, width: r * 1.8, height: r * 0.75),
          _stroke(1.2, accent.withOpacity(0.6)));
      canvas.restore();
    }
    // Orbiting moons.
    canvas.drawCircle(c + Offset(r * 0.78, -r * 0.12), r * 0.07,
        Paint()..color = Colors.white.withOpacity(0.85));
    canvas.drawCircle(c + Offset(-r * 0.70, r * 0.28), r * 0.05,
        Paint()..color = accent.withOpacity(0.9));
  }

  /// 4-point sparkle.
  void _spark(Canvas canvas, Offset c, double r, Color color) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_AstroGraphicPainter old) =>
      old.style != style || old.accent != accent;
}
