import 'dart:async';
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
import '../../models/profile_model.dart';
import '../../models/user_model.dart';
import '../../widgets/common/rasi_chart.dart';

/// A4 print layout + PDF/Image export of a MEMBER'S FULL PROFILE, for the
/// admin User Details screen (§13).
///
/// Modelled on the Marriage Compatibility Report exporter
/// (`compatibility_report_print.dart`): every page is laid out as REAL Flutter
/// widgets at a fixed A4 logical size and rasterised with
/// [RepaintBoundary.toImage] — Flutter's text engine shapes Tamil correctly,
/// which the `pdf` package's own TTF renderer does not guarantee. The captured
/// PNG pages are embedded 1:1 into an A4 PDF (or shared directly as images).
///
/// Pagination is measurement-driven: every section card is laid out offscreen
/// at the real content width to get its true height, then the cards FLOW onto
/// pages. Each card (title + rows) is atomic — if it does not fit in the space
/// left on the current page it starts a fresh page.
///
/// Page 1 carries the full branded header (logo + app name + "Member Profile");
/// later pages use a slim one-line header. EVERY page footer shows the
/// generation date-time, the admin who generated it, and "Page X of Y".

// A4 @ 96dpi logical pixels.
const double _kPageW = 794;
const double _kPageH = 1123;

// Width available to page content inside the framed page:
// 794 − 2×16 (page pad) − 2×1.4 (outer border) − 2×3 (frame pad)
//     − 2×0.8 (inner border) − 2×22 (inner pad) ≈ 707.
const double _kContentW = 707;

// Vertical chrome around the body: 2×16 page pad + borders/frame pad (≈8.4)
// + inner pad (18 top + 12 bottom) + 14 gap under the header.
const double _kPageVChrome = 32 + 8.4 + 30 + 14;

// Gap inserted between two section cards on the same page.
const double _kSectionGap = 14;

// How long the profile photo may take to arrive before the export proceeds
// with a placeholder instead.
const Duration _kPhotoTimeout = Duration(seconds: 8);

const Color _maroon = AppColors.primary;
const Color _gold = AppColors.gold;
const Color _paper = Color(0xFFFDF8F1);

String _dash(String? v) => (v ?? '').trim().isEmpty ? '—' : v!.trim();

String _two(int v) => v.toString().padLeft(2, '0');

String _fmtDate(DateTime? d) =>
    d == null ? '' : '${_two(d.day)}/${_two(d.month)}/${d.year}';

// ─────────────────────────────────────────────────────────────────────────────
// Print widgets
// ─────────────────────────────────────────────────────────────────────────────

/// One framed A4 page: double certificate border, [header] on top, body,
/// [footer] at the bottom. Body overflow is clipped as a last-resort guard —
/// the measured pagination keeps real content inside the page.
Widget _a4Page({
  required Widget header,
  required List<Widget> body,
  required Widget footer,
}) {
  return Container(
    width: _kPageW,
    height: _kPageH,
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
            header,
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
            footer,
          ],
        ),
      ),
    ),
  );
}

/// The rounded-square brand mark, falling back to the app logo / an icon.
Widget _brandLogo(double size) => ClipRRect(
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

/// Full branded header — page 1 only.
Widget _fullHeader() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _brandLogo(62)),
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
          child: Text('Member Profile',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800])),
        ),
        const SizedBox(height: 10),
        Container(height: 2.6, color: _maroon),
        const SizedBox(height: 2),
        Container(height: 1.2, color: _gold),
      ],
    );

/// Slim one-line header for pages after the first.
Widget _slimHeader() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Jothida Matrimony',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _maroon)),
            Text('Member Profile',
                style: TextStyle(fontSize: 10, color: Colors.grey[700])),
          ],
        ),
        const SizedBox(height: 6),
        Container(height: 2, color: _maroon),
        const SizedBox(height: 1.5),
        Container(height: 1, color: _gold),
      ],
    );

