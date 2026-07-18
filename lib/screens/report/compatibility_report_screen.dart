import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/compatibility_report_model.dart';
import '../../models/profile_model.dart';
import '../../providers/astrology_team_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/profile_provider.dart';
import 'compatibility_report_print.dart';

const Color _maroon = AppColors.primary;
const Color _gold = AppColors.gold;
const Color _green = Color(0xFF1B7E3C);
const Color _red = Color(0xFFC62828);
const Color _paper = Color(0xFFFDF8F1);

/// Professional Marriage Compatibility Report — ONE screen, two modes:
///
///  • Employee mode ([employee] = true, report not yet submitted): every
///    பெண்/ஆண் cell is a text input, every பொருத்தம்/தோஷம் verdict is an
///    உண்டு/இல்லை toggle, with Save Draft + Submit Report at the bottom.
///  • User mode (or a submitted report): completely read-only — inputs render
///    as plain text and verdicts as a green tick (உண்டு) / red cross (இல்லை) —
///    with PDF (A4) / Image download.
///
/// The layout is a mobile-width A4-certificate look: no horizontal scrolling,
/// responsive tables, maroon/white/gold theme. Downloads are rasterised from
/// the dedicated A4 print layout in compatibility_report_print.dart.
class CompatibilityReportScreen extends ConsumerStatefulWidget {
  final String requestId;
  final AstrologerRequestModel request;
  final bool employee;
  final bool autoDownload;

  const CompatibilityReportScreen({
    super.key,
    required this.requestId,
    required this.request,
    this.employee = false,
    this.autoDownload = false,
  });

  @override
  ConsumerState<CompatibilityReportScreen> createState() =>
      _CompatibilityReportScreenState();
}

