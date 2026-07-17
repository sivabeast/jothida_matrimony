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
/// shared directly as images), so the download looks exactly like an official
/// printed certificate.

// A4 @ 96dpi logical pixels.
const double kA4PageW = 794;
const double kA4PageH = 1123;

// Conservative height available for body content inside the framed page
// (below the branding header, above the footer). Used to auto-split a long
// explanation across pages.
const double _kBodyH = 880;
// Width available to the explanation text (page frame + block padding).
const double _kExplW = 680;
// Height reserved for the final-result band + signature block.
const double _kTailH = 230;

const TextStyle _kExplStyle =
    TextStyle(fontSize: 10.5, height: 1.55, color: Color(0xFF262626));

const Color _maroon = AppColors.primary;
const Color _gold = AppColors.gold;
const Color _paper = Color(0xFFFDF8F1);

String _dash(String v) => v.trim().isEmpty ? '—' : v.trim();

// ─────────────────────────────────────────────────────────────────────────────
// Page building
// ─────────────────────────────────────────────────────────────────────────────

/// Builds the full list of A4 page widgets for [report]. The explanation is
/// automatically split so the report spans as many pages as it needs, each with
/// the same branding header and footer.
List<Widget> buildCompatPrintPages({
  required CompatibilityReport report,
  required String reportNumber,
  required String reportDate,
}) {
  final bodies = <List<Widget>>[];

  // Page 1 — couple details + திருமண பொருத்தம் table.
  bodies.add([
    _coupleRow(report),
    const SizedBox(height: 16),
    _sectionTitle('திருமண பொருத்தம்'),
    const SizedBox(height: 8),
    _poruthamTable(report),
  ]);

  // Page 2 — the three dosham / dasa tables.
  final page2 = <Widget>[
    _sectionTitle('செவ்வாய் தோஷம்'),
    const SizedBox(height: 8),
    _doshamTable(CompatibilityReport.sevvaiNames,
        [for (var i = 0; i < 3; i++) report.sevvaiAt(i)]),
    const SizedBox(height: 18),
    _sectionTitle('பிற தோஷங்கள்'),
    const SizedBox(height: 8),
    _doshamTable(CompatibilityReport.otherDoshamNames,
        [for (var i = 0; i < 2; i++) report.otherDoshamAt(i)]),
    const SizedBox(height: 18),
    _sectionTitle('திசா சந்தி'),
    const SizedBox(height: 8),
    _dasaTable(report),
  ];

  final tail = <Widget>[
    const SizedBox(height: 20),
    _sectionTitle('இறுதி முடிவு'),
    const SizedBox(height: 10),
    _finalResultBand(report.finalResult),
    const SizedBox(height: 26),
    _signatureRow(report, reportDate),
  ];

  final expl = report.explanation.trim();
  if (expl.isEmpty) {
    bodies.add([...page2, ...tail]);
  } else {
    bodies.add(page2);
    // Explanation gets its own page(s); split by measured line heights.
    final chunks =
        _splitTextForPages(expl, _kExplStyle, _kExplW, _kBodyH - 90, _kBodyH - 40);
    for (var i = 0; i < chunks.length; i++) {
      bodies.add([
        if (i == 0) ...[
          _sectionTitle('பொருத்தம் குறிப்பு / விளக்கம்'),
          const SizedBox(height: 8),
        ],
        _explanationBlock(chunks[i]),
      ]);
    }
    final lastChunkH = _textHeight(chunks.last, _kExplStyle, _kExplW) +
        (chunks.length == 1 ? 90 : 40);
    if (lastChunkH + _kTailH <= _kBodyH) {
      bodies.last.addAll(tail);
    } else {
      bodies.add(tail);
    }
  }

  return [
    for (var i = 0; i < bodies.length; i++)
      _a4Page(
        body: bodies[i],
        pageNo: i + 1,
        pageCount: bodies.length,
        reportNumber: reportNumber,
        reportDate: reportDate,
      ),
  ];
}

/// One framed A4 page: double certificate border, branding header, body,
/// footer with page numbers. Body overflow is clipped as a last-resort guard —
/// the explanation splitter keeps real content inside the page.
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

Widget _printHeader(String reportNumber, String reportDate) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/images/app_logo.png',
                width: 58,
                height: 58,
                errorBuilder: (_, __, ___) => const Icon(Icons.auto_awesome,
                    color: _maroon, size: 48),
              ),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Jothida Matrimony',
                    style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: _maroon)),
                const SizedBox(height: 2),
                Text('Professional Marriage Compatibility Report',
                    style: TextStyle(fontSize: 10.5, color: Colors.grey[800])),
                const SizedBox(height: 5),
                Text('Report No: $reportNumber    |    Report Date: $reportDate',
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700])),
              ],
            ),
          ],
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
      decoration:
          BoxDecoration(color: i.isOdd ? _paper : Colors.white),
      children: [
        for (final c in cells)
          TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: c),
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

Widget _signatureRow(CompatibilityReport r, String reportDate) => Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('தயாரித்தவர் / Prepared By',
                  style: TextStyle(fontSize: 9, color: Colors.grey[700])),
              const SizedBox(height: 3),
              Text(_dash(r.employeeName),
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text('Date: $reportDate',
                  style: TextStyle(fontSize: 9, color: Colors.grey[700])),
            ],
          ),
        ),
        Column(
          children: [
            Container(
              width: 160,
              height: 64,
              decoration: BoxDecoration(
                border: Border.all(color: _maroon.withOpacity(0.4), width: 0.8),
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text('முத்திரை / கையொப்பம்',
                style: TextStyle(fontSize: 9, color: Colors.grey[700])),
          ],
        ),
      ],
    );

// ─────────────────────────────────────────────────────────────────────────────
// Explanation page-splitting
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
// Capture + export
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen route that paints each A4 page at its real logical size behind
/// an opaque "preparing" overlay, captures every page as a PNG, then pops with
/// the page images (null on failure).
class CompatReportCaptureScreen extends StatefulWidget {
  final List<Widget> pages;
  const CompatReportCaptureScreen({super.key, required this.pages});

  static Future<List<Uint8List>?> capture(
          BuildContext context, List<Widget> pages) =>
      Navigator.of(context).push<List<Uint8List>>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CompatReportCaptureScreen(pages: pages),
      ));

  @override
  State<CompatReportCaptureScreen> createState() =>
      _CompatReportCaptureScreenState();
}

class _CompatReportCaptureScreenState extends State<CompatReportCaptureScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  int _index = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_started) return;
    _started = true;
    final out = <Uint8List>[];
    try {
      for (var i = 0; i < widget.pages.length; i++) {
        setState(() => _index = i);
        // Two frames + a short pause so the asset logo and Tamil glyph shaping
        // are fully painted before rasterising.
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
                child: widget.pages[_index],
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
                      'அறிக்கை தயாராகிறது… (${_index + 1}/${widget.pages.length})',
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

/// Captures [pages] and shares them as ONE A4 PDF via the system sheet.
/// Returns true on success.
Future<bool> exportCompatReportPdf(
  BuildContext context,
  List<Widget> pages, {
  required String fileName,
}) async {
  final pngs = await CompatReportCaptureScreen.capture(context, pages);
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

/// Captures [pages] and shares them as PNG image(s) via the system sheet.
/// Returns true on success.
Future<bool> exportCompatReportImages(
  BuildContext context,
  List<Widget> pages, {
  required String baseName,
}) async {
  final pngs = await CompatReportCaptureScreen.capture(context, pages);
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
