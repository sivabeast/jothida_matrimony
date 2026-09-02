import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/compatibility_report_model.dart';
import '../../widgets/common/app_logo.dart';
import 'compatibility_report_print.dart';

const Color _maroon = AppColors.primary;
const Color _gold = AppColors.gold;
const Color _green = Color(0xFF1B7E3C);
const Color _red = Color(0xFFC62828);
const Color _paper = Color(0xFFFDF8F1);

/// A complete, realistic **SAMPLE** Marriage Compatibility Report, shown free
/// and before any payment (spec §3).
///
/// The point is trust, not decoration: a member about to be asked for ₹199
/// should be able to see the actual shape of what arrives — the same maroon /
/// gold certificate, the same eleven poruthams, the same dosham verdicts, the
/// same astrologer's conclusion — filled with invented data for "பிரியா" and
/// "கார்த்திக்".
///
/// It is labelled SAMPLE in four independent places (app bar, ribbon over the
/// certificate header, a notice card, and the exported file's report number) so
/// there is no path by which somebody mistakes it for their own report.
///
/// Deliberately NOT built on top of [CompatibilityReport]'s live screen: that
/// one reads providers, a request id and a saved document. This is a static
/// page with zero data dependencies, which is what lets a signed-out guest open
/// it.
class SampleCompatibilityReportScreen extends StatefulWidget {
  /// Optional "buy it" action shown at the bottom. Null (the default) hides the
  /// CTA — used when the screen is opened from a page that already has one.
  final VoidCallback? onRequestReport;

  /// The price shown on that CTA, e.g. "₹199".
  final String? priceText;

  const SampleCompatibilityReportScreen({
    super.key,
    this.onRequestReport,
    this.priceText,
  });

  @override
  State<SampleCompatibilityReportScreen> createState() =>
      _SampleCompatibilityReportScreenState();
}