class _CompatibilityReportScreenState
    extends ConsumerState<CompatibilityReportScreen> {
  static const int _nPorutham = 11;
  static const int _nSevvai = 3;
  static const int _nOther = 2;
  static const int _nDasa = 2;

  final List<TextEditingController> _porBride = [];
  final List<TextEditingController> _porGroom = [];
  final List<String> _porMatch = List.filled(_nPorutham, '');
  final List<String> _sevvaiBride = List.filled(_nSevvai, '');
  final List<String> _sevvaiGroom = List.filled(_nSevvai, '');
  final List<String> _otherBride = List.filled(_nOther, '');
  final List<String> _otherGroom = List.filled(_nOther, '');
  final List<TextEditingController> _dasaBride = [];
  final List<TextEditingController> _dasaGroom = [];
  final _explanation = TextEditingController();
  String _finalResult = '';

  bool _hydrated = false;
  bool _busy = false;
  bool _downloadSheetShown = false;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _nPorutham; i++) {
      _porBride.add(TextEditingController());
      _porGroom.add(TextEditingController());
    }
    for (var i = 0; i < _nDasa; i++) {
      _dasaBride.add(TextEditingController());
      _dasaGroom.add(TextEditingController());
    }
    if (widget.autoDownload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showDownloadSheet();
      });
    }
  }

  @override
  void dispose() {
    for (final c in [..._porBride, ..._porGroom, ..._dasaBride, ..._dasaGroom]) {
      c.dispose();
    }
    _explanation.dispose();
    super.dispose();
  }

  void _hydrate(CompatibilityReport? saved) {
    if (_hydrated || saved == null) return;
    _hydrated = true;
    for (var i = 0; i < _nPorutham; i++) {
      _porBride[i].text = saved.poruthamAt(i).bride;
      _porGroom[i].text = saved.poruthamAt(i).groom;
      _porMatch[i] = saved.poruthamAt(i).match;
    }
    for (var i = 0; i < _nSevvai; i++) {
      _sevvaiBride[i] = saved.sevvaiAt(i).bride;
      _sevvaiGroom[i] = saved.sevvaiAt(i).groom;
    }
    for (var i = 0; i < _nOther; i++) {
      _otherBride[i] = saved.otherDoshamAt(i).bride;
      _otherGroom[i] = saved.otherDoshamAt(i).groom;
    }
    for (var i = 0; i < _nDasa; i++) {
      _dasaBride[i].text = saved.dasaAt(i).bride;
      _dasaGroom[i].text = saved.dasaAt(i).groom;
    }
    _explanation.text = saved.explanation;
    _finalResult = saved.finalResult;
  }

  // ── Data helpers ────────────────────────────────────────────────────────────

  AstrologerRequestModel get _request {
    final list = widget.employee
        ? ref.watch(myAssignedRequestsProvider).valueOrNull
        : ref.watch(myMatchAnalysisRequestsProvider).valueOrNull;
    for (final r in list ?? const <AstrologerRequestModel>[]) {
      if (r.id == widget.requestId) return r;
    }
    return widget.request;
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  CompatPerson _fromProfile(ProfileModel? p, String fallbackName) {
    if (p == null) return CompatPerson(name: fallbackName);
    final h = p.horoscope;
    return CompatPerson(
      name: p.fullName.isNotEmpty ? p.fullName : fallbackName,
      dob: _fmtDate(p.dateOfBirth),
      birthTime: h.birthTime,
      birthPlace: h.birthPlace,
      star: h.nakshatra,
      rasi: h.rasi,
    );
  }

  /// The person details shown/snapshotted for one side. While editing (or when
  /// no snapshot exists yet) they come LIVE from the profile; a submitted
  /// report always shows its stored snapshot so it never changes afterwards.
  CompatPerson _person({
    required CompatPerson stored,
    required String? profileId,
    required String fallbackName,
    required bool editable,
  }) {
    if (!editable && stored.name.trim().isNotEmpty) return stored;
    final p = (profileId ?? '').isEmpty
        ? null
        : ref.watch(profileByIdProvider(profileId!)).valueOrNull;
    if (p == null && stored.name.trim().isNotEmpty) return stored;
    return _fromProfile(p, fallbackName);
  }

  CompatibilityReport _collect(
    AstrologerRequestModel r, {
    required String status,
    required CompatPerson bride,
    required CompatPerson groom,
  }) {
    final me = ref.read(currentUserProvider).valueOrNull;
    final employeeName = r.astrologerName.trim().isNotEmpty
        ? r.astrologerName
        : (me?.displayName ?? '');
    final saved = CompatibilityReport.tryFrom(r.compatReport);
    return CompatibilityReport(
      status: status,
      bride: bride,
      groom: groom,
      porutham: [
        for (var i = 0; i < _nPorutham; i++)
          PoruthamRow(
            bride: _porBride[i].text.trim(),
            groom: _porGroom[i].text.trim(),
            match: _porMatch[i],
          ),
      ],
      sevvai: [
        for (var i = 0; i < _nSevvai; i++)
          DoshamRow(bride: _sevvaiBride[i], groom: _sevvaiGroom[i]),
      ],
      otherDosham: [
        for (var i = 0; i < _nOther; i++)
          DoshamRow(bride: _otherBride[i], groom: _otherGroom[i]),
      ],
      dasa: [
        for (var i = 0; i < _nDasa; i++)
          DasaRow(
              bride: _dasaBride[i].text.trim(),
              groom: _dasaGroom[i].text.trim()),
      ],
      explanation: _explanation.text.trim(),
      finalResult: _finalResult,
      employeeName: employeeName,
      submittedAt: status == CompatibilityReport.statusSubmitted
          ? DateTime.now()
          : saved?.submittedAt,
      updatedAt: DateTime.now(),
    );
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String? _validate() {
    if (_porMatch.any((m) => m.isEmpty)) {
      return 'திருமண பொருத்தம்: select உண்டு / இல்லை for every row.';
    }
    if (_sevvaiBride.any((m) => m.isEmpty) ||
        _sevvaiGroom.any((m) => m.isEmpty)) {
      return 'செவ்வாய் தோஷம்: select உண்டு / இல்லை for both பெண் and ஆண்.';
    }
    if (_otherBride.any((m) => m.isEmpty) ||
        _otherGroom.any((m) => m.isEmpty)) {
      return 'பிற தோஷங்கள்: select உண்டு / இல்லை for both பெண் and ஆண்.';
    }
    if (_explanation.text.trim().isEmpty) {
      return 'பொருத்தம் குறிப்பு / விளக்கம் is required.';
    }
    if (_finalResult.isEmpty) {
      return 'இறுதி முடிவு: select பொருத்தம் உண்டு or பொருத்தம் இல்லை.';
    }
    return null;
  }

  Future<void> _saveDraft(CompatPerson bride, CompatPerson groom) async {
    setState(() => _busy = true);
    try {
      final data = _collect(_request,
              status: CompatibilityReport.statusDraft,
              bride: bride,
              groom: groom)
          .toMap();
      await ref
          .read(matchAnalysisControllerProvider.notifier)
          .saveCompatReportDraft(requestId: widget.requestId, data: data);
      if (mounted) _snack('Draft saved. You can continue editing later.');
    } catch (_) {
      if (mounted) _snack('Could not save the draft. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit(CompatPerson bride, CompatPerson groom) async {
    final missing = _validate();
    if (missing != null) {
      _snack(missing);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit Report?'),
        content: const Text(
            'The user will see this report immediately and it can no longer '
            'be edited. Submit now?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _maroon, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final report = _collect(_request,
          status: CompatibilityReport.statusSubmitted,
          bride: bride,
          groom: groom);
      await ref
          .read(matchAnalysisControllerProvider.notifier)
          .submitCompatReport(
            requestId: widget.requestId,
            data: report.toMap(),
            explanation: report.explanation,
          );
      if (!mounted) return;
      _snack('Report submitted. The user can now view it.');
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Could not submit the report. Please try again.');
    }
  }

  // ── Download ───────────────────────────────────────────────────────────────

  void _showDownloadSheet() {
    if (_downloadSheetShown) return;
    final r = _request;
    final saved = CompatibilityReport.tryFrom(r.compatReport);
    if (saved == null || !saved.isSubmitted) return;
    _downloadSheetShown = true;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text('Download Report',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading:
                  const Icon(Icons.picture_as_pdf_outlined, color: _maroon),
              title: const Text('PDF (A4)'),
              subtitle: const Text('Official printable report',
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _export(pdf: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined, color: _maroon),
              title: const Text('Image'),
              subtitle: const Text('PNG image of every page',
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _export(pdf: false);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ).whenComplete(() => _downloadSheetShown = false);
  }

  Future<void> _export({required bool pdf}) async {
    final r = _request;
    final saved = CompatibilityReport.tryFrom(r.compatReport);
    if (saved == null) return;
    final number = CompatibilityReport.reportNumber(widget.requestId);
    final date =
        _fmtDate(saved.submittedAt ?? r.completedAt ?? DateTime.now());
    final bool ok;
    if (pdf) {
      ok = await exportCompatReportPdf(context,
          report: saved,
          reportNumber: number,
          reportDate: date,
          fileName: 'jothida_compatibility_${widget.requestId}.pdf');
    } else {
      ok = await exportCompatReportImages(context,
          report: saved,
          reportNumber: number,
          reportDate: date,
          baseName: 'jothida_compatibility_${widget.requestId}');
    }
    if (!ok && mounted) {
      _snack('Could not prepare the report. Please try again.');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final r = _request;
    final saved = CompatibilityReport.tryFrom(r.compatReport);
    _hydrate(saved);

    final submitted = (saved?.isSubmitted ?? false) ||
        r.status == AstrologerRequestStatus.completed;
    final editable = widget.employee && !submitted;

    final bride = _person(
      stored: saved?.bride ?? const CompatPerson(),
      profileId: r.brideProfileId,
      fallbackName: r.brideName ?? '',
      editable: editable,
    );
    final groom = _person(
      stored: saved?.groom ?? const CompatPerson(),
      profileId: r.groomProfileId,
      fallbackName: r.groomName ?? '',
      editable: editable,
    );

    final number = CompatibilityReport.reportNumber(widget.requestId);
    final date = _fmtDate(
        saved?.submittedAt ?? r.completedAt ?? saved?.updatedAt ?? DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Compatibility Report'),
        backgroundColor: _maroon,
        foregroundColor: Colors.white,
        actions: [
          if (submitted && saved != null && saved.isSubmitted)
            IconButton(
              tooltip: 'Download',
              icon: const Icon(Icons.download_outlined),
              onPressed: _showDownloadSheet,
            ),
        ],
      ),
      bottomNavigationBar: editable
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _busy ? null : () => _saveDraft(bride, groom),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _maroon,
                          side: const BorderSide(color: _maroon),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Save Draft'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _busy ? null : () => _submit(bride, groom),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _maroon,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Submit Report',
                                style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _brandHeader(number, date),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _personCard('மணமகள் (Bride)', bride)),
              const SizedBox(width: 10),
              Expanded(child: _personCard('மணமகன் (Groom)', groom)),
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'திருமண பொருத்தம்',
            legend: editable,
            child: _poruthamTable(editable),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'செவ்வாய் தோஷம்',
            legend: editable,
            child: _doshamTable(
              names: CompatibilityReport.sevvaiNames,
              bride: _sevvaiBride,
              groom: _sevvaiGroom,
              editable: editable,
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'பிற தோஷங்கள்',
            legend: editable,
            child: _doshamTable(
              names: CompatibilityReport.otherDoshamNames,
              bride: _otherBride,
              groom: _otherGroom,
              editable: editable,
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'திசா சந்தி',
            child: _dasaTable(editable),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'பொருத்தம் குறிப்பு / விளக்கம்',
            child: _explanationSection(editable),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'இறுதி முடிவு',
            child: _finalResultSection(editable),
          ),
          if (submitted && saved != null) ...[
            if (saved.isSubmitted) ...[
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _showDownloadSheet,
                icon: const Icon(Icons.download_outlined, size: 20),
                label: const Text('Download Report (PDF / Image)',
                    style:
                        TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _maroon,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _brandHeader(String number, String date) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _maroon.withOpacity(0.35)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/report_logo.png',
                width: 54,
                height: 54,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Image.asset(
                  'assets/images/app_logo.png',
                  width: 54,
                  height: 54,
                  errorBuilder: (_, __, ___) => const Icon(Icons.auto_awesome,
                      color: _maroon, size: 44),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Jothida Matrimony',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _maroon)),
            const SizedBox(height: 2),
            Text('Professional Marriage Compatibility Report',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: Colors.grey[700])),
            const SizedBox(height: 10),
            Container(height: 2.2, color: _maroon),
            const SizedBox(height: 2),
            Container(height: 1, color: _gold),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Report No: $number',
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600)),
                Text('Report Date: $date',
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      );

  Widget _personCard(String title, CompatPerson p) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _maroon.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: _maroon,
              padding: const EdgeInsets.symmetric(vertical: 7),
              alignment: Alignment.center,
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _personField('Name', p.name),
                  _personField('Date of Birth', p.dob),
                  _personField('Time of Birth', p.birthTime),
                  _personField('Birth Place', p.birthPlace),
                  _personField('Star', p.star),
                  _personField('Rasi', p.rasi),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _personField(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 9.5, color: Colors.grey[600])),
            Text(value.trim().isEmpty ? '—' : value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _sectionCard({
    required String title,
    required Widget child,
    bool legend = false,
  }) =>
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _maroon.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: _maroon,
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
            if (legend)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: _green),
                    const SizedBox(width: 3),
                    Text('உண்டு',
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey[700])),
                    const SizedBox(width: 14),
                    const Icon(Icons.cancel, size: 14, color: _red),
                    const SizedBox(width: 3),
                    Text('இல்லை',
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey[700])),
                  ],
                ),
              ),
            Padding(padding: const EdgeInsets.all(10), child: child),
          ],
        ),
      );

  TableBorder get _border =>
      TableBorder.all(color: _maroon.withOpacity(0.25), width: 0.7);

  Widget _headCell(String text) => Container(
        color: _maroon.withOpacity(0.92),
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        alignment: Alignment.center,
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      );

  Widget _textCell(String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
        child: Text(v.trim().isEmpty ? '—' : v,
            textAlign: bold ? TextAlign.left : TextAlign.center,
            style: TextStyle(
                fontSize: 11,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      );

  Widget _fieldCell(TextEditingController c, {String hint = ''}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 3),
        child: TextField(
          controller: c,
          maxLines: null,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(fontSize: 10.5, color: Colors.grey[400]),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            enabledBorder: UnderlineInputBorder(
                borderSide:
                    BorderSide(color: _maroon.withOpacity(0.25), width: 0.8)),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: _maroon, width: 1.2)),
          ),
        ),
      );

  /// Compact உண்டு / இல்லை toggle — behaves like a radio pair (single select).
  Widget _triToggle(String value, ValueChanged<String> onChanged) {
    Widget dot({required bool yes}) {
      final selected =
          value == (yes ? CompatAnswer.yes : CompatAnswer.no);
      final color = yes ? _green : _red;
      return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () =>
            onChanged(yes ? CompatAnswer.yes : CompatAnswer.no),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? color : Colors.transparent,
            border: Border.all(
                color: selected ? color : Colors.grey.shade400, width: 1.2),
          ),
          child: Icon(yes ? Icons.check : Icons.close,
              size: 15, color: selected ? Colors.white : Colors.grey.shade400),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [dot(yes: true), const SizedBox(width: 7), dot(yes: false)],
      ),
    );
  }

  /// Read-only verdict: green tick உண்டு / red cross இல்லை.
  Widget _answerView(String v) {
    if (v != CompatAnswer.yes && v != CompatAnswer.no) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('—',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey)),
      );
    }
    final yes = v == CompatAnswer.yes;
    final color = yes ? _green : _red;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(yes ? Icons.check_circle : Icons.cancel, size: 17, color: color),
          const SizedBox(height: 1),
          Text(yes ? 'உண்டு' : 'இல்லை',
              style: TextStyle(
                  fontSize: 8.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  TableRow _zebra(int i, List<Widget> cells) => TableRow(
        decoration: BoxDecoration(color: i.isOdd ? _paper : Colors.white),
        children: [
          for (final c in cells)
            TableCell(
                verticalAlignment: TableCellVerticalAlignment.middle,
                child: c),
        ],
      );

  Widget _poruthamTable(bool editable) => Table(
        border: _border,
        columnWidths: const {
          0: FixedColumnWidth(24),
          1: FlexColumnWidth(1.15),
          2: FlexColumnWidth(1),
          3: FlexColumnWidth(1),
          4: FixedColumnWidth(70),
        },
        children: [
          TableRow(children: [
            _headCell('No'),
            _headCell('பொருத்தம்'),
            _headCell('பெண்'),
            _headCell('ஆண்'),
            _headCell('பொருத்தம்'),
          ]),
          for (var i = 0; i < _nPorutham; i++)
            _zebra(i, [
              _textCell('${i + 1}'),
              _textCell(CompatibilityReport.poruthamNames[i], bold: true),
              editable
                  ? _fieldCell(_porBride[i])
                  : _textCell(_porBride[i].text),
              editable
                  ? _fieldCell(_porGroom[i])
                  : _textCell(_porGroom[i].text),
              editable
                  ? _triToggle(_porMatch[i],
                      (v) => setState(() => _porMatch[i] = v))
                  : _answerView(_porMatch[i]),
            ]),
        ],
      );

  Widget _doshamTable({
    required List<String> names,
    required List<String> bride,
    required List<String> groom,
    required bool editable,
  }) =>
      Table(
        border: _border,
        columnWidths: const {
          0: FlexColumnWidth(1.4),
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
              _textCell(names[i], bold: true),
              editable
                  ? _triToggle(
                      bride[i], (v) => setState(() => bride[i] = v))
                  : _answerView(bride[i]),
              editable
                  ? _triToggle(
                      groom[i], (v) => setState(() => groom[i] = v))
                  : _answerView(groom[i]),
            ]),
        ],
      );

  Widget _dasaTable(bool editable) => Table(
        border: _border,
        columnWidths: const {
          0: FlexColumnWidth(1.2),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1),
        },
        children: [
          TableRow(children: [
            _headCell('விவரம்'),
            _headCell('பெண்'),
            _headCell('ஆண்'),
          ]),
          for (var i = 0; i < _nDasa; i++)
            _zebra(i, [
              _textCell(CompatibilityReport.dasaNames[i], bold: true),
              editable
                  ? _fieldCell(_dasaBride[i])
                  : _textCell(_dasaBride[i].text),
              editable
                  ? _fieldCell(_dasaGroom[i])
                  : _textCell(_dasaGroom[i].text),
            ]),
        ],
      );

  Widget _explanationSection(bool editable) {
    if (editable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Explain why compatibility is / is not available, important '
            'observations, suggestions and astrological remarks. The user '
            'sees this exactly as entered.',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _explanation,
            minLines: 6,
            maxLines: 14,
            style: const TextStyle(fontSize: 13, height: 1.5),
            decoration: InputDecoration(
              hintText: 'பொருத்தம் குறித்த விளக்கத்தை இங்கே எழுதவும்…',
              filled: true,
              fillColor: AppColors.scaffoldBg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
          ),
        ],
      );
    }
    final text = _explanation.text.trim();
    return Text(
      text.isEmpty ? '—' : text,
      style: const TextStyle(fontSize: 13, height: 1.6),
      textAlign: TextAlign.justify,
    );
  }

  Widget _finalResultSection(bool editable) {
    if (editable) {
      Widget option(String label, String value, Color color) {
        final selected = _finalResult == value;
        return Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _finalResult = value),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              decoration: BoxDecoration(
                color: selected ? color.withOpacity(0.08) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: selected ? color : Colors.grey.shade300,
                    width: selected ? 1.4 : 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: selected ? color : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: selected ? color : Colors.grey[700])),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Row(
        children: [
          option('பொருத்தம் உண்டு', CompatAnswer.yes, _green),
          const SizedBox(width: 10),
          option('பொருத்தம் இல்லை', CompatAnswer.no, _red),
        ],
      );
    }

    final yes = _finalResult == CompatAnswer.yes;
    final no = _finalResult == CompatAnswer.no;
    final color = yes
        ? _green
        : no
            ? _red
            : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (yes || no)
            Icon(yes ? Icons.check_circle : Icons.cancel,
                size: 22, color: color),
          if (yes || no) const SizedBox(width: 8),
          Text(
            yes
                ? 'பொருத்தம் உண்டு'
                : no
                    ? 'பொருத்தம் இல்லை'
                    : '—',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

}
