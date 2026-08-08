import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/brand_assets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/file_actions.dart';
import '../../core/utils/value_l10n.dart';
import '../../models/profile_model.dart';
import '../../models/user_model.dart';

/// A4 PDF / image export of a member profile, laid out as the printed
/// **JOTHIDA MATRIMONY பதிவு படிவம்** (registration form) — the same branded
/// artwork the office hands out on paper, with the blanks filled in from the
/// member's saved profile instead of left empty.
///
/// One exporter serves BOTH callers so the two downloads can never drift apart:
///   • the admin User Details screen — nothing redacted;
///   • a member downloading a MATCH's profile after a mutually-accepted
///     interest — redacted by that member's own privacy switches.
/// [ProfileFormExportOptions] is the only difference between them.
///
/// Pages are laid out as REAL Flutter widgets at a fixed A4 logical size and
/// rasterised with [RepaintBoundary.toImage]: Flutter's text engine shapes
/// Tamil correctly, which the `pdf` package's own TTF renderer does not
/// guarantee. The captured PNG pages are embedded 1:1 into an A4 PDF (or
/// shared directly as images).
///
/// Pagination is measurement-driven: every section card is laid out offscreen
/// at the real content width to get its true height, then the cards FLOW onto
/// pages. Each card is atomic — a card that does not fit in the space left on
/// the current page starts a fresh one. Page 1 carries the full branded header
/// (logo + wordmark + photo box); later pages use the slim one-line header.

// A4 @ 96dpi logical pixels.
const double _kPageW = 794;
const double _kPageH = 1123;

const double _kPagePad = 18; // white margin outside the maroon frame
const double _kOuterBorder = 1.6;
const double _kFramePad = 5; // gap between the maroon and the pink frame
const double _kInnerBorder = 1;
const double _kContentPadH = 20;
const double _kContentPadTop = 16;
const double _kContentPadBottom = 10;
const double _kHeaderGap = 12;

/// Width available to page content inside the double frame.
const double _kContentW = _kPageW -
    2 * _kPagePad -
    2 * _kOuterBorder -
    2 * _kFramePad -
    2 * _kInnerBorder -
    2 * _kContentPadH;

/// Vertical chrome around the body (everything except header/body/footer).
const double _kPageVChrome = 2 * _kPagePad +
    2 * _kOuterBorder +
    2 * _kFramePad +
    2 * _kInnerBorder +
    _kContentPadTop +
    _kContentPadBottom +
    _kHeaderGap;

/// Gap inserted between two section cards on the same page.
const double _kSectionGap = 16;

/// How long the profile photo may take to arrive before the export proceeds
/// with the empty photo box instead.
const Duration _kPhotoTimeout = Duration(seconds: 8);

const Color _maroon = AppColors.primary;
const Color _pink = Color(0xFFE8C4CE); // hairline frame / card borders
const Color _rule = Color(0xFFAFAFAF); // the "write here" underlines
const Color _star = Color(0xFFD32F2F); // the red * on mandatory fields

/// Office contact block printed in every page footer.
const String _kPhone = '+91 8870846688';
const String _kEmail = 'jothidamatrimonysupport@gmail.com';
const String _kWebsite = 'www.jothidamatrimony.in';

/// Body text for the form — Tamil labels and mixed Tamil/English values.
///
/// Deliberately the SAME family + fallback chain [AppTextStyles] gives every
/// screen, so a page that renders in the app renders in the PDF. Do not pin
/// `'NotoSansTamil'` on its own here: the bundled file carries no Tamil
/// codepoints (it is a Latin-only placeholder), so Tamil is actually served by
/// the platform's font fallback — which only kicks in for a style the engine
/// can fall through, exactly as the app's own styles are set up.
TextStyle _ta({
  double size = 11.5,
  FontWeight weight = FontWeight.w400,
  Color color = Colors.black87,
  double height = 1.35,
  double? spacing,
}) =>
    TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontFamilyFallback: const [AppTextStyles.tamilFont],
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: spacing,
    );

String _dash(String? v) => (v ?? '').trim().isEmpty ? '' : v!.trim();

String _two(int v) => v.toString().padLeft(2, '0');

String _fmtDate(DateTime? d) =>
    d == null ? '' : '${_two(d.day)}/${_two(d.month)}/${d.year}';

