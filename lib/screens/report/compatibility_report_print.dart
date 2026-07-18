import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../models/compatibility_report_model.dart';

/// A4 print layout + PDF/Image export for the Marriage Compatibility Report.
///
/// The report pages are laid out as REAL Flutter widgets at a fixed A4 logical
/// size and rasterised with [RepaintBoundary.toImage] — Flutter's text engine
/// shapes Tamil correctly, which the `pdf` package's own TTF renderer does not
/// guarantee. The captured PNG pages are then embedded 1:1 into an A4 PDF (or
/// shared directly as images).
///
/// Pagination is measurement-driven (no fixed page plan): every section is
/// first laid out offscreen at the real content width to get its true height,
/// then sections FLOW onto pages one after another so no page is left with a
/// big empty gap. A table (with its title) is atomic — if it does not fit in
/// the space left on the current page, the whole table starts on a fresh page.
/// Only the explanation text may split across pages (at line boundaries).

// A4 @ 96dpi logical pixels.
const double kA4PageW = 794;
const double kA4PageH = 1123;

// Width available to page content inside the framed page:
// 794 − 2×16 (page pad) − 2×1.4 (outer border) − 2×3 (frame pad)
//     − 2×0.8 (inner border) − 2×22 (inner pad) ≈ 707.
const double kContentW = 707;

// Vertical chrome around the body: 2×16 page pad + borders/frame pad (≈8.4)
// + inner pad (18 top + 12 bottom) + 14 gap under the header.
const double _kPageVChrome = 32 + 8.4 + 30 + 14;

// Explanation text width inside its bordered block (padding 12×2 + borders).
const double _kExplTextW = kContentW - 26;
// Vertical chrome of the explanation block (padding + borders).
const double _kExplChrome = 26;
// Gap inserted between two sections on the same page.
const double _kSectionGap = 16;

const TextStyle _kExplStyle =
    TextStyle(fontSize: 10.5, height: 1.55, color: Color(0xFF262626));

const Color _maroon = AppColors.primary;
const Color _gold = AppColors.gold;
const Color _paper = Color(0xFFFDF8F1);

String _dash(String v) => v.trim().isEmpty ? '—' : v.trim();

// ─────────────────────────────────────────────────────────────────────────────
// Print widgets
// ─────────────────────────────────────────────────────────────────────────────

/// One framed A4 page: double certificate border, centered branding header,
/// body, footer with page numbers. Body overflow is clipped as a last-resort
/// guard — the measured pagination keeps real content inside the page.
Widget _a4Page({
  required List<Widget> body,
  required int pageNo,
  required int pageCount,
  required String reportNumber,
  required String reportDate,
}) {
  return Container(
    width: kA4PageW,
    height: kA4PageH,
    color: Colors.white,
    padding: const EdgeInsets.all(16),
    child: Container(
      decoration: BoxDecoration(border: Border.all(color: _maroon, width: 1.4)),
      padding: const EdgeInsets.all(3),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: _gold, width: 0.8)),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _printHeader(reportNumber, reportDate),
            const SizedBox(height: 14),
            Expanded(
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: body,
                  ),
                ),
              ),
            ),
            _printFooter(pageNo, pageCount),
          ],
        ),
      ),
    ),
  );
}

/// The report logo — the rounded-square brand mark, clipped so its rounded
/// corners stay clean on the white page. Falls back to the app logo / icon.
Widget _reportLogo(double size) => ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/images/report_logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/images/app_logo.png',
          width: size,
          height: size,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.auto_awesome, color: _maroon, size: size * 0.8),
        ),
      ),
    );

/// Centered branding header — logo on top, name + subtitle + report meta
/// beneath, then the maroon/gold rules.
Widget _printHeader(String reportNumber, String reportDate) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _reportLogo(62)),
        const SizedBox(height: 8),
        const Center(
          child: Text('Jothida Matrimony',
              style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: _maroon)),
        ),
        const SizedBox(height: 2),
        Center(
          child: Text('Professional Marriage Compatibility Report',
              style: TextStyle(fontSize: 10.5, color: Colors.grey[800])),
        ),
        const SizedBox(height: 5),
        Center(
          child: Text(
              'Report No: $reportNumber    |    Report Date: $reportDate',
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700])),
        ),
        const SizedBox(height: 10),
        Container(height: 2.6, color: _maroon),
        const SizedBox(height: 2),
        Container(height: 1.2, color: _gold),
      ],
    );

