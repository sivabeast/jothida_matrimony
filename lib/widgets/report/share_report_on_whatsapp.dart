import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/phone_utils.dart';
import '../../models/astrologer_request_model.dart';

/// **Sending the finished report to the member on WhatsApp** (spec §17–§19).
///
/// This is the astrologer's side of the flow, and the ONLY place WhatsApp
/// appears in the horoscope journey — the member's payment confirmation
/// deliberately has none (spec §20).
///
/// The recipient is never chosen by hand. It is [AstrologerRequestModel]'s own
/// `contactWhatsapp` — the number the member typed into the request they paid
/// for — resolved through [AstrologerRequestModel.whatsappDialNumber], falling
/// back to the account's phone. No admin number, no office number, nothing
/// hardcoded (spec §18).
///
/// **Why two steps rather than one button.** WhatsApp has no API for
/// "send THIS file to THAT number": `wa.me` addresses a conversation but
/// carries text only, and the system share sheet carries the file but lets the
/// OS pick the conversation. Pretending otherwise would mean a button that
/// silently sends the report to whoever the astrologer last messaged. So the
/// sheet does both halves explicitly and in order — open the right chat, then
/// attach the report — and shows the number it is using so a wrong one is
/// obvious before anything is sent.
Future<void> showShareReportOnWhatsapp(
  BuildContext context, {
  required AstrologerRequestModel request,

  /// Produces the report file and hands it to the system share sheet. Returns
  /// false when the report could not be rendered.
  required Future<bool> Function({required bool pdf}) exportFile,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) =>
        _ShareSheet(request: request, exportFile: exportFile),
  );
}

class _ShareSheet extends StatefulWidget {
  final AstrologerRequestModel request;
  final Future<bool> Function({required bool pdf}) exportFile;

  const _ShareSheet({required this.request, required this.exportFile});

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  bool _busy = false;

  AstrologerRequestModel get r => widget.request;

  /// The member's number in dialling form, or '' when the request carries none.
  ///
  /// `whatsappDialNumber` is the request's own contact number; `userPhone` is
  /// the account's, used only when the request predates the contact step. Both
  /// come from the stored request — this never reads the signed-in (staff)
  /// user (spec §18).
  String get _dialNumber {
    final fromRequest = r.whatsappDialNumber;
    if (fromRequest.isNotEmpty) return fromRequest;
    final account = normalizeIndianPhone(r.userPhone);
    return account.length == 12 ? account : '';
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens the member's own WhatsApp conversation, with the report reference
  /// already typed so the file that follows has context.
  Future<void> _openChat() async {
    final l10n = context.l10n;
    final number = _dialNumber;
    if (number.isEmpty) {
      _snack(l10n.noWhatsappNumberForMember);
      return;
    }
    final text = Uri.encodeComponent(
        '${l10n.horoscopeCompatibilityReport}\n'
        '${l10n.requestIdLabel}: ${r.id}\n'
        '${r.displayContactName}');
    try {
      final ok = await launchUrl(
          Uri.parse('${whatsappUri(number)}?text=$text'),
          mode: LaunchMode.externalApplication);
      if (!ok) _snack(l10n.couldNotOpenWhatsapp);
    } catch (_) {
      _snack(l10n.couldNotOpenWhatsapp);
    }
  }

  Future<void> _share({required bool pdf}) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      final ok = await widget.exportFile(pdf: pdf);
      if (!mounted) return;
      _snack(ok ? l10n.reportSharedOnWhatsapp : l10n.couldNotPrepareShare);
    } catch (e) {
      debugPrint('[ShareReport] export failed: $e');
      if (mounted) _snack(l10n.couldNotPrepareShare);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final number = _dialNumber;
    final hasNumber = number.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Row(children: [
              const Icon(Icons.chat, color: Color(0xFF25D366), size: 22),
              const SizedBox(width: 9),
              Expanded(
                child: Text(l10n.shareReportOnWhatsapp,
                    style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 14),

            // ── Who this is going to ──────────────────────────────────────
            // Named and numbered before anything is sent: the one mistake this
            // flow can make is reaching the wrong person.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: hasNumber
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : AppColors.error.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.displayContactName,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  if (hasNumber)
                    Row(children: [
                      Expanded(
                        child: SelectableText(
                            formatIndianPhoneDisplay(number),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary)),
                      ),
                      IconButton(
                        tooltip: l10n.copy,
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        onPressed: () => Clipboard.setData(
                            ClipboardData(text: number)),
                      ),
                    ])
                  else
                    Text(l10n.noWhatsappNumberForMember,
                        style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.45,
                            color: AppColors.error)),
                  const SizedBox(height: 2),
                  Text('${l10n.requestIdLabel}: ${r.id}',
                      style:
                          TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Step 1: the right conversation ────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: hasNumber && !_busy ? _openChat : null,
                icon: const Icon(Icons.chat, size: 19),
                label: Text(l10n.openWhatsappChat,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ── Step 2: the report itself, as a file ──────────────────────
            Text(l10n.attachReportHint,
                style: TextStyle(
                    fontSize: 12, height: 1.45, color: Colors.grey[700])),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _share(pdf: true),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: Text(l10n.pdfA4,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _share(pdf: false),
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(l10n.imageLabel,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
            if (_busy) ...[
              const SizedBox(height: 14),
              Row(children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary)),
                const SizedBox(width: 10),
                Text(l10n.preparingReportFile,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
