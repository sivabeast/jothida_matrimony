// File generated for Jothida Matrimony — Firebase project `matrimony-app-bd0d5`.
//
// Generated from android/app/google-services.json (Project Settings > Your apps
// > Jothida Matrimony [Android]). This project currently targets Android only.
//
// If iOS/Web/macOS support is added later, run:
//   flutterfire configure --project=matrimony-app-bd0d5
// to add those platform blocks, or paste values manually from the
// Firebase Console > Project settings > Your apps.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'this project currently targets Android only. '
        'Run `flutterfire configure` to add web support.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for iOS - '
          'this project currently targets Android only. '
          'Run `flutterfire configure` to add iOS support.',
        );
      default:
        return android;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDgmSX5-uwCa-e8anHt6wYjnwca9PJoWm0',
    appId: '1:560906592127:android:0fa605b5a85ff77d4e444a',
    messagingSenderId: '560906592127',
    projectId: 'matrimony-app-bd0d5',
    storageBucket: 'matrimony-app-bd0d5.firebasestorage.app',
  );
}