Widget _printFooter(int pageNo, int pageCount) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 0.8, color: Colors.grey[350]),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Jothida Matrimony • Marriage Compatibility Report',
                style: TextStyle(fontSize: 8.5, color: Colors.grey[600])),
            Text('Page $pageNo of $pageCount',
                style: TextStyle(fontSize: 8.5, color: Colors.grey[600])),
          ],
        ),
      ],
    );

Widget _sectionTitle(String title) => Row(
      children: [
        const Expanded(child: Divider(color: _gold, thickness: 0.9)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: _maroon)),
        ),
        const Expanded(child: Divider(color: _gold, thickness: 0.9)),
      ],
    );

/// A section title glued to its table so the pair paginates as ONE unit —
/// a table never starts at the bottom of a page without its heading.
Widget _titledGroup(String title, Widget child) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_sectionTitle(title), const SizedBox(height: 8), child],
    );

Widget _coupleRow(CompatibilityReport r) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _personCard('மணமகள் விவரங்கள் (Bride)', r.bride)),
        const SizedBox(width: 14),
        Expanded(child: _personCard('மணமகன் விவரங்கள் (Groom)', r.groom)),
      ],
    );

Widget _personCard(String title, CompatPerson p) => Container(
      decoration: BoxDecoration(
        color: _paper,
        border: Border.all(color: _maroon.withOpacity(0.35), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: _maroon,
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            child: Text(title,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              children: [
                _personRow('பெயர் / Name', p.name),
                _personRow('பிறந்த தேதி / DOB', p.dob),
                _personRow('பிறந்த நேரம் / Time', p.birthTime),
                _personRow('பிறந்த இடம் / Place', p.birthPlace),
                _personRow('நட்சத்திரம் / Star', p.star),
                _personRow('ராசி / Rasi', p.rasi),
              ],
            ),
          ),
        ],
      ),
    );

Widget _personRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 118,
              child: Text(label,
                  style: TextStyle(fontSize: 9, color: Colors.grey[700]))),
          Expanded(
              child: Text(_dash(value),
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600))),
        ],
      ),
    );

TableBorder get _tableBorder =>
    TableBorder.all(color: _maroon.withOpacity(0.35), width: 0.6);

Widget _headCell(String text) => Container(
      color: _maroon,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      alignment: Alignment.center,
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
    );

Widget _bodyCell(String text,
        {bool bold = false, TextAlign align = TextAlign.center}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.5, horizontal: 6),
      child: Text(_dash(text),
          textAlign: align,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
    );

/// The உண்டு / இல்லை verdict cell rendered as a green tick / red cross.
Widget _answerCell(String answer) {
  if (answer != CompatAnswer.yes && answer != CompatAnswer.no) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6.5),
      child: Text('—', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10.5, color: Colors.grey)),
    );
  }
  final yes = answer == CompatAnswer.yes;
  final color = yes ? const Color(0xFF1B7E3C) : const Color(0xFFC62828);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5.5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(yes ? Icons.check_circle : Icons.cancel, size: 13, color: color),
        const SizedBox(width: 4),
        Text(yes ? 'உண்டு' : 'இல்லை',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      ],
    ),
  );
}

TableRow _zebra(int i, List<Widget> cells) => TableRow(
      decoration: BoxDecoration(color: i.isOdd ? _paper : Colors.white),
      children: [
        for (final c in cells)
          TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle, child: c),
      ],
    );

Widget _poruthamTable(CompatibilityReport r) => Table(
      border: _tableBorder,
      columnWidths: const {
        0: FixedColumnWidth(34),
        1: FlexColumnWidth(1.3),
        2: FlexColumnWidth(1.05),
        3: FlexColumnWidth(1.05),
        4: FixedColumnWidth(104),
      },
      children: [
        TableRow(children: [
          _headCell('No'),
          _headCell('பொருத்தம்'),
          _headCell('பெண்'),
          _headCell('ஆண்'),
          _headCell('பொருத்தம்'),
        ]),
        for (var i = 0; i < CompatibilityReport.poruthamNames.length; i++)
          _zebra(i, [
            _bodyCell('${i + 1}'),
            _bodyCell(CompatibilityReport.poruthamNames[i],
                bold: true, align: TextAlign.left),
            _bodyCell(r.poruthamAt(i).bride),
            _bodyCell(r.poruthamAt(i).groom),
            _answerCell(r.poruthamAt(i).match),
          ]),
      ],
    );

