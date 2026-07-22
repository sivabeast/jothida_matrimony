import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/profile_model.dart';
import 'network_photo.dart';

/// The ONE way horoscope documents are presented anywhere in the app —
/// the employee's Request Details page, the match-analysis workspace and a
/// member's profile view (after a mutually-accepted interest).
///
/// * **Images** render as thumbnails; tapping opens the full-screen, zoomable
///   gallery. Each thumbnail carries its own Download action.
/// * **PDFs** render as a row with a PDF icon + file name, a **View** button
///   (in-app viewer — never depends on an external PDF app) and a **Download**
///   button (system save/share sheet).
///
/// Fully responsive: thumbnails live in a horizontally scrolling rail and the
/// PDF rows wrap their actions, so nothing can overflow on a small phone.
class HoroscopeDocumentsView extends StatelessWidget {
  final List<String> imageUrls;
  final List<String> pdfUrls;

  /// Section heading. Pass null to render the lists without a heading.
  final String? title;

  /// Shown when there is nothing to display. Defaults to the standard
  /// "no horoscope documents" message; pass an empty string to render nothing.
  final String? emptyMessage;

  final double thumbnailSize;

  const HoroscopeDocumentsView({
    super.key,
    required this.imageUrls,
    required this.pdfUrls,
    this.title,
    this.emptyMessage,
    this.thumbnailSize = 88,
  });

  /// Builds straight from a profile's horoscope details, folding the legacy
  /// single PDF field into the multi-PDF list.
  factory HoroscopeDocumentsView.fromHoroscope(
    HoroscopeDetails? h, {
    String? title,
    String? emptyMessage,
    double thumbnailSize = 88,
  }) =>
      HoroscopeDocumentsView(
        imageUrls: h?.horoscopeImages ?? const [],
        pdfUrls: h?.allPdfUrls ?? const [],
        title: title,
        emptyMessage: emptyMessage,
        thumbnailSize: thumbnailSize,
      );

  bool get isEmpty => imageUrls.isEmpty && pdfUrls.isEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (isEmpty) {
      final message = emptyMessage ?? l10n.noHoroscopeFiles;
      if (message.isEmpty) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Text(message,
            style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(title!,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
        ],
        if (imageUrls.isNotEmpty) ...[
          Text(l10n.horoscopeImages,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: Colors.grey[700])),
          const SizedBox(height: 6),
          SizedBox(
            // +34 leaves room for the per-thumbnail action row underneath.
            height: thumbnailSize + 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: imageUrls.length,
              padding: EdgeInsets.zero,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _ImageThumb(
                urls: imageUrls,
                index: i,
                size: thumbnailSize,
              ),
            ),
          ),
          if (pdfUrls.isNotEmpty) const SizedBox(height: 14),
        ],
        if (pdfUrls.isNotEmpty) ...[
          Text(l10n.horoscopePdfs,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: Colors.grey[700])),
          const SizedBox(height: 6),
          for (var i = 0; i < pdfUrls.length; i++)
            _PdfRow(url: pdfUrls[i], label: l10n.horoscopePdfN(i + 1), index: i),
        ],
      ],
    );
  }
}

/// One image thumbnail + a compact "View full" / "Download" action row.
class _ImageThumb extends StatelessWidget {
  final List<String> urls;
  final int index;
  final double size;
  const _ImageThumb({
    required this.urls,
    required this.index,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      width: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => showImageGallery(context, urls, initialIndex: index),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: NetworkPhoto(
                  url: urls[index], width: size, height: size),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _iconAction(
                icon: Icons.fullscreen,
                tooltip: l10n.viewFull,
                onTap: () =>
                    showImageGallery(context, urls, initialIndex: index),
              ),
              _iconAction(
                icon: Icons.download_outlined,
                tooltip: l10n.download,
                onTap: () =>
                    shareRemoteFile(context, urls[index], pdf: false, index: index),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
        ),
      );
}

/// One PDF: icon + file name, with View (in-app) and Download actions. The
/// actions sit in a [Wrap] so they move onto a second line on narrow screens
/// instead of overflowing.
class _PdfRow extends StatelessWidget {
  final String url;
  final String label;
  final int index;
  const _PdfRow(
      {required this.url, required this.label, required this.index});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.picture_as_pdf_outlined,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(l10n.tapToOpen,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () =>
                    openPdfInApp(context, url, title: label),
                icon: const Icon(Icons.visibility_outlined, size: 17),
                label: Text(l10n.viewLabel),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              TextButton.icon(
                onPressed: () => downloadRemotePdf(context, url,
                    fileName: 'jothida_horoscope_${index + 1}.pdf'),
                icon: const Icon(Icons.download_outlined, size: 17),
                label: Text(l10n.download),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
