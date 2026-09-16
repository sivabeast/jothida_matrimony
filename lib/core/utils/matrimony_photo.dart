/// Keeps AUTHENTICATION identity and MATRIMONY profile data apart (spec §6 /
/// §17).
///
/// A member may sign in with Google, but their Google account picture is
/// **not** their matrimony profile photo and must never be shown as one — not
/// on their own profile, not in the admin view, not on match cards, not in
/// search results, and never as a fallback when they have not uploaded one.
/// The only image the app displays is the one the member explicitly uploaded
/// (`profiles/{id}.photos` / the `users/{uid}.photoUrl` mirror of it); with no
/// upload the UI shows the app's own placeholder.
///
/// Two layers enforce that:
///   1. the user document is never SEEDED from `FirebaseAuth.User.photoURL`
///      (see `FirestoreService.createOrUpdateUserOnLogin`); and
///   2. [matrimonyPhotoUrl] filters anything that still looks like a provider
///      avatar at READ time, so documents written before this rule existed
///      cannot leak one either.
library;

/// Hosts that serve identity-provider avatars. A URL on one of these is an
/// account picture, never an uploaded matrimony photo — the app's own uploads
/// go to Cloudinary / Firebase Storage.
const List<String> kAuthAvatarHosts = [
  'googleusercontent.com',
  'graph.facebook.com',
  'platform-lookaside.fbsbx.com',
];

/// True when [url] is an identity-provider avatar rather than an uploaded
/// matrimony photo.
bool isAuthProviderPhoto(String? url) {
  final u = (url ?? '').trim().toLowerCase();
  if (u.isEmpty) return false;
  return kAuthAvatarHosts.any(u.contains);
}

/// The matrimony profile photo to display, or `''` when there is none.
///
/// Pass the profile photo first and the denormalized account mirror second.
/// Anything that turns out to be a provider avatar is dropped, so the caller
/// falls through to the app's placeholder instead of showing a Google picture.
String matrimonyPhotoUrl(String? profilePhotoUrl, [String? accountPhotoUrl]) {
  final p = (profilePhotoUrl ?? '').trim();
  if (p.isNotEmpty && !isAuthProviderPhoto(p)) return p;
  final a = (accountPhotoUrl ?? '').trim();
  if (a.isNotEmpty && !isAuthProviderPhoto(a)) return a;
  return '';
}

/// True when [url] is an upload inside [uid]'s OWN Cloudinary folder
/// (`jothida_matrimony/profiles/{uid}/…`) — the deterministic user ↔ asset
/// mapping every profile upload uses. A recovered photo must pass this, so a
/// repair can never attach another member's image to a profile.
bool isMemberCloudinaryAsset(String? url, String uid) {
  final u = (url ?? '').trim();
  if (u.isEmpty || uid.trim().isEmpty) return false;
  return u.contains('res.cloudinary.com') &&
      u.contains('/jothida_matrimony/profiles/${uid.trim()}/');
}

/// The Cloudinary cloud every upload in this app goes to (see
/// `CloudinaryStorageService.cloudName`).
const String kAppCloudinaryCloud = 'dh8hzjx5q';

/// True when [url] is an IMAGE delivered by this app's Cloudinary account —
/// i.e. something a member (or an admin) uploaded through the app, as opposed
/// to an identity-provider avatar or an arbitrary link. Independent of the
/// folder, so it also holds for accounts whose Cloudinary folders are not part
/// of the delivery URL.
bool isAppCloudinaryImage(String? url) {
  final u = (url ?? '').trim();
  return u.startsWith('https://res.cloudinary.com/$kAppCloudinaryCloud/image/upload/');
}

/// The photo a LEGACY profile document still references outside
/// `profilePhotoUrl`, or `''`.
///
/// Before one-photo-per-member, a profile carried `profilePhotoUrl` plus an
/// `additionalPhotos` list, and an older edit path wrote a `photos` array. A
/// document whose `profilePhotoUrl` was never set (or was blanked) but still
/// lists an uploaded image in one of those arrays displayed that image under the
/// old model — and showed NOTHING after the model switched to reading
/// `profilePhotoUrl` only, although the Cloudinary asset was still there. This
/// is the read-side recovery of that mapping; `reconcileMemberPrivacy` writes it
/// back into `profilePhotoUrl`.
String legacyProfilePhoto(Map<String, dynamic> data) {
  for (final key in const ['photos', 'additionalPhotos']) {
    final list = data[key];
    if (list is! List) continue;
    for (final entry in list) {
      final url = entry is String ? entry.trim() : '';
      if (url.isNotEmpty && !isAuthProviderPhoto(url)) return url;
    }
  }
  return '';
}
