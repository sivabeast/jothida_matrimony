import 'package:flutter/material.dart';

/// A label that shrinks its font just enough to keep **whole words** intact.
///
/// Tamil labels such as `பொருத்தங்கள்` or `சரிபார்க்கப்பட்ட` are far longer than
/// their English counterparts. In a narrow column (a quick-action tile, a
/// feature-highlight cell) a single Tamil word can be wider than the cell, and
/// Flutter's line breaker then has no choice but to split it **mid-word** —
/// which is what made the Home screen read as broken characters.
///
/// This widget removes that possibility. For the width it is actually given it
/// picks the largest font size (stepping down from the style's size, never
/// below [minFontSize]) at which BOTH hold:
///
///   • the longest single word still fits on one line — so a break can only
///     ever happen at a space, never inside a word;
///   • the whole string fits within [maxLines].
///
/// If even [minFontSize] cannot fit the longest word (a pathological width),
/// the text is ellipsised rather than split — a clipped label is far more
/// readable than a shattered one.
class AutoFitLabel extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int maxLines;
  final double minFontSize;
  final TextAlign textAlign;

  const AutoFitLabel(
    this.text, {
    super.key,
    required this.style,
    this.maxLines = 2,
    this.minFontSize = 8.5,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final start = style.fontSize ?? 14.0;
        var size = start;
        if (maxWidth.isFinite && maxWidth > 0) {
          while (size > minFontSize &&
              !_fits(style.copyWith(fontSize: size), maxWidth, scaler)) {
            size -= 0.5;
          }
        }
        final fitted = style.copyWith(fontSize: size);
        // `visible` when the chosen size genuinely fits; otherwise ellipsis so a
        // hopeless case degrades to a clipped word, never a split one.
        final ok = !maxWidth.isFinite || _fits(fitted, maxWidth, scaler);
        return Text(
          text,
          maxLines: maxLines,
          textAlign: textAlign,
          softWrap: true,
          overflow: ok ? TextOverflow.visible : TextOverflow.ellipsis,
          style: fitted,
        );
      },
    );
  }

  bool _fits(TextStyle candidate, double maxWidth, TextScaler scaler) {
    // 1. No single word may be wider than the line — that is the only situation
    //    in which Flutter breaks inside a word.
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      if (_width(word, candidate, scaler) > maxWidth) return false;
    }
    // 2. The full string must lay out within maxLines at this size.
    final painter = TextPainter(
      text: TextSpan(text: text, style: candidate),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: maxWidth);
    return !painter.didExceedMaxLines;
  }

  double _width(String value, TextStyle candidate, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: candidate),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    return painter.width;
  }
}