String _joined(Iterable<String?> parts) => parts
    .map((v) => (v ?? '').trim())
    .where((v) => v.isNotEmpty)
    .join(', ');

/// Heights are stored as feet/inches (`5'6"`) but the form prints centimetres,
/// so convert. A value that is already a plain number is passed through, and
/// anything unparseable returns null (the row then prints the raw text).
String? _heightCm(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return null;
  final ftIn = RegExp(r"(\d+)\s*'\s*(\d+)?").firstMatch(v);
  if (ftIn != null) {
    final ft = int.tryParse(ftIn.group(1) ?? '') ?? 0;
    final inch = int.tryParse(ftIn.group(2) ?? '0') ?? 0;
    if (ft > 0) return (ft * 30.48 + inch * 2.54).round().toString();
  }
  final plain = RegExp(r'\d{2,3}').firstMatch(v);
  return plain?.group(0);
}

/// The numeric part of a stored weight ("62 kg" → "62"); null when there is none.
String? _weightKg(String raw) =>
    RegExp(r'\d{2,3}').firstMatch(raw.trim())?.group(0);

/// A partner-preference value for printing. `'Any'` is the app's "no
/// preference" sentinel, so the form leaves that rule BLANK rather than
/// writing the word "Any" onto the paper — the same reading the View Profile
/// page gives it.
String _pref(String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty || v.toLowerCase() == 'any') return '';
  return tamilValue(v);
}

// ─────────────────────────────────────────────────────────────────────────────
// What the exported form is allowed to show
// ─────────────────────────────────────────────────────────────────────────────

/// Per-caller redaction rules. The admin export shows everything; a member
/// downloading a match's profile sees exactly what that match's privacy
/// switches allow — the same rules the profile screen and the Contact Details
/// popup already enforce, so the PDF can never reveal more than the app does.
class ProfileFormExportOptions {
  /// Print the photo box empty instead of the member's picture.
  final bool hidePhoto;

  /// Blank the mobile and WhatsApp numbers (mirrors "Hide Phone Number",
  /// which hides the NUMBERS only — never the e-mail or contact person).
  final bool hidePhoneNumbers;

  /// Blank the annual income ("Hide Salary").
  final bool hideSalary;

  /// Blank the horoscope section's values ("Hide Horoscope Details").
  final bool hideHoroscope;

  /// Include the contact section at all. False for a viewer with no right to
  /// the member's contact details.
  final bool includeContact;

  /// Extra footer line — the admin export stamps who generated the file.
  final String? footerNote;

  const ProfileFormExportOptions({
    this.hidePhoto = false,
    this.hidePhoneNumbers = false,
    this.hideSalary = false,
    this.hideHoroscope = false,
    this.includeContact = true,
    this.footerNote,
  });

  /// Admin download: the complete record, stamped with the generating admin.
  factory ProfileFormExportOptions.admin({required String adminEmail}) {
    final who = adminEmail.trim();
    return ProfileFormExportOptions(
      footerNote: 'Generated by: ${who.isEmpty ? 'Admin' : who}',
    );
  }

  /// Member download of a MATCH's profile, gated on a mutually-accepted
  /// interest by the caller. Contact is unlocked by that acceptance (the same
  /// rule as the Contact Details popup), everything else follows the profile
  /// owner's own privacy switches.
  factory ProfileFormExportOptions.forMatch(ProfileModel profile) =>
      ProfileFormExportOptions(
        hidePhoto: profile.hidesPhoto,
        hidePhoneNumbers: profile.hidesPhone,
        hideSalary: profile.hidesSalary,
        hideHoroscope: profile.hidesHoroscope,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Page furniture
// ─────────────────────────────────────────────────────────────────────────────

/// One framed A4 page: maroon rounded border, pink hairline inside it,
/// [header] on top, body, [footer] at the bottom. Body overflow is clipped as
/// a last-resort guard — measured pagination keeps real content inside.
Widget _a4Page({
  required Widget header,
  required List<Widget> body,
  required Widget footer,
}) {
  return Container(
    width: _kPageW,
    height: _kPageH,
    color: Colors.white,
    padding: const EdgeInsets.all(_kPagePad),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _maroon, width: _kOuterBorder),
      ),
      padding: const EdgeInsets.all(_kFramePad),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: _pink, width: _kInnerBorder),
        ),
        padding: const EdgeInsets.fromLTRB(
            _kContentPadH, _kContentPadTop, _kContentPadH, _kContentPadBottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: _kHeaderGap),
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

