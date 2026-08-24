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
