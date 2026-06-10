// File generated for Jothida Matrimony — PLACEHOLDER VALUES.
//
// These are structurally-valid but FAKE Firebase config values. They let
// Firebase.initializeApp() succeed so the app launches and the UI (frontend)
// can be reviewed, without needing a real Firebase project yet.
//
// Once a real Firebase project is created for "Jothida Matrimony", replace
// this file by running:
//   dart pub global activate flutterfire_cli
//   flutterfire configure
// or manually paste the values from Firebase Console > Project settings.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA0000000000000000000000000000000000',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'jothida-matrimony-placeholder',
    storageBucket: 'jothida-matrimony-placeholder.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA0000000000000000000000000000000000',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'jothida-matrimony-placeholder',
    storageBucket: 'jothida-matrimony-placeholder.appspot.com',
    iosBundleId: 'com.jothida.jothidaMatrimony',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA0000000000000000000000000000000000',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'jothida-matrimony-placeholder',
    storageBucket: 'jothida-matrimony-placeholder.appspot.com',
  );
}