/// The brand mark, falling back to the app logo / an icon.
Widget _brandLogo(double size) => ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: Image.asset(
        kAppLogoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.favorite, color: _maroon, size: size * 0.7),
      ),
    );

/// The maroon pill under the wordmark ("பதிவு படிவம்" on the blank form).
Widget _titlePill(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
      decoration: BoxDecoration(
        color: _maroon,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: _ta(
              size: 14.5, weight: FontWeight.w700, color: Colors.white)),
    );

/// Page-1 header: logo · wordmark + tagline + title pill · photo box.
Widget _fullHeader({required Widget photoBox}) => Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _brandLogo(96),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('JOTHIDA MATRIMONY',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    height: 1.1,
                    color: _maroon,
                  )),
              const SizedBox(height: 3),
              Text('உங்கள் வாழ்க்கைத் துணையை கண்டுபிடியுங்கள்',
                  textAlign: TextAlign.center,
                  style: _ta(size: 12, color: _maroon, height: 1.2)),
              const SizedBox(height: 5),
              // Thin rule broken by a small heart, as on the printed form.
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 90, child: Divider(color: _pink, thickness: 1)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.favorite, size: 10, color: _maroon),
                  ),
                  SizedBox(
                      width: 90, child: Divider(color: _pink, thickness: 1)),
                ],
              ),
              const SizedBox(height: 5),
              _titlePill('உறுப்பினர் விவரம்'),
            ],
          ),
        ),
        const SizedBox(width: 14),
        photoBox,
      ],
    );

/// Top-right photo frame. With a picture it is a solid maroon frame; with none
/// it stays the empty "புகைப்படம்" box of the paper form — which is also what a
/// member who hid their photo exports as.
Widget _photoBox(ImageProvider? photo) {
  const w = 108.0;
  const h = 126.0;
  if (photo != null) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _maroon, width: 1.2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Image(image: photo, fit: BoxFit.cover),
      ),
    );
  }
  return Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: const Color(0xFFFDF3F5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _pink, width: 1.2),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.person, size: 40, color: _maroon),
        const SizedBox(height: 6),
        Text('புகைப்படம்',
            textAlign: TextAlign.center,
            style: _ta(size: 9.5, weight: FontWeight.w600, color: _maroon)),
      ],
    ),
  );
}

/// Slim header for pages after the first — wordmark plus the applicant's name.
Widget _slimHeader(String applicantName) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text('JOTHIDA MATRIMONY',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: _maroon,
              )),
          const SizedBox(width: 22),
          Text('விண்ணப்பதாரர் பெயர்', style: _ta(size: 11.5)),
          Text('  :  ', style: _ta(size: 11.5)),
          Expanded(child: _underlined(applicantName)),
        ],
      ),
    );

/// Footer on EVERY page: the office contact strip, then a tiny provenance
/// line (generation time, optional note, page X of Y).
Widget _pageFooter({
  required String generatedAt,
  required String? note,
  required int pageNo,
  required int pageCount,
}) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(color: _pink, thickness: 0.9, height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _footerContact(Icons.call, const Color(0xFF25D366), _kPhone),
            _footerContact(
                Icons.mail_outline, const Color(0xFFD93025), _kEmail),
            _footerContact(
                Icons.language, const Color(0xFF1A73E8), _kWebsite),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: Text(
                _joined(['பதிவிறக்கம்: $generatedAt', note]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _ta(size: 7.5, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(width: 8),
            Text('பக்கம் $pageNo / $pageCount',
                style: _ta(size: 7.5, color: Colors.grey.shade600)),
          ],
        ),
      ],
    );

Widget _footerContact(IconData icon, Color color, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(text, style: _ta(size: 9, color: Colors.black87)),
      ],
    );

// ─────────────────────────────────────────────────────────────────────────────
// Form primitives
// ─────────────────────────────────────────────────────────────────────────────