Widget _doshamTable(List<String> names, List<DoshamRow> rows) => Table(
      border: _tableBorder,
      columnWidths: const {
        0: FlexColumnWidth(1.5),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
      },
      children: [
        TableRow(children: [
          _headCell('விவரம்'),
          _headCell('பெண்'),
          _headCell('ஆண்'),
        ]),
        for (var i = 0; i < names.length; i++)
          _zebra(i, [
            _bodyCell(names[i], bold: true, align: TextAlign.left),
            _answerCell(rows[i].bride),
            _answerCell(rows[i].groom),
          ]),
      ],
    );

Widget _dasaTable(CompatibilityReport r) => Table(
      border: _tableBorder,
      columnWidths: const {
        0: FlexColumnWidth(1.5),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
      },
      children: [
        TableRow(children: [
          _headCell('விவரம்'),
          _headCell('பெண்'),
          _headCell('ஆண்'),
        ]),
        for (var i = 0; i < CompatibilityReport.dasaNames.length; i++)
          _zebra(i, [
            _bodyCell(CompatibilityReport.dasaNames[i],
                bold: true, align: TextAlign.left),
            _bodyCell(r.dasaAt(i).bride),
            _bodyCell(r.dasaAt(i).groom),
          ]),
      ],
    );

Widget _explanationBlock(String text) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _paper,
        border: Border.all(color: _maroon.withOpacity(0.3), width: 0.7),
      ),
      child: Text(text, style: _kExplStyle, textAlign: TextAlign.justify),
    );

Widget _finalResultBand(String answer) {
  final yes = answer == CompatAnswer.yes;
  final no = answer == CompatAnswer.no;
  final color = yes
      ? const Color(0xFF1B7E3C)
      : no
          ? const Color(0xFFC62828)
          : Colors.grey;
  final label = yes
      ? 'பொருத்தம் உண்டு'
      : no
          ? 'பொருத்தம் இல்லை'
          : '—';
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      border: Border.all(color: color, width: 1.1),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (yes || no)
          Icon(yes ? Icons.check_circle : Icons.cancel, size: 20, color: color),
        if (yes || no) const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 15.5, fontWeight: FontWeight.w800, color: color)),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Explanation text splitting
// ─────────────────────────────────────────────────────────────────────────────

double _textHeight(String text, TextStyle style, double maxWidth) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);
  return tp.height;
}

