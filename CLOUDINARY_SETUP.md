# Cloudinary Setup — Profile Media Uploads

Profile photos, horoscope PDFs/images, and ID-proof documents are uploaded to
**Cloudinary** (not Firebase Storage). This avoids the Firebase **Blaze**
billing-plan requirement for Storage.

## How it works

```
Pick image (image_picker)
   → CloudinaryStorageService (unsigned upload, multipart POST)
   → Cloudinary returns { secure_url, public_id, ... }
   → secure_url saved into Firestore (profiles/{id}.photos[],
     profiles/{id}.horoscopeDetails.horoscopePdfUrl)
   → cached_network_image displays the secure_url throughout the app
```

- `lib/services/storage_service.dart` — abstract `StorageService` interface
  used everywhere else in the app (UI, providers, repositories).
- `lib/services/cloudinary/cloudinary_storage_service.dart` — the active
  implementation. Uses an **unsigned upload preset**, so only the cloud name
  and preset name are needed on the client.
- `lib/services/firebase/storage_service.dart` — `FirebaseStorageService`,
  an alternate implementation of the same interface. To switch back once the
  Firebase project is on the Blaze plan, change one line in
  `lib/providers/service_providers.dart`:

  ```dart
  final storageServiceProvider =
      Provider<StorageService>((ref) => FirebaseStorageService());
  ```

  No UI/provider/repository code needs to change either way.

## Current configuration

| Setting | Value |
|---|---|
| Cloud name | `dh8hzjx5q` |
| Upload preset | `matrimony_profiles` (Unsigned) |
| Folder layout | `jothida_matrimony/profiles/{userId}/photos/photo_0.jpg`, `.../horoscope/horoscope.pdf`, `.../id_proof/{docType}.jpg` |

These are set as defaults inside `CloudinaryStorageService`. If you ever need
to change them (e.g. a different Cloudinary account), update the constructor
defaults or pass values explicitly when constructing it in
`lib/providers/service_providers.dart`.

## ⚠️ API secret

Cloudinary's **API secret** must **never** be placed in the Flutter app — it
would be extractable from the compiled APK/IPA and would let anyone delete or
overwrite any asset on your account. This project only uses the **cloud
name** and an **unsigned upload preset**, neither of which is secret.

Because of this, `CloudinaryStorageService.deleteFile` and
`deleteProfilePhotos` are intentionally **no-ops** — deleting/overwriting
assets requires a *signed* admin request. If you need real deletes:

1. Create a small trusted backend (e.g. a Cloud Function) that holds the API
   secret and exposes a `deleteAsset(publicId)` endpoint.
2. Call that endpoint from `CloudinaryStorageService.deleteFile` instead of
   no-op'ing.

## Verifying the upload preset

In the Cloudinary Console → **Settings → Upload → Upload presets**, confirm
`matrimony_profiles`:

- **Signing mode**: `Unsigned`
- (Optional, for "edit profile photo" to overwrite cleanly) **Unique
  filename**: off, **Overwrite**: on

If the preset is missing or signed, uploads will fail with a `400` error and
the app shows: *"the Cloudinary upload preset 'matrimony_profiles' is missing
or not set to 'Unsigned'"*.

## Retry & progress

`CloudinaryStorageService` retries failed uploads up to 3 times with
exponential backoff (1s, 2s) for network/5xx errors; 4xx errors (bad preset,
validation) fail immediately without retrying. The profile-creation screen
(Step 7) shows a progress bar and status text ("Uploading 2 photos...",
"Uploading horoscope PDF...", "Saving your profile...") while
`profileCreationProvider` is loading. If an upload ultimately fails, the
SnackBar message tells the user to tap **Submit Profile** again to retry.