/// A value sitting on a printed "write here" rule. An empty value keeps the
/// rule (and the row's height), exactly like the blank paper form.
Widget _underlined(String? value, {String? suffix, double size = 11.5}) => Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _rule, width: 0.8)),
            ),
            child: Text(
              _dash(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _ta(size: size, weight: FontWeight.w600),
            ),
          ),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 5),
          Text(suffix, style: _ta(size: 10, color: Colors.black87)),
        ],
      ],
    );

/// `label * :  ______value______` — the atom every section is built from.
Widget _field(
  String label,
  String? value, {
  bool required = false,
  String? suffix,
  double labelW = 118,
}) =>
    Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(width: labelW, child: _label(label, required: required)),
        Text(':', style: _ta(size: 11.5)),
        const SizedBox(width: 6),
        Expanded(child: _underlined(value, suffix: suffix)),
      ],
    );

Widget _label(String text, {bool required = false}) => RichText(
      maxLines: 2,
      text: TextSpan(
        text: text,
        style: _ta(size: 11.5),
        children: required
            ? [TextSpan(text: ' *', style: _ta(size: 11.5, color: _star))]
            : null,
      ),
    );

/// Two [_field]s side by side, as on the printed form.
Widget _pair(Widget left, Widget right) => Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: left),
        const SizedBox(width: 22),
        Expanded(child: right),
      ],
    );

/// One tick box. [checked] paints the maroon fill + tick that marks the
/// member's stored value.
Widget _box(bool checked) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: checked ? _maroon : Colors.white,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: _maroon, width: 1),
      ),
      child: checked
          ? const Icon(Icons.check, size: 9, color: Colors.white)
          : null,
    );

/// `label : ☐ a  ☑ b  ☐ c` — the ticked option is the member's stored value.
/// Options wrap, so a long list never overflows the card.
Widget _choice(
  String label,
  List<(String, bool)> options, {
  bool required = false,
  double labelW = 118,
}) =>
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelW,
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: _label(label, required: required),
          ),
        ),
        Text(':', style: _ta(size: 11.5)),
        const SizedBox(width: 6),
        Expanded(
          child: Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final (text, checked) in options)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _box(checked),
                    const SizedBox(width: 5),
                    Text(text, style: _ta(size: 11.5)),
                  ],
                ),
            ],
          ),
        ),
      ],
    );

/// A numbered section: the maroon pill straddles the top-left corner of a
/// pink-bordered card, and the whole thing paginates as ONE atomic unit.
Widget _section(String title, List<Widget> rows) => Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 13),
          padding: const EdgeInsets.fromLTRB(18, 26, 18, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _pink, width: 0.9),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: 9),
                rows[i],
              ],
            ],
          ),
        ),
        Positioned(
          left: 20,
          top: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: _maroon,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(title,
                style: _ta(
                    size: 14, weight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ],
    );

// ─────────────────────────────────────────────────────────────────────────────
// Measure → paginate → capture
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen route that (1) waits for the member's photo (with a timeout →
/// empty photo box), (2) lays the section cards out offscreen at the real A4
/// content width to measure their true heights, (3) flows them onto pages, and
/// (4) paints each page behind an opaque "preparing" overlay, capturing every
/// page as a PNG. Pops with the page images (null on failure).
class ProfileFormCaptureScreen extends StatefulWidget {
  final ProfileModel profile;

  /// Login identity — admin exports print the registered phone / e-mail.
  final UserModel? user;

  /// The gated `contacts/{userId}` record; falls back to the copy on the
  /// profile document field by field.
  final ContactDetails? contact;

  final ProfileFormExportOptions options;

  const ProfileFormCaptureScreen({
    super.key,
    required this.profile,
    required this.user,
    required this.contact,
    required this.options,
  });

  static Future<List<Uint8List>?> capture(
    BuildContext context, {
    required ProfileModel profile,
    required UserModel? user,
    required ContactDetails? contact,
    required ProfileFormExportOptions options,
  }) =>
      Navigator.of(context).push<List<Uint8List>>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProfileFormCaptureScreen(
          profile: profile,
          user: user,
          contact: contact,
          options: options,
        ),
      ));

  @override
  State<ProfileFormCaptureScreen> createState() =>
      _ProfileFormCaptureScreenState();
}

