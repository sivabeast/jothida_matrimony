import 'package:flutter/material.dart';

import '../../models/banner_model.dart';
import '../common/network_photo.dart';

/// Renders ONE admin-managed Home banner — shared by the Home carousel and the
/// admin Banner Management live preview so what the admin sees is exactly what
/// users get.
///
///  • IMAGE banner → the uploaded artwork, edge-to-edge (offers/posters carry
///    their own text inside the image).
///  • TEXT banner  → title / subtitle / description over the configured
///    background colour, with the configured text colour, size and alignment.
class HomeBannerSlide extends StatelessWidget {
  final HomeBannerModel banner;
  const HomeBannerSlide({super.key, required this.banner});

  @override
  Widget build(BuildContext context) {
    if (banner.isImage) {
      return NetworkPhoto(
        url: banner.imageUrl,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        fallbackIcon: Icons.image_outlined,
        showLoadingSpinner: true,
      );
    }

    final titleSize = banner.fontSize > 0 ? banner.fontSize : 22.0;
    final subtitleSize = (titleSize * 0.62).clamp(11.0, 18.0);
    final bodySize = (titleSize * 0.55).clamp(10.5, 16.0);

    return Container(
      color: banner.bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      alignment: switch (banner.textAlign) {
        'center' => Alignment.center,
        'right' => Alignment.centerRight,
        _ => Alignment.centerLeft,
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: banner.crossAlignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (banner.title.trim().isNotEmpty)
            Text(
              banner.title,
              textAlign: banner.textAlignment,
              style: TextStyle(
                color: banner.fgColor,
                fontSize: titleSize,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
            ),
          if (banner.subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              banner.subtitle,
              textAlign: banner.textAlignment,
              style: TextStyle(
                color: banner.fgColor.withOpacity(0.92),
                fontSize: subtitleSize,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
          if (banner.description.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              banner.description,
              textAlign: banner.textAlignment,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: banner.fgColor.withOpacity(0.85),
                fontSize: bodySize,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
