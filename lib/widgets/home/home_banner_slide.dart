import 'package:flutter/material.dart';

import '../../models/banner_model.dart';
import '../common/network_photo.dart';

/// Renders ONE admin-uploaded Home banner — shared by the Home carousel and the
/// admin Banner Management list, so what the admin uploads is EXACTLY what
/// users get.
///
/// The artwork is shown edge-to-edge with nothing painted over it: no title,
/// description, button or template overlay. Any promotional text belongs in the
/// uploaded image itself.
class HomeBannerSlide extends StatelessWidget {
  final HomeBannerModel banner;
  const HomeBannerSlide({super.key, required this.banner});

  @override
  Widget build(BuildContext context) => NetworkPhoto(
        url: banner.imageUrl,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        fallbackIcon: Icons.image_outlined,
        showLoadingSpinner: true,
      );
}
