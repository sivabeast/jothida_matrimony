/// Resolving a Cloudinary asset's `public_id` (and resource type) from the
/// `secure_url` the upload returned.
///
/// Deleting an asset needs its `public_id`, not its URL. Rather than migrating
/// every stored document to carry a second field — and leaving every EXISTING
/// image undeletable — the id is derived from the URL, which is deterministic:
/// Cloudinary builds the URL from the public_id, so it is always recoverable.
///
///   https://res.cloudinary.com/<cloud>/image/upload/v1712345678/profiles/u1/x.jpg
///                                     ^resource ^type  ^version  ^-- public_id --^
///
/// Returns null for anything that is not a Cloudinary delivery URL, so a
/// non-Cloudinary image (or an empty field) is simply skipped rather than
/// producing a bogus delete request.
library;

class CloudinaryAssetRef {
  /// The id Cloudinary's destroy API expects, e.g. `profiles/u1/x`.
  final String publicId;

  /// `image`, `video` or `raw` — a PDF uploaded through this app is `raw`.
  final String resourceType;

  const CloudinaryAssetRef({
    required this.publicId,
    required this.resourceType,
  });

  @override
  String toString() => '$resourceType:$publicId';

  @override
  bool operator ==(Object other) =>
      other is CloudinaryAssetRef &&
      other.publicId == publicId &&
      other.resourceType == resourceType;

  @override
  int get hashCode => Object.hash(publicId, resourceType);
}

/// Parses a Cloudinary delivery URL into the reference needed to delete it.
///
/// Handles the version segment (`/v1712345678/`), on-the-fly transformation
/// segments (`/w_400,h_400,c_fill/`) and the file extension, all of which are
/// part of the URL but NOT part of the public_id.
CloudinaryAssetRef? cloudinaryRefFromUrl(String? url) {
  final raw = (url ?? '').trim();
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.host.contains('cloudinary.com')) return null;

  final segs = uri.pathSegments;
  // .../<cloud>/<resourceType>/upload/<...>/<public_id>.<ext>
  final uploadAt = segs.indexOf('upload');
  if (uploadAt <= 0 || uploadAt + 1 >= segs.length) return null;

  final resourceType = segs[uploadAt - 1];
  var rest = segs.sublist(uploadAt + 1);

  // Drop the version segment, and any transformation segment before it. A
  // transformation looks like "w_400,h_400,c_fill" — key_value pairs joined by
  // commas — and never appears after the version.
  final versionAt =
      rest.indexWhere((s) => RegExp(r'^v\d+$').hasMatch(s));
  if (versionAt >= 0) {
    rest = rest.sublist(versionAt + 1);
  } else {
    while (rest.length > 1 && _looksLikeTransformation(rest.first)) {
      rest = rest.sublist(1);
    }
  }
  if (rest.isEmpty) return null;

  // The extension is not part of the public_id.
  final joined = rest.join('/');
  final dot = joined.lastIndexOf('.');
  final publicId = dot > 0 ? joined.substring(0, dot) : joined;
  if (publicId.isEmpty) return null;

  return CloudinaryAssetRef(
    publicId: publicId,
    resourceType: resourceType.isEmpty ? 'image' : resourceType,
  );
}

/// Every distinct asset referenced by [urls], skipping blanks and non-Cloudinary
/// links. De-duplicated so the same image linked twice is deleted once.
List<CloudinaryAssetRef> cloudinaryRefsFromUrls(Iterable<String?> urls) {
  final out = <CloudinaryAssetRef>{};
  for (final u in urls) {
    final ref = cloudinaryRefFromUrl(u);
    if (ref != null) out.add(ref);
  }
  return out.toList();
}

/// A display-sized delivery URL for a Cloudinary IMAGE, or [url] unchanged for
/// anything else (a PDF, a non-Cloudinary link, an already-transformed URL).
///
/// Every upload is stored at full camera resolution, and every card, avatar
/// and thumbnail used to download that original — megabytes per profile on a
/// Matches page. Cloudinary resizes on delivery: `c_limit,w_<w>` scales down
/// (never up) and `q_auto` picks an efficient quality. The width is rounded up
/// to a 200 px bucket so nearby sizes share one cached file. The ORIGINAL URL
/// stays the stored value and is what the full-screen viewer opens.
///
/// Format is deliberately left as uploaded (no `f_auto`): `f_auto` can serve
/// AVIF, which Flutter's decoder does not support on every device.
String cloudinaryDisplayUrl(String url, {required double width}) {
  final raw = url.trim();
  if (raw.isEmpty || !raw.contains('res.cloudinary.com')) return raw;
  const marker = '/image/upload/';
  final at = raw.indexOf(marker);
  if (at < 0) return raw;
  final rest = raw.substring(at + marker.length);
  final firstSegment = rest.split('/').first;
  if (_looksLikeTransformation(firstSegment)) return raw;
  if (!width.isFinite || width <= 0) return raw;
  final bucket = (((width / 200).ceil()) * 200).clamp(200, 1600);
  return '${raw.substring(0, at + marker.length)}c_limit,w_$bucket,q_auto/$rest';
}

bool _looksLikeTransformation(String seg) =>
    seg.contains('_') &&
    seg.split(',').every((p) => RegExp(r'^[a-z]+_[^,]+$').hasMatch(p));
