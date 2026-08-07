

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
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
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA-EnUGPvOm8KHUuMUNifRLAa6-1qNJR6E',
    appId: '1:569718802147:web:2c1d965d6cdd6da32727d6',
    messagingSenderId: '569718802147',
    projectId: 'smartnps360-d9937',
    authDomain: 'smartnps360-d9937.firebaseapp.com',
    storageBucket: 'smartnps360-d9937.firebasestorage.app',
    measurementId: 'G-REKNBY875G',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCDzmsP44t-kgOuPqQQVrqgv5eM50JKsac',
    appId: '1:569718802147:android:af9caa2c11df5c9e2727d6',
    messagingSenderId: '569718802147',
    projectId: 'smartnps360-d9937',
    storageBucket: 'smartnps360-d9937.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBbBi5P38h9YfG5Fdd1Rcc83VdrZdGKWGo',
    appId: '1:569718802147:ios:864e54bccb20ebbf2727d6',
    messagingSenderId: '569718802147',
    projectId: 'smartnps360-d9937',
    storageBucket: 'smartnps360-d9937.firebasestorage.app',
    iosBundleId: 'com.smartnps360.app',
  );
}