/// Footer on EVERY page: generation date-time, generating admin, page X of Y.
Widget _pageFooter({
  required String generatedAt,
  required String adminEmail,
  required int pageNo,
  required int pageCount,
}) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 0.8, color: Colors.grey[350]),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Generated: $generatedAt',
                      style: TextStyle(fontSize: 8.5, color: Colors.grey[600])),
                  Text(
                      'Generated by: '
                      '${adminEmail.trim().isEmpty ? 'Admin' : adminEmail.trim()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 8.5, color: Colors.grey[600])),
                ],
              ),
            ),
            const SizedBox(width: 8),
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
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: _maroon)),
        ),
        const Expanded(child: Divider(color: _gold, thickness: 0.9)),
      ],
    );

/// One label/value row inside a section card. Empty values render as "—".
Widget _kv(String label, String? value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 190,
              child: Text(label,
                  style: TextStyle(fontSize: 9.5, color: Colors.grey[700]))),
          Expanded(
              child: Text(_dash(value),
                  style: const TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w600))),
        ],
      ),
    );

/// A titled section card: gold-ruled title glued to a bordered table of
/// label/value rows (plus an optional [extra] widget, e.g. the Rasi chart).
/// The whole card paginates as ONE atomic unit.
Widget _sectionCard(String title, List<Widget> rows, {Widget? extra}) =>
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(title),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: BoxDecoration(
            color: _paper,
            border: Border.all(color: _maroon.withValues(alpha: 0.35), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [...rows, if (extra != null) extra],
          ),
        ),
      ],
    );

// ─────────────────────────────────────────────────────────────────────────────
// Measure → paginate → capture
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen route that (1) waits for the member's profile photo (with a
/// timeout → placeholder), (2) lays the section cards out offscreen at the
/// real A4 content width to measure their true heights, (3) flows them onto
/// pages, and (4) paints each page behind an opaque "preparing" overlay,
/// capturing every page as a PNG. Pops with the page images (null on failure).
class UserProfileExportCaptureScreen extends StatefulWidget {
  final UserModel user;
  final ProfileModel profile;
  final ContactDetails? contact; // contacts/{userId} record (admin-readable)
  final String adminEmail;

  const UserProfileExportCaptureScreen({
    super.key,
    required this.user,
    required this.profile,
    required this.contact,
    required this.adminEmail,
  });

  static Future<List<Uint8List>?> capture(
    BuildContext context, {
    required UserModel user,
    required ProfileModel profile,
    required ContactDetails? contact,
    required String adminEmail,
  }) =>
      Navigator.of(context).push<List<Uint8List>>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => UserProfileExportCaptureScreen(
          user: user,
          profile: profile,
          contact: contact,
          adminEmail: adminEmail,
        ),
      ));

  @override
  State<UserProfileExportCaptureScreen> createState() =>
      _UserProfileExportCaptureScreenState();
}

