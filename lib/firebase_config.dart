/// Paste your Firebase web app config here (Firebase console → Project
/// settings → Your apps → Web app → SDK setup and configuration).
///
/// Once these values are filled in, live tracking switches from simulation
/// mode to real Firebase streaming on web. For Android, also add the
/// `google-services.json` file to `android/app/` (see README).
import 'package:firebase_core/firebase_core.dart';

class FirebaseConfig {
  static const String apiKey = 'PASTE_YOUR_API_KEY';
  static const String projectId = 'PASTE_YOUR_PROJECT_ID';
  static const String messagingSenderId = 'PASTE_YOUR_SENDER_ID';
  static const String appId = 'PASTE_YOUR_APP_ID';
  static const String storageBucket = 'PASTE_YOUR_STORAGE_BUCKET';

  static bool get webConfigured =>
      !apiKey.startsWith('PASTE_') &&
      !projectId.startsWith('PASTE_') &&
      !appId.startsWith('PASTE_');

  static FirebaseOptions get webOptions => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        authDomain: '$projectId.firebaseapp.com',
        storageBucket: storageBucket,
      );
}