class _SampleCompatibilityReportScreenState
    extends State<SampleCompatibilityReportScreen> {
  bool _downloading = false;

  /// Downloads the sample as the same A4 PDF a real report produces, so the
  /// preview promises exactly what is delivered (spec §3B).
  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    final l10n = context.l10n;
    try {
      final ok = await exportCompatReportPdf(
        context,
        report: sampleCompatibilityReport(),
        // The report number itself says SAMPLE, so a file that leaves the phone
        // still announces what it is.
        reportNumber: 'JM-SAMPLE',
        reportDate: _sampleDate,
        fileName: 'jothida_sample_compatibility_report.pdf',
      );
      if (!mounted) return;
      if (!ok) _snack(l10n.couldNotPrepareSampleReport);
    } catch (_) {
      if (mounted) _snack(l10n.couldNotPrepareSampleReport);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final report = sampleCompatibilityReport();

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: _maroon,
        foregroundColor: Colors.white,
        title: Text(l10n.sampleReportTitle,
            maxLines: 2, style: const TextStyle(fontSize: 16, height: 1.2)),
        actions: [
          IconButton(
            tooltip: l10n.downloadSampleReport,
            onPressed: _downloading ? null : _download,
            icon: _downloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Colors.white))
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      bottomNavigationBar: widget.onRequestReport == null
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 12),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.getYourCompatibilityReport,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onRequestReport!.call();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _maroon,
                        foregroundColor: Colors.white,
                        // Padding, not a fixed height — a two-line Tamil label
                        // must grow the button, not spill out of it (§5A).
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                          l10n.payAndRequestReport(widget.priceText ?? '₹199'),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: const TextStyle(
                              fontSize: 14.5,
                              height: 1.25,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _sampleNotice(),
          const SizedBox(height: 12),
          _certificate(report),
          const SizedBox(height: 14),
          _sampleFooterNotice(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── SAMPLE labelling ───────────────────────────────────────────────────────

  Widget _sampleNotice() {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 19, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.sampleReportBadge,
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: AppColors.warning)),
                const SizedBox(height: 4),
                Text(l10n.sampleReportNotice,
                    style: TextStyle(
                        fontSize: 12, height: 1.55, color: Colors.grey[800])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sampleFooterNotice() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(context.l10n.sampleReportFooterNotice,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11.5, height: 1.55, color: Colors.grey[700])),
      );

  // ── The certificate ────────────────────────────────────────────────────────

  Widget _certificate(CompatibilityReport r) => Column(
        children: [
          _brandHeader(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _personCard(
                      context.l10n.brideRole, r.bride, const Color(0xFFC2185B))),
              const SizedBox(width: 10),
              Expanded(
                  child: _personCard(
                      context.l10n.groomRole, r.groom, AppColors.info)),
            ],
          ),
          const SizedBox(height: 12),
          _scoreCard(),
          const SizedBox(height: 12),
          _section(context.l10n.sampleSectionPorutham, _poruthamTable(r)),
          const SizedBox(height: 12),
          _section(context.l10n.sampleSectionSevvai,
              _doshamTable(CompatibilityReport.sevvaiNames, r.sevvai)),
          const SizedBox(height: 12),
          _section(context.l10n.sampleSectionOtherDosham,
              _doshamTable(CompatibilityReport.otherDoshamNames, r.otherDosham)),
          const SizedBox(height: 12),
          _section(context.l10n.sampleSectionDasa,
              _doshamTable(CompatibilityReport.dasaNames, r.dasa)),
          const SizedBox(height: 12),
          _section(context.l10n.sampleSectionObservations,
              _bullets(_sampleObservations(context))),
          const SizedBox(height: 12),
          _section(context.l10n.sampleSectionRemedies,
              _bullets(_sampleRemedies(context))),
          const SizedBox(height: 12),
          _section(context.l10n.sampleSectionMuhurtham,
              _bullets(_sampleMuhurtham(context))),
          const SizedBox(height: 12),
          _section(
            context.l10n.sampleSectionConclusion,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.explanation,
                    style: const TextStyle(fontSize: 13, height: 1.7)),
                const SizedBox(height: 12),
                _finalVerdict(r.finalResult == CompatAnswer.yes),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(r.employeeName,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(context.l10n.astrologerRemarksBy,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[600])),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _brandHeader() => Stack(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            decoration: BoxDecoration(
              color: _paper,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _gold.withValues(alpha: 0.65), width: 2),
            ),
            child: Column(
              children: [
                const AppLogo(size: 52),
                const SizedBox(height: 10),
                Text(context.l10n.compatibilityReportCertificateTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15.5,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                        color: _maroon)),
                const SizedBox(height: 8),
                // Wrap so the number and date stack instead of overflowing when
                // the Tamil labels are long.
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    Text('${context.l10n.reportNumberLabel}: JM-SAMPLE',
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey[700])),
                    Text('${context.l10n.dateLabel}: $_sampleDate',
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey[700])),
                  ],
                ),
              ],
            ),
          ),
          // The ribbon: unmissable, and it sits ON the certificate rather than
          // beside it, so a screenshot of the report still carries the label.
          Positioned(
            top: 10,
            right: 0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: const BoxDecoration(
                color: AppColors.warning,
                borderRadius:
                    BorderRadius.horizontal(left: Radius.circular(20)),
              ),
              child: Text(context.l10n.sampleReportBadge,
                  style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                      color: Colors.white)),
            ),
          ),
        ],
      );

  Widget _personCard(String title, CompatPerson p, Color accent) {
    final l10n = context.l10n;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey[600])),
              Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(
                      fontSize: 12, height: 1.4, fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(title,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: accent)),
          ),
          const SizedBox(height: 8),
          row(l10n.fullName, p.name),
          row(l10n.dateOfBirth, p.dob),
          row(l10n.timeOfBirth, p.birthTime),
          row(l10n.placeOfBirthLabel, p.birthPlace),
          row(l10n.nakshatra, p.star),
          row(l10n.rasi, p.rasi),
        ],
      ),
    );
  }

  /// The headline number. Shown as a labelled bar rather than a gauge so it
  /// reads identically at any width and in any language.
  Widget _scoreCard() {
    final l10n = context.l10n;
    const score = 8;
    const outOf = 11;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.compatibilityScoreLabel,
                  style: const TextStyle(
                      fontSize: 13, height: 1.35, fontWeight: FontWeight.w700)),
              const Text('$score / $outOf',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _green)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: score / outOf,
              minHeight: 9,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(_green),
            ),
          ),
          const SizedBox(height: 9),
          Text(l10n.sampleScoreCaption,
              style: TextStyle(
                  fontSize: 11.5, height: 1.55, color: Colors.grey[700])),
        ],
      ),
    );
  }

  Widget _section(String title, Widget child) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _gold.withValues(alpha: 0.40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: const BoxDecoration(
                color: _maroon,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(12.5)),
              ),
              child: Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.all(13),
              child: child,
            ),
          ],
        ),
      );

  Widget _poruthamTable(CompatibilityReport r) {
    final l10n = context.l10n;
    return Table(
      border: TableBorder.all(color: Colors.grey[300]!, width: 0.8),
      columnWidths: const {
        0: FlexColumnWidth(2.3),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(2),
        3: FlexColumnWidth(1.3),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: _maroon.withValues(alpha: 0.07)),
          children: [
            _th(l10n.poruthamLabel),
            _th(l10n.brideRole),
            _th(l10n.groomRole),
            _th(l10n.resultLabel),
          ],
        ),
        for (var i = 0; i < CompatibilityReport.poruthamNames.length; i++)
          TableRow(children: [
            _td(CompatibilityReport.poruthamNames[i], bold: true),
            _td(r.poruthamAt(i).bride),
            _td(r.poruthamAt(i).groom),
            _verdictCell(r.poruthamAt(i).match == CompatAnswer.yes),
          ]),
      ],
    );
  }

  Widget _doshamTable(List<String> names, List<DoshamRow> rows) {
    final l10n = context.l10n;
    DoshamRow at(int i) => i < rows.length ? rows[i] : const DoshamRow();
    return Table(
      border: TableBorder.all(color: Colors.grey[300]!, width: 0.8),
      columnWidths: const {
        0: FlexColumnWidth(2.6),
        1: FlexColumnWidth(1.6),
        2: FlexColumnWidth(1.6),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: _maroon.withValues(alpha: 0.07)),
          children: [_th(''), _th(l10n.brideRole), _th(l10n.groomRole)],
        ),
        for (var i = 0; i < names.length; i++)
          TableRow(children: [
            _td(names[i], bold: true),
            _verdictCell(at(i).bride == CompatAnswer.yes),
            _verdictCell(at(i).groom == CompatAnswer.yes),
          ]),
      ],
    );
  }

  Widget _th(String t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 11,
                height: 1.3,
                fontWeight: FontWeight.w800,
                color: _maroon)),
      );

  Widget _td(String t, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(t.isEmpty ? '—' : t,
            style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      );

  Widget _verdictCell(bool yes) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(yes ? Icons.check_circle : Icons.cancel,
                size: 15, color: yes ? _green : _red),
            const SizedBox(width: 4),
            Flexible(
              child: Text(yes ? 'உண்டு' : 'இல்லை',
                  style: TextStyle(
                      fontSize: 10.5,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: yes ? _green : _red)),
            ),
          ],
        ),
      );

  Widget _bullets(List<String> lines) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(Icons.circle, size: 6, color: _gold),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(line,
                        style: const TextStyle(fontSize: 12.5, height: 1.65)),
                  ),
                ],
              ),
            ),
        ],
      );

  Widget _finalVerdict(bool yes) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: (yes ? _green : _red).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: (yes ? _green : _red).withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(yes ? Icons.verified : Icons.cancel,
                size: 20, color: yes ? _green : _red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(yes ? 'பொருத்தம் உண்டு' : 'பொருத்தம் இல்லை',
                  style: TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                      color: yes ? _green : _red)),
            ),
          ],
        ),
      );
}