class _UserProfileExportCaptureScreenState
    extends State<UserProfileExportCaptureScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  final GlobalKey _headerKey = GlobalKey();
  final GlobalKey _slimHeaderKey = GlobalKey();
  final GlobalKey _footerKey = GlobalKey();

  List<Widget> _sections = const []; // atomic section cards, in order
  List<GlobalKey> _sectionKeys = const [];
  List<Widget> _pages = const [];
  late final String _generatedAt;
  bool _measuring = true;
  int _pageIndex = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _generatedAt = '${_fmtDate(now)} ${_two(now.hour)}:${_two(now.minute)}';
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_started) return;
    _started = true;
    try {
      // 1. Profile photo — wait for the network image (placeholder on
      //    failure/timeout) so the captured page never shows a half-loaded
      //    image.
      final photo =
          await _resolvePhoto(widget.profile.profilePhotoUrl ?? '');
      if (!mounted) return;
      setState(() {
        _sections = _buildSections(photo);
        _sectionKeys = [for (final _ in _sections) GlobalKey()];
      });

      // 2. Let the measuring pass (logo asset, cached photo, chart) settle,
      //    then read the true heights.
      await _pumpFrame();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await _pumpFrame();

      double h(GlobalKey k) => k.currentContext?.size?.height ?? 0;
      final headerH = h(_headerKey);
      final slimHeaderH = h(_slimHeaderKey);
      final footerH = h(_footerKey);
      final sectionHs = [for (final k in _sectionKeys) h(k)];
      if (headerH <= 0) throw StateError('measuring pass failed');

      final firstBodyH = _kPageH - _kPageVChrome - headerH - footerH - 4;
      final otherBodyH = _kPageH - _kPageVChrome - slimHeaderH - footerH - 4;
      final bodies = _paginate(sectionHs,
          firstBodyH: firstBodyH, otherBodyH: otherBodyH);
      _pages = [
        for (var i = 0; i < bodies.length; i++)
          _a4Page(
            header: i == 0 ? _fullHeader() : _slimHeader(),
            body: bodies[i],
            footer: _pageFooter(
              generatedAt: _generatedAt,
              adminEmail: widget.adminEmail,
              pageNo: i + 1,
              pageCount: bodies.length,
            ),
          ),
      ];

      // 3. Capture every page.
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
      debugPrint('[UserProfileExport] capture failed: $e');
      if (mounted) Navigator.of(context).pop(null);
    }
  }

  /// Resolves the member photo into the image cache so the capture frame can
  /// paint it synchronously. Returns null (→ placeholder) when the URL is
  /// empty, the download fails, or [_kPhotoTimeout] elapses.
  Future<ImageProvider?> _resolvePhoto(String url) async {
    final u = url.trim();
    if (u.isEmpty) return null;
    final provider = NetworkImage(u);
    final completer = Completer<bool>();
    final stream = provider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        info.dispose();
        if (!completer.isCompleted) completer.complete(true);
      },
      onError: (Object e, StackTrace? st) {
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    stream.addListener(listener);
    bool ok;
    try {
      ok = await completer.future
          .timeout(_kPhotoTimeout, onTimeout: () => false);
    } catch (_) {
      ok = false;
    } finally {
      stream.removeListener(listener);
    }
    return ok ? provider : null;
  }

  // ── Section cards ──────────────────────────────────────────────────────────

  List<Widget> _buildSections(ImageProvider? photo) {
    final p = widget.profile;
    final u = widget.user;
    final h = p.horoscope;
    final f = p.family;
    final pp = p.partnerPreferences;

    // Effective contact: the gated contacts/{userId} record first, the
    // profile-embedded contact as fallback (older documents), field by field.
    final c = widget.contact;
    final pc = p.contact;
    String pick(String? primary, String? fallback) {
      final a = (primary ?? '').trim();
      return a.isNotEmpty ? a : (fallback ?? '').trim();
    }

    String joined(Iterable<String?> parts) => parts
        .map((v) => (v ?? '').trim())
        .where((v) => v.isNotEmpty)
        .join(', ');

    final showChart = RasiChart.resolveIndex(h.rasi) >= 0 ||
        RasiChart.resolveIndex(h.lagnam) >= 0;

    return [
      _identityBlock(photo),
      _sectionCard('Basic Details', [
        _kv('Name', p.fullName),
        _kv('Name (Tamil)', p.fullNameTamil),
        _kv('Gender', p.gender),
        _kv('Date of Birth', _fmtDate(p.dateOfBirth)),
        _kv('Age', p.age > 0 ? '${p.age} years' : ''),
        _kv('Height', p.height),
        _kv('Weight', p.weight),
        _kv('Marital Status', p.maritalStatus),
        _kv('Mother Tongue', p.motherTongue),
        _kv('Religion', p.religion),
        _kv('Caste', p.caste),
        _kv('Sub Caste', p.subCaste),
      ]),
      _sectionCard('Personal Details', [
        _kv('Education Level', p.effectiveEducationLevel),
        _kv('Course / Degree', p.education),
        _kv('Occupation', p.occupation),
        _kv('Annual Income', p.annualIncome),
        _kv('City', p.city),
        _kv('District', p.district),
        _kv('State', p.state),
        _kv('About', p.aboutMe),
      ]),
      _sectionCard('Family Details', [
        _kv("Father's Name", f.fatherName),
        _kv("Father's Occupation", f.fatherOccupation),
        _kv("Mother's Name", f.motherName),
        _kv("Mother's Occupation", f.motherOccupation),
        _kv('Brothers', '${f.brothersCount} (${f.marriedBrothers} married)'),
        _kv('Sisters', '${f.sistersCount} (${f.marriedSisters} married)'),
        _kv('Family Type', f.familyType),
        _kv('Family Status', f.familyStatus),
        _kv('About Family', f.aboutFamily),
      ]),
      _sectionCard(
        'Horoscope Details',
        [
          _kv('Rasi', h.rasi),
          _kv('Nakshatra', h.nakshatra),
          _kv('Lagnam', h.lagnam),
          _kv('Chevvai Dosham', h.dosham),
          _kv('Rahu / Kethu Dosham', h.rahuKethuDosham),
          _kv('Kalasarpa Dosham', h.kalasarpaDosham),
          _kv('Dasa Balance', h.dasaBalance),
          _kv('Birth Date', _fmtDate(p.dateOfBirth)),
          _kv('Birth Time', h.birthTime),
          _kv('Birth Place', h.birthPlace),
        ],
        extra: showChart
            ? Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: SizedBox(
                    width: 240,
                    child: RasiChart(rasi: h.rasi, lagnam: h.lagnam),
                  ),
                ),
              )
            : null,
      ),
      _sectionCard('Partner Preferences', [
        _kv('Age Range', '${pp.minAge} – ${pp.maxAge} years'),
        _kv('Height Range', '${pp.minHeight} – ${pp.maxHeight}'),
        _kv('Education', pp.education.join(', ')),
        _kv('Occupation', pp.occupation.join(', ')),
        _kv('Annual Income', pp.income),
        _kv('Religion', pp.religion),
        _kv('Caste', pp.caste),
        _kv('Sub Caste', pp.subCaste),
        _kv('Marital Status', pp.maritalStatus),
        _kv('Mother Tongue', pp.motherTongue),
        _kv('Physical Status', pp.physicalStatus),
        _kv('Preferred Location',
            joined([pp.city, pp.district, pp.state, pp.country])),
        _kv('Rasi', pp.rasi),
        _kv('Nakshatra', pp.nakshatra),
        _kv('Chevvai Dosham', pp.chevvaiDosham),
        _kv('Horoscope Match Required',
            pp.horoscopeMatchRequired ? 'Yes' : 'No'),
      ]),
      _sectionCard('Membership', [
        _kv('Plan', 'Free'),
      ]),
      _sectionCard('Contact Details', [
        _kv('Contact Person', pick(c?.contactPersonName, pc.contactPersonName)),
        _kv('Relationship', pick(c?.relationship, pc.relationship)),
        _kv('Mobile', pick(c?.mobileNumber, pc.mobileNumber)),
        _kv('WhatsApp', pick(c?.whatsappNumber, pc.whatsappNumber)),
        _kv('Email', pick(c?.email, pc.email)),
        _kv('Registered Mobile (login)', u.phone),
        _kv('Registered Email (login)', u.email),
      ]),
    ];
  }

  /// Page-1 identity block: rounded profile photo (placeholder when the
  /// download failed / timed out), both names, member id.
  Widget _identityBlock(ImageProvider? photo) {
    final p = widget.profile;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _gold, width: 1.2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: photo != null
                ? Image(
                    image: photo, width: 120, height: 120, fit: BoxFit.cover)
                : Container(
                    width: 120,
                    height: 120,
                    color: _paper,
                    child: const Icon(Icons.person, size: 56, color: _maroon),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Text(_dash(p.fullName),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        if (p.fullNameTamil.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(p.fullNameTamil.trim(),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[850])),
          ),
        const SizedBox(height: 4),
        Text('Member ID: ${widget.user.uid}',
            style: TextStyle(fontSize: 8.5, color: Colors.grey[600])),
      ],
    );
  }

  /// Flows the measured section cards onto pages. Every card is atomic: when
  /// it does not fit in the current page's remaining space it starts a fresh
  /// page. Page 1 has less room (full branded header) than later pages.
  List<List<Widget>> _paginate(
    List<double> sectionHs, {
    required double firstBodyH,
    required double otherBodyH,
  }) {
    final pages = <List<Widget>>[];
    var cur = <Widget>[];
    var remaining = firstBodyH;
    for (var i = 0; i < _sections.length; i++) {
      final need = (cur.isEmpty ? 0 : _kSectionGap) + sectionHs[i];
      if (need > remaining && cur.isNotEmpty) {
        pages.add(cur);
        cur = <Widget>[];
        remaining = otherBodyH;
      }
      if (cur.isNotEmpty) {
        cur.add(const SizedBox(height: _kSectionGap));
        remaining -= _kSectionGap;
      }
      cur.add(_sections[i]);
      remaining -= sectionHs[i];
    }
    if (cur.isNotEmpty) pages.add(cur);
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
          if (_measuring && _sections.isNotEmpty)
            // Offscreen measuring pass: lay every piece out at the REAL A4
            // content width (nested scroll views give unbounded room, so the
            // cards take their true intrinsic heights).
            Positioned(
              left: 0,
              top: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: _kContentW,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KeyedSubtree(key: _headerKey, child: _fullHeader()),
                        KeyedSubtree(
                            key: _slimHeaderKey, child: _slimHeader()),
                        KeyedSubtree(
                          key: _footerKey,
                          child: _pageFooter(
                            generatedAt: _generatedAt,
                            adminEmail: widget.adminEmail,
                            pageNo: 1,
                            pageCount: 1,
                          ),
                        ),
                        for (var i = 0; i < _sections.length; i++)
                          KeyedSubtree(
                              key: _sectionKeys[i], child: _sections[i]),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (!_measuring && _pages.isNotEmpty)
            // The page being captured — painted at full A4 logical size (the
            // opaque overlay hides it; clipping never affects toImage).
            Positioned(
              left: 0,
              top: 0,
              child: RepaintBoundary(
                key: _boundaryKey,
                child: SizedBox(
                  width: _kPageW,
                  height: _kPageH,
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
                          ? 'Preparing profile export…'
                          : 'Preparing profile export… '
                              '(${_pageIndex + 1}/${_pages.length})',
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

/// Captures the member profile and shares it as ONE A4 PDF via the system
/// sheet. Returns true on success.
Future<bool> exportUserProfilePdf(
  BuildContext context, {
  required UserModel user,
  required ProfileModel profile,
  required ContactDetails? contact,
  required String adminEmail,
  required String fileName,
}) async {
  final pngs = await UserProfileExportCaptureScreen.capture(context,
      user: user, profile: profile, contact: contact, adminEmail: adminEmail);
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

/// Captures the member profile and shares it as PNG image(s) via the system
/// sheet. Returns true on success.
Future<bool> exportUserProfileImages(
  BuildContext context, {
  required UserModel user,
  required ProfileModel profile,
  required ContactDetails? contact,
  required String adminEmail,
  required String baseName,
}) async {
  final pngs = await UserProfileExportCaptureScreen.capture(context,
      user: user, profile: profile, contact: contact, adminEmail: adminEmail);
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
