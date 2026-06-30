import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD3zf6YhWFqOKDJmwUHNakCPd5XIpLycnY',
    appId: '1:103742206612:web:654b9d88ea4c219709fa81',
    messagingSenderId: '103742206612',
    projectId: 'lucifax-kickdirty',
    authDomain: 'lucifax-kickdirty.firebaseapp.com',
    storageBucket: 'lucifax-kickdirty.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD3zf6YhWFqOKDJmwUHNakCPd5XIpLycnY',
    appId: '1:103742206612:android:397f969390814bdf09fa81',
    messagingSenderId: '103742206612',
    projectId: 'lucifax-kickdirty',
    storageBucket: 'lucifax-kickdirty.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD3zf6YhWFqOKDJmwUHNakCPd5XIpLycnY',
    appId: '1:103742206612:ios:397f969390814bdf09fa81', // Fallback placeholder
    messagingSenderId: '103742206612',
    projectId: 'lucifax-kickdirty',
    storageBucket: 'lucifax-kickdirty.firebasestorage.app',
  );
}
