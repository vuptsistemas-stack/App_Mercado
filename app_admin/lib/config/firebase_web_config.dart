import 'package:firebase_core/firebase_core.dart';

class FirebaseWebConfig {
  FirebaseWebConfig._();

  static const String vapidKey = String.fromEnvironment(
    'FIREBASE_WEB_VAPID_KEY',
    defaultValue:
        'BKThWLbI6avgfDYfxdjO11jzeTR6zxjQlooX60PLQi1Y1Hf6YxC2cRmbCvPTU1c3ncvDwG_wl8tROH-oTH7iQ64',
  );

  static const FirebaseOptions options = FirebaseOptions(
    apiKey: 'AIzaSyASSL7OZ6H9neFQj2od221GgSri0ngr2fU',
    appId: '1:491158654376:web:83e2e2de2f86de3bc6219d',
    messagingSenderId: '491158654376',
    projectId: 'aplicativo-admin-e5b92',
    authDomain: 'aplicativo-admin-e5b92.firebaseapp.com',
    storageBucket: 'aplicativo-admin-e5b92.firebasestorage.app',
    measurementId: 'G-X3VXQMH34S',
  );
}