/// Splits [text] into page-sized chunks: the first chunk fits [firstHeight],
/// every later chunk fits [otherHeight]. Cuts only at line boundaries so no
/// line of text is ever sliced through.
List<String> _splitTextForPages(
  String text,
  TextStyle style,
  double maxWidth,
  double firstHeight,
  double otherHeight,
) {
  final out = <String>[];
  var remaining = text.trim();
  var avail = firstHeight;
  while (remaining.isNotEmpty) {
    final tp = TextPainter(
      text: TextSpan(text: remaining, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    if (tp.height <= avail) {
      out.add(remaining);
      break;
    }
    final metrics = tp.computeLineMetrics();
    double used = 0;
    int lastLine = -1;
    for (var i = 0; i < metrics.length; i++) {
      if (used + metrics[i].height <= avail) {
        used += metrics[i].height;
        lastLine = i;
      } else {
        break;
      }
    }
    if (lastLine < 0) {
      // The page can't even hold one line — dump the rest (clipped guard).
      out.add(remaining);
      break;
    }
    final pos = tp.getPositionForOffset(
        Offset(maxWidth, used - metrics[lastLine].height / 2));
    final cut = tp.getLineBoundary(pos).end;
    if (cut <= 0 || cut >= remaining.length) {
      out.add(remaining);
      break;
    }
    out.add(remaining.substring(0, cut).trimRight());
    remaining = remaining.substring(cut).trimLeft();
    avail = otherHeight;
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Measure → paginate → capture
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen route that (1) lays the report sections out offscreen at the
/// real A4 content width to measure their true heights, (2) flows them onto
/// pages — tables are atomic, only the explanation text splits — and (3)
/// paints each page behind an opaque "preparing" overlay, capturing every page
/// as a PNG. Pops with the page images (null on failure).
class CompatReportCaptureScreen extends StatefulWidget {
  final CompatibilityReport report;
  final String reportNumber;
  final String reportDate;

  const CompatReportCaptureScreen({
    super.key,
    required this.report,
    required this.reportNumber,
    required this.reportDate,
  });

  static Future<List<Uint8List>?> capture(
    BuildContext context, {
    required CompatibilityReport report,
    required String reportNumber,
    required String reportDate,
  }) =>
      Navigator.of(context).push<List<Uint8List>>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CompatReportCaptureScreen(
          report: report,
          reportNumber: reportNumber,
          reportDate: reportDate,
        ),
      ));

  @override
  State<CompatReportCaptureScreen> createState() =>
      _CompatReportCaptureScreenState();
}

class _CompatReportCaptureScreenState extends State<CompatReportCaptureScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  final GlobalKey _headerKey = GlobalKey();
  final GlobalKey _footerKey = GlobalKey();
  final GlobalKey _explTitleKey = GlobalKey();
  late final List<Widget> _sections; // atomic sections, in report order
  late final List<GlobalKey> _sectionKeys;

  List<Widget> _pages = const [];
  bool _measuring = true;
  int _pageIndex = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final r = widget.report;
    _sections = [
      _coupleRow(r),
      _titledGroup('திருமண பொருத்தம்', _poruthamTable(r)),
      _titledGroup(
          'செவ்வாய் தோஷம்',
          _doshamTable(CompatibilityReport.sevvaiNames,
              [for (var i = 0; i < 3; i++) r.sevvaiAt(i)])),
      _titledGroup(
          'பிற தோஷங்கள்',
          _doshamTable(CompatibilityReport.otherDoshamNames,
              [for (var i = 0; i < 2; i++) r.otherDoshamAt(i)])),
      _titledGroup('திசா சந்தி', _dasaTable(r)),
      // Explanation is handled separately (splittable); final result is atomic.
      _titledGroup('இறுதி முடிவு', _finalResultBand(r.finalResult)),
    ];
    _sectionKeys = [for (final _ in _sections) GlobalKey()];
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_started) return;
    _started = true;
    try {
      // Let the measuring pass (and the logo asset) settle, then read sizes.
      await _pumpFrame();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await _pumpFrame();

      double h(GlobalKey k) => k.currentContext?.size?.height ?? 0;
      final headerH = h(_headerKey);
      final footerH = h(_footerKey);
      final explTitleH = h(_explTitleKey);
      final sectionHs = [for (final k in _sectionKeys) h(k)];
      if (headerH <= 0) throw StateError('measuring pass failed');

      final bodyH = kA4PageH - _kPageVChrome - headerH - footerH - 4;
      final bodies =
          _paginate(sectionHs, bodyH: bodyH, explTitleH: explTitleH);
      _pages = [
        for (var i = 0; i < bodies.length; i++)
          _a4Page(
            body: bodies[i],
            pageNo: i + 1,
            pageCount: bodies.length,
            reportNumber: widget.reportNumber,
            reportDate: widget.reportDate,
          ),
      ];

      // Capture every page.
      final out = <Uint8List>[];
      for (var i = 0; i < _pages.length; i++) {
        setState(() {
          _measuring = false;
          _pageIndex = i;
        });
        await _pumpFrame();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await _pumpFrame();
        final boundary = _boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary == null) throw StateError('capture boundary missing');
        final image = await boundary.toImage(pixelRatio: 2.5);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (data == null) throw StateError('PNG encode failed');
        out.add(data.buffer.asUint8List());
      }
      if (mounted) Navigator.of(context).pop(out);
    } catch (e) {
      debugPrint('[CompatReport] capture failed: $e');
      if (mounted) Navigator.of(context).pop(null);
    }
  }

  /// Flows the measured sections onto pages. Every atomic section that does not
  /// fit in the current page's remaining space starts a fresh page; the
  /// explanation text fills whatever space is left and continues across pages.
  List<List<Widget>> _paginate(
    List<double> sectionHs, {
    required double bodyH,
    required double explTitleH,
  }) {
    final pages = <List<Widget>>[];
    var cur = <Widget>[];
    var remaining = bodyH;

    void closePage() {
      if (cur.isNotEmpty) {
        pages.add(cur);
        cur = <Widget>[];
        remaining = bodyH;
      }
    }

    void addGap() {
      if (cur.isNotEmpty) {
        cur.add(const SizedBox(height: _kSectionGap));
        remaining -= _kSectionGap;
      }
    }

    void addAtomic(Widget w, double h) {
      final need = (cur.isEmpty ? 0 : _kSectionGap) + h;
      if (need > remaining && cur.isNotEmpty) closePage();
      addGap();
      cur.add(w);
      remaining -= h;
    }

    // All sections up to (but excluding) the final-result group, then the
    // explanation, then the final result — matching the on-screen order.
    final finalIdx = _sections.length - 1;
    for (var i = 0; i < finalIdx; i++) {
      addAtomic(_sections[i], sectionHs[i]);
    }

    final expl = widget.report.explanation.trim();
    if (expl.isNotEmpty) {
      // Move to a fresh page only when not even the title + a few lines fit.
      final gap = cur.isEmpty ? 0 : _kSectionGap;
      if (remaining - gap - explTitleH - 8 - _kExplChrome < 50) closePage();
      addGap();
      final firstAvail =
          remaining - explTitleH - 8 - _kExplChrome;
      final otherAvail = bodyH - _kExplChrome;
      final chunks = _splitTextForPages(
          expl, _kExplStyle, _kExplTextW, firstAvail, otherAvail);
      cur.add(_sectionTitle('பொருத்தம் குறிப்பு / விளக்கம்'));
      cur.add(const SizedBox(height: 8));
      cur.add(_explanationBlock(chunks.first));
      remaining -= explTitleH +
          8 +
          _kExplChrome +
          _textHeight(chunks.first, _kExplStyle, _kExplTextW);
      for (final chunk in chunks.skip(1)) {
        closePage();
        cur.add(_explanationBlock(chunk));
        remaining -=
            _kExplChrome + _textHeight(chunk, _kExplStyle, _kExplTextW);
      }
    }

    addAtomic(_sections[finalIdx], sectionHs[finalIdx]);
    closePage();
    return pages;
  }

  Future<void> _pumpFrame() {
    WidgetsBinding.instance.scheduleFrame();
    return WidgetsBinding.instance.endOfFrame;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          if (_measuring)
            // Offscreen measuring pass: lay every piece out at the REAL A4
            // content width (nested scroll views give unbounded room, so the
            // sections take their true intrinsic heights).
            Positioned(
              left: 0,
              top: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: kContentW,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KeyedSubtree(
                            key: _headerKey,
                            child: _printHeader(
                                widget.reportNumber, widget.reportDate)),
                        KeyedSubtree(
                            key: _footerKey, child: _printFooter(1, 1)),
                        KeyedSubtree(
                            key: _explTitleKey,
                            child: _sectionTitle('பொருத்தம் குறிப்பு / விளக்கம்')),
                        for (var i = 0; i < _sections.length; i++)
                          KeyedSubtree(
                              key: _sectionKeys[i], child: _sections[i]),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            // The page being captured — painted at full A4 logical size (the
            // opaque overlay hides it; clipping never affects toImage).
            Positioned(
              left: 0,
              top: 0,
              child: RepaintBoundary(
                key: _boundaryKey,
                child: SizedBox(
                  width: kA4PageW,
                  height: kA4PageH,
                  child: _pages[_pageIndex],
                ),
              ),
            ),
          Positioned.fill(
            child: Container(
              color: Colors.white,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: _maroon),
                    const SizedBox(height: 16),
                    Text(
                      _measuring
                          ? 'அறிக்கை தயாராகிறது…'
                          : 'அறிக்கை தயாராகிறது… (${_pageIndex + 1}/${_pages.length})',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Export entry points
// ─────────────────────────────────────────────────────────────────────────────

/// Captures the report and shares it as ONE A4 PDF via the system sheet.
/// Returns true on success.
Future<bool> exportCompatReportPdf(
  BuildContext context, {
  required CompatibilityReport report,
  required String reportNumber,
  required String reportDate,
  required String fileName,
}) async {
  final pngs = await CompatReportCaptureScreen.capture(context,
      report: report, reportNumber: reportNumber, reportDate: reportDate);
  if (pngs == null || pngs.isEmpty) return false;
  final doc = pw.Document();
  for (final png in pngs) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
    ));
  }
  await sharePdfBytes(await doc.save(), fileName: fileName);
  return true;
}

/// Captures the report and shares it as PNG image(s) via the system sheet.
/// Returns true on success.
Future<bool> exportCompatReportImages(
  BuildContext context, {
  required CompatibilityReport report,
  required String reportNumber,
  required String reportDate,
  required String baseName,
}) async {
  final pngs = await CompatReportCaptureScreen.capture(context,
      report: report, reportNumber: reportNumber, reportDate: reportDate);
  if (pngs == null || pngs.isEmpty) return false;
  final dir = await getTemporaryDirectory();
  final files = <XFile>[];
  for (var i = 0; i < pngs.length; i++) {
    final f = File('${dir.path}/${baseName}_page${i + 1}.png');
    await f.writeAsBytes(pngs[i]);
    files.add(XFile(f.path));
  }
  await Share.shareXFiles(files);
  return true;
}
