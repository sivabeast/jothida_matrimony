import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds the professional single-file PDF for a horoscope-analysis report
/// whose content was submitted as text and/or images (spec: app logo, report
/// title, user name, employee name, report date, description, images, footer).
///
/// Pure generation — no I/O with the UI. Callers share/save the returned
/// bytes (e.g. via `Printing.sharePdf`).
class ReportPdfBuilder {
  static const _maroon = PdfColor.fromInt(0xFF8B0000);
  static const _gold = PdfColor.fromInt(0xFFC9A227);
  static const _grey = PdfColor.fromInt(0xFF666666);

  /// Downloads every image URL, skipping failures so one broken attachment
  /// never produces a broken PDF.
  static Future<List<Uint8List>> _fetchImages(List<String> urls) async {
    final out = <Uint8List>[];
    for (final url in urls) {
      try {
        final res =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          out.add(res.bodyBytes);
        }
      } catch (e) {
        debugPrint('[ReportPdf] image skipped ($url): $e');
      }
    }
    return out;
  }

  /// Generates the report PDF and returns its bytes.
  static Future<Uint8List> build({
    required String reportTitle,
    required String userName,
    required String employeeName,
    required DateTime reportDate,
    required String description,
    List<String> imageUrls = const [],
    String appName = 'Jothida Matrimony',
  }) async {
    // Poppins for Latin text with Noto Sans Tamil as fallback so Tamil report
    // text renders correctly instead of as tofu boxes.
    final regular =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Poppins-Regular.ttf'));
    final bold =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Poppins-SemiBold.ttf'));
    final tamil = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansTamil-Regular.ttf'));
    final tamilBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansTamil-Bold.ttf'));

    Uint8List? logoBytes;
    try {
      logoBytes =
          (await rootBundle.load('assets/images/app_logo.png')).buffer.asUint8List();
    } catch (_) {
      logoBytes = null; // logo missing must never block report generation
    }
    final logo = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    final images = await _fetchImages(imageUrls);

    String fmtDate(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        fontFallback: [tamil, tamilBold],
      ),
    );

    pw.Widget metaRow(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 130,
                child: pw.Text(label,
                    style: const pw.TextStyle(fontSize: 10.5, color: _grey)),
              ),
              pw.Expanded(
                child: pw.Text(value.isEmpty ? '—' : value,
                    style: pw.TextStyle(
                        fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 40),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null)
                  pw.Container(
                    width: 40,
                    height: 40,
                    margin: const pw.EdgeInsets.only(right: 10),
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(appName,
                        style: pw.TextStyle(
                            fontSize: 15,
                            fontWeight: pw.FontWeight.bold,
                            color: _maroon)),
                    pw.Text('Horoscope Analysis Report',
                        style:
                            const pw.TextStyle(fontSize: 9.5, color: _grey)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Container(height: 2, color: _gold),
            pw.SizedBox(height: 14),
          ],
        ),
        footer: (ctx) => pw.Column(
          children: [
            pw.Container(height: 1, color: PdfColors.grey300),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('$appName • Generated on ${fmtDate(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 8.5, color: _grey)),
                pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8.5, color: _grey)),
              ],
            ),
          ],
        ),
        build: (ctx) => [
          // Title band
          pw.Container(
            width: double.infinity,
            padding:
                const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFFDF6EC),
              border: pw.Border.all(color: _gold, width: 0.8),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(reportTitle,
                style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: _maroon)),
          ),
          pw.SizedBox(height: 14),
          // Meta block
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                metaRow('Member Name', userName),
                metaRow('Prepared By', employeeName),
                metaRow('Report Date', fmtDate(reportDate)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          if (description.trim().isNotEmpty) ...[
            pw.Text('Analysis',
                style: pw.TextStyle(
                    fontSize: 12.5,
                    fontWeight: pw.FontWeight.bold,
                    color: _maroon)),
            pw.SizedBox(height: 6),
            pw.Text(description.trim(),
                style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 3)),
            pw.SizedBox(height: 16),
          ],
          if (images.isNotEmpty) ...[
            pw.Text('Attachments',
                style: pw.TextStyle(
                    fontSize: 12.5,
                    fontWeight: pw.FontWeight.bold,
                    color: _maroon)),
            pw.SizedBox(height: 8),
            for (final bytes in images)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    border:
                        pw.Border.all(color: PdfColors.grey300, width: 0.7),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Image(
                    pw.MemoryImage(bytes),
                    fit: pw.BoxFit.contain,
                    height: 380,
                  ),
                ),
              ),
          ],
        ],
      ),
    );

    return doc.save();
  }
}