/// A fixed date, so the sample never looks stale-dated or, worse, like a real
/// report generated today.
const String _sampleDate = '12/06/2026';

List<String> _sampleObservations(BuildContext c) => [
      c.l10n.sampleObservation1,
      c.l10n.sampleObservation2,
      c.l10n.sampleObservation3,
    ];

List<String> _sampleRemedies(BuildContext c) => [
      c.l10n.sampleRemedy1,
      c.l10n.sampleRemedy2,
    ];

List<String> _sampleMuhurtham(BuildContext c) => [
      c.l10n.sampleMuhurtham1,
      c.l10n.sampleMuhurtham2,
    ];

/// The demo report itself — invented people, invented chart values.
///
/// Kept as a function (not a const) so the exported PDF and the on-screen page
/// are built from the SAME source and cannot drift apart.
CompatibilityReport sampleCompatibilityReport() {
  const yes = CompatAnswer.yes;
  const no = CompatAnswer.no;

  // 8 of 11 poruthams agree — a realistic "good, not perfect" match, which is
  // far more representative of a real report than a flawless one.
  const matches = [yes, yes, yes, no, yes, yes, yes, no, yes, no, yes];
  const brideValues = [
    'ரோகிணி',
    'தேவ கணம்',
    'உண்டு',
    'உண்டு',
    'சர்ப்பம்',
    'ரிஷபம்',
    'சுக்கிரன்',
    'உண்டு',
    'பாத ரஜ்ஜு',
    'இல்லை',
    'ஆதி நாடி',
  ];
  const groomValues = [
    'உத்திரம்',
    'மனித கணம்',
    'உண்டு',
    'உண்டு',
    'கௌ',
    'கன்னி',
    'புதன்',
    'உண்டு',
    'சிரோ ரஜ்ஜு',
    'இல்லை',
    'மத்திய நாடி',
  ];

  return CompatibilityReport(
    status: CompatibilityReport.statusSubmitted,
    bride: const CompatPerson(
      name: 'பிரியா தர்ஷினி',
      dob: '14 Aug 1999',
      birthTime: '06:45 AM',
      birthPlace: 'Salem, Salem, Tamil Nadu',
      star: 'ரோகிணி',
      rasi: 'ரிஷபம்',
    ),
    groom: const CompatPerson(
      name: 'கார்த்திக் ராஜா',
      dob: '02 Mar 1996',
      birthTime: '09:20 PM',
      birthPlace: 'Erode, Erode, Tamil Nadu',
      star: 'உத்திரம்',
      rasi: 'கன்னி',
    ),
    porutham: [
      for (var i = 0; i < CompatibilityReport.poruthamNames.length; i++)
        PoruthamRow(
            bride: brideValues[i], groom: groomValues[i], match: matches[i]),
    ],
    sevvai: const [
      DoshamRow(bride: no, groom: no),
      DoshamRow(bride: yes, groom: yes),
      DoshamRow(bride: no, groom: no),
    ],
    otherDosham: const [
      DoshamRow(bride: no, groom: no),
      DoshamRow(bride: no, groom: yes),
    ],
    dasa: const [
      DoshamRow(bride: no, groom: no),
      DoshamRow(bride: yes, groom: yes),
    ],
    explanation:
        'இரு ஜாதகங்களிலும் 11 பொருத்தங்களில் 8 பொருத்தங்கள் அமைந்துள்ளன. '
        'தினம், கணம், மகேந்திரம், யோனி, ராசி மற்றும் ராசி அதிபதி பொருத்தங்கள் '
        'சிறப்பாக உள்ளன — இது தாம்பத்திய ஒற்றுமைக்கும், குடும்ப நல்லிணக்கத்திற்கும் '
        'உகந்தது. ரஜ்ஜு பொருத்தம் அமையவில்லை; இருப்பினும் இரு ஜாதகங்களிலும் '
        'செவ்வாய் சந்திரனுக்கு சமமாக அமைந்திருப்பதால் தோஷம் பரிகாரமாகிறது. '
        'நாடி பொருத்தம் அமைந்திருப்பது சந்ததி வளத்திற்கு நல்லது. மொத்தத்தில் '
        'இந்த ஜாதகங்கள் திருமணத்திற்கு உகந்தவை.',
    finalResult: CompatAnswer.yes,
    employeeName: 'ஜோதிடர் R. முருகன்',
    submittedAt: DateTime(2026, 6, 12),
    updatedAt: DateTime(2026, 6, 12),
  );
}