class _ProfileFormCaptureScreenState extends State<ProfileFormCaptureScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  final GlobalKey _headerKey = GlobalKey();
  final GlobalKey _slimHeaderKey = GlobalKey();
  final GlobalKey _footerKey = GlobalKey();

  List<Widget> _sections = const []; // atomic section cards, in order
  List<GlobalKey> _sectionKeys = const [];
  List<Widget> _pages = const [];
  ImageProvider? _photo;
  late final String _generatedAt;
  bool _measuring = true;
  int _pageIndex = 0;
  bool _started = false;

  String get _applicantName {
    final p = widget.profile;
    final ta = p.fullNameTamil.trim();
    return ta.isNotEmpty ? ta : p.fullName.trim();
  }

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
      // 1. Profile photo — wait for the network image (empty box on
      //    failure/timeout/redaction) so a captured page never shows a
      //    half-loaded picture.
      final photo = widget.options.hidePhoto
          ? null
          : await _resolvePhoto(widget.profile.profilePhotoUrl ?? '');
      if (!mounted) return;
      setState(() {
        _photo = photo;
        _sections = _buildSections();
        _sectionKeys = [for (final _ in _sections) GlobalKey()];
      });

      // 2. Let the measuring pass (logo asset, cached photo) settle, then read
      //    the true heights.
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
      final bodies =
          _paginate(sectionHs, firstBodyH: firstBodyH, otherBodyH: otherBodyH);
      _pages = [
        for (var i = 0; i < bodies.length; i++)
          _a4Page(
            header: i == 0
                ? _fullHeader(photoBox: _photoBox(_photo))
                : _slimHeader(_applicantName),
            body: bodies[i],
            footer: _pageFooter(
              generatedAt: _generatedAt,
              note: widget.options.footerNote,
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
      debugPrint('[ProfileFormExport] capture failed: $e');
      if (mounted) Navigator.of(context).pop(null);
    }
  }

  /// Resolves the member photo into the image cache so the capture frame can
  /// paint it synchronously. Returns null (→ empty box) when the URL is empty,
  /// the download fails, or [_kPhotoTimeout] elapses.
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
      ok = await completer.future.timeout(_kPhotoTimeout, onTimeout: () => false);
    } catch (_) {
      ok = false;
    } finally {
      stream.removeListener(listener);
    }
    return ok ? provider : null;
  }

  // ── Section cards ──────────────────────────────────────────────────────────

  List<Widget> _buildSections() => buildProfileFormSections(
        profile: widget.profile,
        user: widget.user,
        contact: widget.contact,
        options: widget.options,
      );

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
                        KeyedSubtree(
                            key: _headerKey,
                            child: _fullHeader(photoBox: _photoBox(_photo))),
                        KeyedSubtree(
                            key: _slimHeaderKey,
                            child: _slimHeader(_applicantName)),
                        KeyedSubtree(
                          key: _footerKey,
                          child: _pageFooter(
                            generatedAt: _generatedAt,
                            note: widget.options.footerNote,
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
                          ? 'Preparing profile…'
                          : 'Preparing profile… '
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

/// The numbered sections of the printed registration form, filled in from the
/// profile. Redacted values print as a blank rule, so the layout is identical
/// whether or not the member hid something. Top-level so the capture screen
/// and the layout test build the exact same cards.
List<Widget> buildProfileFormSections({
  required ProfileModel profile,
  required UserModel? user,
  required ContactDetails? contact,
  required ProfileFormExportOptions options,
}) {
  final p = profile;
  final o = options;
  final f = p.family;
  final h = p.horoscope;
  final pp = p.partnerPreferences;

  // Effective contact: the gated contacts/{userId} record first, the
  // profile-embedded copy as fallback (older documents), field by field.
  final c = contact;
  final pc = p.contact;
  String pick(String? primary, String? fallback) {
    final a = (primary ?? '').trim();
    return a.isNotEmpty ? a : (fallback ?? '').trim();
  }

  final mobile = o.hidePhoneNumbers
      ? ''
      : pick(c?.mobileNumber, pc.mobileNumber);
  final whatsapp = o.hidePhoneNumbers
      ? ''
      : pick(c?.whatsappNumber, pc.whatsappNumber);
  final email = pick(c?.email, pc.email);

  final marital = AppConstants.normalizeMaritalStatus(p.maritalStatus);
  final heightCm = _heightCm(p.height);
  final weightKg = _weightKg(p.weight);

  return [
    _section('1. அடிப்படை விவரங்கள்', [
      _field('முழுப் பெயர்', _joined([p.fullNameTamil, p.fullName]),
          required: true, labelW: 108),
      _choice(
        'பாலினம்',
        [
          for (final g in AppConstants.genderList)
            (tamilValue(g), p.gender.trim() == g),
        ],
        required: true,
        labelW: 108,
      ),
      _pair(
        _field('பிறந்த தேதி', _fmtDate(p.dateOfBirth),
            required: true, labelW: 108),
        _field('வயது', p.age > 0 ? '${p.age}' : '',
            suffix: 'ஆண்டுகள்', labelW: 70),
      ),
      _choice(
        'உடல் நிலை',
        [
          for (final s in AppConstants.physicalStatusList)
            (tamilValue(s), p.physicalStatus.trim() == s),
        ],
        labelW: 108,
      ),
      _choice(
        'திருமண நிலை',
        [
          for (final s in AppConstants.maritalStatusList)
            (tamilValue(s), marital == s),
        ],
        required: true,
        labelW: 108,
      ),
      _pair(
        _field('மதம்', tamilValue(p.religion), required: true, labelW: 108),
        _field('சாதி', tamilValue(p.caste), required: true, labelW: 70),
      ),
      _pair(
        _field('உட்பிரிவு', tamilValue(p.subCaste), labelW: 108),
        _field('தாய் மொழி', tamilValue(p.motherTongue),
            required: true, labelW: 70),
      ),
      _pair(
        _field('உயரம்', heightCm ?? p.height,
            suffix: heightCm == null ? null : 'செ.மீ', labelW: 108),
        _field('எடை', weightKg ?? p.weight,
            suffix: weightKg == null ? null : 'கிலோ', labelW: 70),
      ),
      _pair(
        _field('சொந்த ஊர்', p.nativePlace, labelW: 108),
        _field('குடியுரிமை', tamilValue(p.citizenship), labelW: 70),
      ),
      if (o.includeContact) ...[
        _pair(
          _field('மொபைல் எண்', mobile, required: true, labelW: 108),
          // Wider than its neighbours: "WhatsApp எண்" wraps to two lines at 70.
          _field('WhatsApp எண்', whatsapp, labelW: 95),
        ),
        _field('மின்னஞ்சல்', email, labelW: 108),
      ],
      _field('முகவரி', _joined([p.city, p.district, p.state, p.country]),
          labelW: 108),
    ]),
    _section('2. குடும்ப விவரங்கள்', [
      _pair(
        _field('தந்தை பெயர்', f.fatherName, labelW: 108),
        _field('தந்தை தொழில்', f.fatherOccupation, labelW: 92),
      ),
      _pair(
        _field('தாய் பெயர்', f.motherName, labelW: 108),
        _field('தாய் தொழில்', f.motherOccupation, labelW: 92),
      ),
      _pair(
        _field('சகோதரர்', _siblings(f.brothersCount, f.marriedBrothers),
            labelW: 108),
        _field('சகோதரி', _siblings(f.sistersCount, f.marriedSisters),
            labelW: 92),
      ),
      _choice(
        'குடும்ப வகை',
        [
          for (final t in AppConstants.familyTypeList)
            (tamilValue(t), f.familyType.trim() == t),
        ],
        labelW: 108,
      ),
      _field('குடும்ப நிலை', tamilValue(f.familyStatus), labelW: 108),
      _field('குடும்பம் பற்றி', f.aboutFamily, labelW: 108),
    ]),
    _section('3. கல்வி & தொழில்', [
      _pair(
        _field('கல்வித் தகுதி', tamilValue(p.effectiveEducationLevel),
            required: true, labelW: 108),
        _field('படிப்பு / பட்டம்', p.education, labelW: 100),
      ),
      _pair(
        _field('தொழில்', p.occupation, required: true, labelW: 108),
        _field('பணியிடம்', p.workLocation, labelW: 100),
      ),
      _field('ஆண்டு வருமானம்', o.hideSalary ? '' : p.annualIncome,
          labelW: 108),
      _choice(
        'வேலை வகை',
        [
          for (final t in AppConstants.employmentTypeList)
            (tamilValue(t), p.employmentType.trim() == t),
        ],
        labelW: 108,
      ),
    ]),
    _section('4. ஜாதக விவரங்கள்', [
      _pair(
        _field('பிறந்த தேதி', _fmtDate(p.dateOfBirth),
            required: true, labelW: 108),
        _field('பிறந்த நேரம்', o.hideHoroscope ? '' : h.birthTime,
            required: true, labelW: 92),
      ),
      _field('பிறந்த இடம்', o.hideHoroscope ? '' : h.birthPlace,
          required: true, labelW: 108),
      _pair(
        _field('ராசி', o.hideHoroscope ? '' : tamilValue(h.rasi),
            labelW: 108),
        _field('நட்சத்திரம்', o.hideHoroscope ? '' : tamilValue(h.nakshatra),
            labelW: 92),
      ),
      _pair(
        _field('லக்னம்', o.hideHoroscope ? '' : tamilValue(h.lagnam),
            labelW: 108),
        _field('தசா இருப்பு', o.hideHoroscope ? '' : h.dasaBalance,
            labelW: 92),
      ),
      _doshamRow(o.hideHoroscope ? '' : h.dosham),
      _field(
        'பிற குறிப்புகள்',
        o.hideHoroscope
            ? ''
            : _joined([
                if (h.rahuKethuDosham.trim().isNotEmpty)
                  'ராகு/கேது: ${tamilValue(h.rahuKethuDosham)}',
                if (h.kalasarpaDosham.trim().isNotEmpty)
                  'காலசர்ப்பம்: ${tamilValue(h.kalasarpaDosham)}',
              ]),
        labelW: 108,
      ),
    ]),
    _section('5. வாழ்க்கைத் துணை விருப்பங்கள்', [
      _field('வயது வரம்பு', '${pp.minAge} முதல் ${pp.maxAge} வரை',
          suffix: 'ஆண்டுகள்', labelW: 118),
      // Not _joined: that comma-separates, and a range reads as a sentence.
      _field(
          'உயரம் வரம்பு',
          [pp.minHeight, pp.maxHeight].every((v) => v.trim().isEmpty)
              ? ''
              : '${pp.minHeight} முதல் ${pp.maxHeight} வரை',
          labelW: 118),
      _pair(
        _field('கல்வி', pp.education.map(_pref).join(', '), labelW: 118),
        _field('தொழில்', pp.occupation.map(_pref).join(', '), labelW: 80),
      ),
      _pair(
        // NOT gated by "Hide Salary": that switch covers the member's OWN
        // annual income, not the income they look for in a partner — the same
        // split the View Profile page makes.
        _field('வருமானம்', _pref(pp.income), labelW: 118),
        _field('மதம்', _pref(pp.religion), labelW: 80),
      ),
      _pair(
        _field('சாதி', _pref(pp.caste), labelW: 118),
        _field('இருப்பிடம்',
            _joined([pp.city, pp.district, pp.state, pp.country].map(_pref)),
            labelW: 80),
      ),
      _field(
        'பிற விருப்பங்கள்',
        _joined([
          if (_pref(pp.maritalStatus).isNotEmpty)
            'திருமண நிலை: ${_pref(pp.maritalStatus)}',
          if (_pref(pp.motherTongue).isNotEmpty)
            'தாய் மொழி: ${_pref(pp.motherTongue)}',
          if (_pref(pp.physicalStatus).isNotEmpty)
            'உடல் நிலை: ${_pref(pp.physicalStatus)}',
        ]),
        labelW: 118,
      ),
    ]),
    if (user != null) _loginSection(user),
  ];
}

/// Registered login identity — admin-only context, never part of the paper
/// form, so it is a plain extra card at the end.
Widget _loginSection(UserModel u) => _section('6. பதிவு விவரங்கள்', [
      _pair(
        _field('பதிவு மொபைல்', u.phone, labelW: 118),
        _field('பதிவு மின்னஞ்சல்', u.email, labelW: 100),
      ),
      _field('உறுப்பினர் எண்', u.uid, labelW: 118),
    ]);

String _siblings(int total, int married) =>
    total <= 0 ? '' : '$total ($married திருமணமானவர்)';

/// Chevvai dosham is a FREE-TEXT field on the profile, not a dropdown, so
/// the printed form's three tick boxes cannot represent every stored value.
/// A recognised answer ticks its box; anything else the member typed is
/// printed verbatim on a rule rather than silently dropped; empty leaves the
/// boxes blank, exactly like the paper form.
Widget _doshamRow(String stored) {
  const label = 'செவ்வாய் தோஷம்';
  final v = stored.trim().toLowerCase();
  final match = v.isEmpty ? null : _doshamAliases[v];
  if (v.isNotEmpty && match == null) {
    return _field(label, stored.trim(), labelW: 108);
  }
  return _choice(
    label,
    [
      for (final o in _doshamOptions) (o, match == o),
    ],
    labelW: 108,
  );
}

const List<String> _doshamOptions = [
  'உண்டு',
  'இல்லை',
  'தெரியவில்லை',
];

/// Stored value (lower-cased) → the tick box it selects.
const Map<String, String> _doshamAliases = {
  'yes': 'உண்டு',
  'true': 'உண்டு',
  'have': 'உண்டு',
  'present': 'உண்டு',
  'உண்டு': 'உண்டு',
  'no': 'இல்லை',
  'false': 'இல்லை',
  'none': 'இல்லை',
  'nil': 'இல்லை',
  'இல்லை': 'இல்லை',
  "don't know": 'தெரியவில்லை',
  'dont know': 'தெரியவில்லை',
  'not known': 'தெரியவில்லை',
  'unknown': 'தெரியவில்லை',
  'தெரியவில்லை': 'தெரியவில்லை',
};

// ─────────────────────────────────────────────────────────────────────────────
/// Every piece of the form — full header, all section cards, slim header,
/// footer — as ONE continuous A4-width column, with no pagination and no
/// capture. The layout test pumps this to prove the printed form never
/// overflows, whatever a member typed into their profile.
@visibleForTesting
Widget buildProfileFormPreview({
  required ProfileModel profile,
  UserModel? user,
  ContactDetails? contact,
  ProfileFormExportOptions options = const ProfileFormExportOptions(),
}) {
  final sections = buildProfileFormSections(
      profile: profile, user: user, contact: contact, options: options);
  final name = profile.fullNameTamil.trim().isNotEmpty
      ? profile.fullNameTamil.trim()
      : profile.fullName.trim();
  return Container(
    width: _kContentW,
    color: Colors.white,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fullHeader(photoBox: _photoBox(null)),
        const SizedBox(height: _kHeaderGap),
        for (final s in sections) ...[
          s,
          const SizedBox(height: _kSectionGap),
        ],
        _slimHeader(name),
        const SizedBox(height: _kHeaderGap),
        _pageFooter(
          generatedAt: '01/01/2026 09:30',
          note: options.footerNote,
          pageNo: 1,
          pageCount: 2,
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Export entry points
// ─────────────────────────────────────────────────────────────────────────────

/// Captures the profile form and shares it as ONE A4 PDF via the system sheet.
/// Returns true on success.
Future<bool> exportProfileFormPdf(
  BuildContext context, {
  required ProfileModel profile,
  UserModel? user,
  ContactDetails? contact,
  required ProfileFormExportOptions options,
  required String fileName,
}) async {
  final pngs = await ProfileFormCaptureScreen.capture(context,
      profile: profile, user: user, contact: contact, options: options);
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

/// Captures the profile form and shares it as PNG page image(s) via the system
/// sheet. Returns true on success.
Future<bool> exportProfileFormImages(
  BuildContext context, {
  required ProfileModel profile,
  UserModel? user,
  ContactDetails? contact,
  required ProfileFormExportOptions options,
  required String baseName,
}) async {
  final pngs = await ProfileFormCaptureScreen.capture(context,
      profile: profile, user: user, contact: contact, options: options);
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

/// A filesystem-safe base name for this member's export
/// ("jothida_profile_kavitha_r"), falling back to the profile id for
/// Tamil-only or empty names.
String profileExportBaseName(ProfileModel profile) {
  var slug = profile.fullName
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (slug.isEmpty) slug = profile.id;
  return 'jothida_profile_$slug';
}
